import os
import tempfile

import alphashape
import numpy as np
import trimesh
from fastapi import APIRouter, BackgroundTasks
from pydantic import BaseModel
from shapely.geometry import MultiPoint, Polygon

from common import get_supabase

router = APIRouter(prefix='/spaces')


class BboxRequest(BaseModel):
    space_id: str
    n_sides: int = 40
    alpha: float = 0.5


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


def _compute_bounding_box(space_id: str, n_sides: int = 40, alpha: float = 0.5) -> None:
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

        # Drop components whose centroid lies outside the main component's
        # bounding box (padded by 1 m) — removes distant scan artifacts while
        # keeping all valid room geometry regardless of component size.
        components = mesh.split(only_watertight=False)
        if len(components) > 1:
            main = max(components, key=lambda c: len(c.vertices))
            lo = main.bounds[0] - 1.0
            hi = main.bounds[1] + 1.0
            kept = [c for c in components if np.all(np.array(c.centroid) >= lo) and np.all(np.array(c.centroid) <= hi)]
            bbox_mesh = trimesh.util.concatenate(kept) if kept else main
        else:
            bbox_mesh = mesh

        verts = np.array(bbox_mesh.vertices)
        xz = verts[:, [0, 2]]

        shape = alphashape.alphashape(xz, alpha)
        # Fall back to convex hull if alpha produces a degenerate/multipart result
        if not isinstance(shape, Polygon) or shape.is_empty:
            shape = MultiPoint(xz).convex_hull

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
    background_tasks.add_task(_compute_bounding_box, req.space_id, req.n_sides, req.alpha)
    return {'status': 'computing', 'space_id': req.space_id, 'n_sides': req.n_sides, 'alpha': req.alpha}
