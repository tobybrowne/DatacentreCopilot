from __future__ import annotations
import logging
import os
import tempfile
from concurrent.futures import ThreadPoolExecutor, as_completed

import numpy as np
import trimesh
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from scipy import ndimage
from scipy.spatial.transform import Rotation
from shapely.geometry import Polygon as ShapelyPolygon
from shapely.ops import unary_union

from common import get_supabase, require_auth

logger = logging.getLogger(__name__)
router = APIRouter(prefix='/mesh-rooms')

GRID_RES = 0.10      # 10 cm grid resolution
WALL_DILATE = 1      # 1-cell dilation to thicken thin scan surfaces
POLY_SUBSAMPLE = 4   # 4× downscale for polygon extraction (→ 40 cm cells)


class MeshSegmentRequest(BaseModel):
    building_id: str
    min_passage_width: float = 0.8  # m; passages narrower than this are treated as doorways
    cut_height_offset: float = 1.2  # m above floor for cross-section
    min_room_area: float = 2.0      # m²; smaller regions are merged into neighbours


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
        return mesh
    finally:
        os.unlink(tmp)


def _rigid_to_matrix(t: dict) -> np.ndarray:
    pos = t['position']
    q = t['quaternion']
    R = Rotation.from_quat([q['x'], q['y'], q['z'], q['w']]).as_matrix()
    mat = np.eye(4)
    mat[:3, :3] = R
    mat[:3, 3] = [pos['x'], pos['y'], pos['z']]
    return mat


def _cross_section_segments(mesh: trimesh.Trimesh, cut_y: float) -> list[tuple]:
    section = mesh.section(plane_origin=[0.0, cut_y, 0.0], plane_normal=[0.0, 1.0, 0.0])
    if section is None:
        return []
    verts = section.vertices
    segments = []
    for entity in section.entities:
        pts = entity.points
        for i in range(len(pts) - 1):
            x1, _, z1 = verts[pts[i]]
            x2, _, z2 = verts[pts[i + 1]]
            if abs(x1 - x2) > 1e-6 or abs(z1 - z2) > 1e-6:
                segments.append(((float(x1), float(z1)), (float(x2), float(z2))))
    return segments


def _rasterize(segments: list[tuple], grid_res: float) -> tuple[np.ndarray | None, float, float]:
    if not segments:
        return None, 0.0, 0.0

    all_pts = [pt for seg in segments for pt in seg]
    xs = [p[0] for p in all_pts]
    zs = [p[1] for p in all_pts]
    x_min = min(xs) - 1.0
    z_min = min(zs) - 1.0
    x_max = max(xs) + 1.0
    z_max = max(zs) + 1.0

    ncols = int((x_max - x_min) / grid_res) + 2
    nrows = int((z_max - z_min) / grid_res) + 2
    grid = np.zeros((nrows, ncols), dtype=bool)

    for (x1, z1), (x2, z2) in segments:
        c1 = int((x1 - x_min) / grid_res)
        r1 = int((z1 - z_min) / grid_res)
        c2 = int((x2 - x_min) / grid_res)
        r2 = int((z2 - z_min) / grid_res)
        dc, dr = abs(c2 - c1), abs(r2 - r1)
        sc, sr = (1 if c1 < c2 else -1), (1 if r1 < r2 else -1)
        err, c, r = dc - dr, c1, r1
        while True:
            if 0 <= r < nrows and 0 <= c < ncols:
                grid[r, c] = True
            if c == c2 and r == r2:
                break
            e2 = 2 * err
            if e2 > -dr:
                err -= dr
                c += sc
            if e2 < dc:
                err += dc
                r += sr

    if WALL_DILATE > 0:
        struct = ndimage.generate_binary_structure(2, 2)
        grid = ndimage.binary_dilation(grid, structure=struct, iterations=WALL_DILATE)

    return grid, x_min, z_min


def _label_rooms(wall_grid: np.ndarray, min_passage_width: float, grid_res: float) -> np.ndarray | None:
    free = ~wall_grid
    erosion_cells = max(1, round(min_passage_width / 2 / grid_res))
    struct = ndimage.generate_binary_structure(2, 2)
    cores = ndimage.binary_erosion(free, structure=struct, iterations=erosion_cells)

    labeled_cores, n = ndimage.label(cores, structure=np.ones((3, 3)))
    if n == 0:
        return None

    # Assign every free cell to the nearest core via EDT.
    # distance_transform_edt treats zeros as targets; (labeled_cores == 0) makes
    # core cells zero so indices point to the nearest core for each cell.
    _, indices = ndimage.distance_transform_edt(labeled_cores == 0, return_indices=True)
    labels = labeled_cores[indices[0], indices[1]]
    labels[~free] = 0
    return labels


def _filter_small(labels: np.ndarray, grid_res: float, min_area_m2: float) -> np.ndarray:
    min_cells = max(1, int(min_area_m2 / grid_res ** 2))
    n = int(labels.max())
    sizes = {i: int(np.sum(labels == i)) for i in range(1, n + 1)}
    large = {i for i, s in sizes.items() if s >= min_cells}
    if not large:
        return labels

    centroids = {i: np.argwhere(labels == i).mean(axis=0) for i in large}
    result = labels.copy()
    for i in range(1, n + 1):
        if i not in large:
            cells = np.argwhere(labels == i)
            if len(cells) == 0:
                continue
            cen = cells.mean(axis=0)
            nearest = min(large, key=lambda lr: np.linalg.norm(centroids[lr] - cen))
            result[labels == i] = nearest

    final = np.zeros_like(result)
    for new_id, old_id in enumerate(sorted(large), start=1):
        final[result == old_id] = new_id
    return final


def _extract_polygon(mask: np.ndarray, x_min: float, z_min: float, grid_res: float) -> list[list[float]] | None:
    sub = mask[::POLY_SUBSAMPLE, ::POLY_SUBSAMPLE]
    rows, cols = np.argwhere(sub).T
    if len(rows) == 0:
        return None
    sub_res = grid_res * POLY_SUBSAMPLE
    polys = [
        ShapelyPolygon([
            (x_min + c * sub_res,           z_min + r * sub_res),
            (x_min + (c + 1) * sub_res,     z_min + r * sub_res),
            (x_min + (c + 1) * sub_res,     z_min + (r + 1) * sub_res),
            (x_min + c * sub_res,           z_min + (r + 1) * sub_res),
        ])
        for r, c in zip(rows, cols)
    ]
    merged = unary_union(polys).simplify(sub_res * 0.5)
    if merged.is_empty:
        return None
    if merged.geom_type == 'MultiPolygon':
        merged = max(merged.geoms, key=lambda g: g.area)
    return [[round(float(x), 4), round(float(z), 4)] for x, z in merged.exterior.coords[:-1]]


@router.post('/segment')
async def segment(req: MeshSegmentRequest, _: None = Depends(require_auth)) -> list[dict]:
    sb = get_supabase()

    rows = (
        sb.table('spaces')
        .select('id, glb_path, offset_transformation')
        .eq('building_id', req.building_id)
        .execute()
        .data
    )
    if not rows:
        raise HTTPException(404, f'No spaces found for building {req.building_id}')

    def _fetch_mesh(row: dict) -> trimesh.Trimesh | None:
        glb_path = row.get('glb_path')
        if not glb_path:
            return None
        data = sb.storage.from_('spaces_bucket').download(glb_path)
        mesh = _load_mesh(data)
        transform = row.get('offset_transformation')
        if transform:
            mesh.apply_transform(_rigid_to_matrix(transform))
        return mesh

    meshes: list[trimesh.Trimesh] = []
    with ThreadPoolExecutor(max_workers=6) as pool:
        futures = {pool.submit(_fetch_mesh, r): r for r in rows}
        for fut in as_completed(futures):
            result = fut.result()
            if result is not None:
                meshes.append(result)

    if not meshes:
        raise HTTPException(400, 'No valid meshes found for this building')

    combined = trimesh.util.concatenate(meshes) if len(meshes) > 1 else meshes[0]
    y_floor = float(np.percentile(combined.vertices[:, 1], 5))
    y_ceil = float(combined.bounds[1][1])
    cut_y = y_floor + req.cut_height_offset

    if cut_y >= y_ceil:
        raise HTTPException(400, f'cut_height_offset {req.cut_height_offset}m exceeds building height')

    logger.info(f'[mesh-rooms] cross-section at y={cut_y:.3f} (floor={y_floor:.3f}, {len(meshes)} spaces)')

    segments = _cross_section_segments(combined, cut_y)
    if not segments:
        raise HTTPException(400, 'No wall geometry at cross-section height — try adjusting cut_height_offset')

    logger.info(f'[mesh-rooms] {len(segments)} wall segments, rasterising at {GRID_RES}m')

    wall_grid, x_min, z_min = _rasterize(segments, GRID_RES)
    if wall_grid is None:
        raise HTTPException(400, 'Rasterisation failed')

    labels = _label_rooms(wall_grid, req.min_passage_width, GRID_RES)
    if labels is None:
        raise HTTPException(400, 'No rooms detected — try reducing min_passage_width')

    labels = _filter_small(labels, GRID_RES, req.min_room_area)
    n_rooms = int(labels.max())
    logger.info(f'[mesh-rooms] {n_rooms} rooms after filtering')

    result = []
    for room_id in range(1, n_rooms + 1):
        coords = _extract_polygon(labels == room_id, x_min, z_min, GRID_RES)
        if coords and len(coords) >= 3:
            result.append({
                'polygon_2d': coords,
                'y_min': round(y_floor, 4),
                'y_max': round(y_ceil, 4),
            })

    return result
