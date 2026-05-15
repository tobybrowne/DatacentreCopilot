import io
import os
import tempfile

import numpy as np
import trimesh
from fastapi import APIRouter, BackgroundTasks, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from scipy.spatial.transform import Rotation
from shapely import concave_hull
from shapely.geometry import MultiPoint

from common import get_supabase

router = APIRouter(prefix='/spaces')


class BboxRequest(BaseModel):
    space_id: str
    n_sides: int = 40
    ratio: float = 0.3


def _sample_perimeter(pts: np.ndarray, n: int) -> np.ndarray:
    """Resample a convex polygon to n evenly-spaced points along its perimeter."""
    m = len(pts)
    closed = np.vstack([pts, pts[0]])
    seg_lens = np.linalg.norm(np.diff(closed, axis=0), axis=1)
    cum = np.concatenate([[0.0], np.cumsum(seg_lens)])
    total = cum[-1]
    result = []
    for t in np.linspace(0, total, n, endpoint=False):
        seg = min(int(np.searchsorted(cum[1:], t, side='right')), m - 1)
        alpha = (t - cum[seg]) / seg_lens[seg] if seg_lens[seg] > 1e-12 else 0.0
        result.append(pts[seg] + alpha * (pts[(seg + 1) % m] - pts[seg]))
    return np.array(result)


def _compute_bounding_box(space_id: str, n_sides: int = 40, ratio: float = 0.3) -> None:
    sb = get_supabase()

    row = (
        sb.table('spaces')
        .select('glb_path')
        .eq('id', space_id)
        .single()
        .execute()
        .data
    )
    if not row or not row.get('glb_path'):
        raise ValueError(f'No glb_path for space {space_id}')

    glb_bytes = sb.storage.from_('spaces_bucket').download(row['glb_path'])

    with tempfile.NamedTemporaryFile(suffix='.glb', delete=False) as f:
        f.write(glb_bytes)
        tmp = f.name

    try:
        loaded = trimesh.load(tmp, force='mesh')
        if isinstance(loaded, trimesh.Scene):
            mesh = trimesh.util.concatenate(list(loaded.geometry.values()))
        else:
            mesh = loaded

        verts = np.array(mesh.vertices)

        # Drop floating islands using voxel-based XZ connectivity.
        # Mesh-face adjacency is unreliable for GLB scans (submeshes don't share edges),
        # so we voxelise the vertex positions and BFS over occupied cells instead.
        # decreasing this value makes the algorithm more aggressively filter "floating" sections
        VOXEL = 0.05
        cx = np.floor(verts[:, 0] / VOXEL).astype(int)
        cz = np.floor(verts[:, 2] / VOXEL).astype(int)

        cell_to_indices: dict = {}
        for i, (x, z) in enumerate(zip(cx, cz)):
            cell_to_indices.setdefault((x, z), []).append(i)

        occupied = set(cell_to_indices.keys())
        visited: set = set()
        components: list = []

        for start in occupied:
            if start in visited:
                continue
            component: list = []
            queue = [start]
            while queue:
                cell = queue.pop()
                if cell in visited:
                    continue
                visited.add(cell)
                component.append(cell)
                x, z = cell
                for nb in ((x+1, z), (x-1, z), (x, z+1), (x, z-1)):
                    if nb in occupied and nb not in visited:
                        queue.append(nb)
            components.append(component)

        if len(components) > 1:
            largest = max(components, key=len)
            keep = set()
            for cell in largest:
                keep.update(cell_to_indices[cell])
            verts = verts[sorted(keep)]

        xz = verts[:, [0, 2]]

        shape = concave_hull(MultiPoint(xz), ratio=ratio)

        hull_pts = np.array(shape.exterior.coords[:-1])  # drop repeated closing vertex

        if len(hull_pts) > n_sides:
            hull_pts = _sample_perimeter(hull_pts, n_sides)

        bounding_box = {
            'vertices_2d': [[float(p[0]), float(p[1])] for p in hull_pts],
            'y_min': float(verts[:, 1].min()),
            'y_max': float(verts[:, 1].max()),
        }
    finally:
        os.unlink(tmp)

    sb.table('spaces').update({'bounding_box': bounding_box}).eq('id', space_id).execute()
    print(f'[spaces] computed bounding_box (n={len(bounding_box["vertices_2d"])}) for {space_id}')


@router.post('/compute-bbox')
async def compute_bbox(req: BboxRequest, background_tasks: BackgroundTasks) -> dict:
    """Compute and store the N-gon prism footprint for a space's GLB. Runs in background."""
    background_tasks.add_task(_compute_bounding_box, req.space_id, req.n_sides, req.ratio)
    return {'status': 'computing', 'space_id': req.space_id, 'n_sides': req.n_sides, 'ratio': req.ratio}
