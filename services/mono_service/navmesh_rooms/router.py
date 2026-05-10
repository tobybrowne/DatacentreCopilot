import tempfile
import os
from datetime import datetime

import numpy as np
import trimesh
import networkx as nx
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from shapely.ops import unary_union
from shapely.geometry import Polygon as ShapelyPolygon

from common import get_supabase, require_auth

router = APIRouter(prefix='/navmesh-rooms')

PALETTE = np.array([
    [0,   212, 255, 200],
    [255,  80,  80, 200],
    [80,  255, 120, 200],
    [255, 200,   0, 200],
    [180,  80, 255, 200],
    [255, 140,   0, 200],
    [0,   180, 255, 200],
    [255,  60, 180, 200],
    [60,  220, 180, 200],
    [200, 255,  60, 200],
    [255, 160, 120, 200],
    [120, 120, 255, 200],
], dtype=np.uint8)

OUTPUT_DIR = os.environ.get('NAVMESH_OUTPUT_DIR', os.path.join(os.path.dirname(__file__), '..', 'navmesh_rooms_output'))


class SegmentRequest(BaseModel):
    navmesh_id: str
    resolution: float = 0.2


def _load_mesh(data: bytes) -> trimesh.Trimesh:
    with tempfile.NamedTemporaryFile(suffix='.glb', delete=False) as f:
        f.write(data)
        tmp = f.name
    try:
        scene = trimesh.load(tmp, force='scene')
        if isinstance(scene, trimesh.Scene):
            meshes = list(scene.geometry.values())
            if not meshes:
                raise ValueError('No geometry in GLB')
            mesh = trimesh.util.concatenate(meshes)
        else:
            mesh = scene
        if not isinstance(mesh, trimesh.Trimesh):
            raise ValueError(f'Expected triangle mesh, got {type(mesh)}')
        mesh.merge_vertices()
        return mesh
    finally:
        os.unlink(tmp)


def _build_dual_graph(mesh: trimesh.Trimesh) -> nx.Graph:
    G = nx.Graph()
    G.add_nodes_from(range(len(mesh.faces)))
    for (fi, fj), (vi, vj) in zip(mesh.face_adjacency, mesh.face_adjacency_edges):
        width = float(np.linalg.norm(mesh.vertices[vi] - mesh.vertices[vj]))
        G.add_edge(int(fi), int(fj), width=width)
    print(f'[navmesh-rooms] dual graph: {len(mesh.faces)} nodes, {G.number_of_edges()} edges')
    return G


def _segment(mesh: trimesh.Trimesh, min_area: float = 2.0, resolution: float = 0.2) -> list[list[int]]:
    from networkx.algorithms.community import louvain_communities

    G = _build_dual_graph(mesh)
    communities = louvain_communities(G, weight='width', seed=42, resolution=resolution)
    components = sorted([list(c) for c in communities], key=len, reverse=True)

    face_areas = mesh.area_faces
    rooms, fragments = [], []
    for comp in components:
        if face_areas[comp].sum() >= min_area:
            rooms.append(comp)
        else:
            fragments.append(comp)

    if not rooms:
        rooms.append(fragments.pop(0))

    # BFS flood-fill fragments into nearest room
    face_to_room: dict[int, int] = {}
    queue: list[int] = []
    for ri, fids in enumerate(rooms):
        for fi in fids:
            face_to_room[fi] = ri
            queue.append(fi)

    G_full = G
    head = 0
    while head < len(queue):
        fi = queue[head]; head += 1
        for nb in G_full.neighbors(fi):
            if nb not in face_to_room:
                face_to_room[nb] = face_to_room[fi]
                queue.append(nb)

    room_centroids = np.array([
        mesh.vertices[mesh.faces[fids]].mean(axis=(0, 1)) for fids in rooms
    ])
    for fi in range(len(mesh.faces)):
        if fi not in face_to_room:
            fc = mesh.vertices[mesh.faces[fi]].mean(axis=0)
            face_to_room[fi] = int(np.argmin(np.linalg.norm(room_centroids - fc, axis=1)))

    result = [[] for _ in rooms]
    for fi, ri in face_to_room.items():
        result[ri].append(fi)
    return result


def _room_polygon_shape(mesh: trimesh.Trimesh, face_ids: list[int]):
    triangles = [
        ShapelyPolygon([(mesh.vertices[vi][0], mesh.vertices[vi][2]) for vi in mesh.faces[fi]])
        for fi in face_ids
    ]
    return unary_union(triangles)


def _room_polygon(mesh: trimesh.Trimesh, face_ids: list[int]) -> dict:
    shape = _room_polygon_shape(mesh, face_ids)
    if shape.geom_type == 'MultiPolygon':
        shape = max(shape.geoms, key=lambda g: g.area)
    coords = [[round(float(x), 4), round(float(z), 4)] for x, z in shape.exterior.coords[:-1]]
    y_vals = mesh.vertices[mesh.faces[face_ids].ravel(), 1]
    return {
        'polygon_2d': coords,
        'y_min': round(float(y_vals.min()), 4),
        'y_max': round(float(y_vals.max()), 4),
    }


def _export_coloured_glb(mesh: trimesh.Trimesh, rooms: list[list[int]], navmesh_id: str) -> str:
    coloured = mesh.copy()
    coloured.unmerge_vertices()
    face_colors = np.zeros((len(coloured.faces), 4), dtype=np.uint8)
    for ri, face_ids in enumerate(rooms):
        face_colors[face_ids] = PALETTE[ri % len(PALETTE)]
    coloured.visual = trimesh.visual.ColorVisuals(mesh=coloured, face_colors=face_colors)

    os.makedirs(OUTPUT_DIR, exist_ok=True)
    ts = datetime.now().strftime('%Y%m%d_%H%M%S')
    path = os.path.join(OUTPUT_DIR, f'{navmesh_id}_{ts}.glb')
    coloured.export(path)
    print(f'[navmesh-rooms] saved coloured GLB → {path}')
    return path


@router.post('/segment')
async def segment(req: SegmentRequest, _: None = Depends(require_auth)) -> list[dict]:
    sb = get_supabase()

    row = (
        sb.table('navmeshes')
        .select('glb_path')
        .eq('id', req.navmesh_id)
        .single()
        .execute()
        .data
    )
    if not row or not row.get('glb_path'):
        raise HTTPException(404, 'Navmesh GLB not found — save the navmesh first')

    data = sb.storage.from_('spaces_bucket').download(row['glb_path'])
    mesh = _load_mesh(data)
    rooms = _segment(mesh, resolution=req.resolution)
    _export_coloured_glb(mesh, rooms, req.navmesh_id)

    return [_room_polygon(mesh, fids) for fids in rooms]
