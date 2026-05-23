import os
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import open3d as o3d
import trimesh
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from scipy.spatial.transform import Rotation

from common import get_supabase, require_auth

router = APIRouter(prefix='/stitch')

NORMAL_RADIUS = 0.02  # neighbourhood radius for normal estimation
# SAMPLES_PER_M2 = 100
SAMPLES_PER_M2 = 200
USE_POINT_TO_PLANE = True  # True = point-to-plane (faster, needs good normals), False = point-to-point (slower, more robust on noisy/partial data)


class _Position(BaseModel):
    x: float
    y: float
    z: float


class _Quaternion(BaseModel):
    x: float
    y: float
    z: float
    w: float


class RigidTransform(BaseModel):
    position: _Position
    quaternion: _Quaternion


class StitchRequest(BaseModel):
    space_a_id: str
    space_b_id: str
    initial_transform: RigidTransform  # aligns space_b onto space_a


def _to_matrix(rt: RigidTransform) -> np.ndarray:
    q = rt.quaternion
    R = Rotation.from_quat([q.x, q.y, q.z, q.w]).as_matrix()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = [rt.position.x, rt.position.y, rt.position.z]
    return T


def _from_matrix(T: np.ndarray) -> dict:
    q = Rotation.from_matrix(T[:3, :3]).as_quat()
    return {
        'position': {'x': float(T[0, 3]), 'y': float(T[1, 3]), 'z': float(T[2, 3])},
        'quaternion': {'x': float(q[0]), 'y': float(q[1]), 'z': float(q[2]), 'w': float(q[3])},
    }


def _glb_bytes_to_pcd(data: bytes, label: str) -> tuple[o3d.geometry.PointCloud, dict]:
    with tempfile.NamedTemporaryFile(suffix='.glb', delete=False) as f:
        f.write(data)
        tmp = f.name
    try:
        loaded = trimesh.load(tmp, force='mesh')
        if isinstance(loaded, trimesh.Scene):
            mesh = trimesh.util.concatenate(list(loaded.geometry.values()))
        else:
            mesh = loaded

        t0 = time.perf_counter()
        n_sample = max(10_000, min(int(mesh.area * SAMPLES_PER_M2), 500_000))
        samples, _ = trimesh.sample.sample_surface(mesh, n_sample)
        pcd = o3d.geometry.PointCloud()
        pcd.points = o3d.utility.Vector3dVector(samples)
        t_sample = time.perf_counter() - t0

        t2 = time.perf_counter()
        if USE_POINT_TO_PLANE:
            pcd.estimate_normals(
                o3d.geometry.KDTreeSearchParamHybrid(radius=NORMAL_RADIUS, max_nn=30)
            )
        t_normals = time.perf_counter() - t2

        print(f'[stitch] {label}: {n_sample} pts | sample={t_sample:.2f}s normals={t_normals:.2f}s')
        return pcd, {'sample': t_sample, 'voxel': 0.0, 'normals': t_normals}
    finally:
        os.unlink(tmp)


@router.post('/refine')
async def refine(req: StitchRequest, _: None = Depends(require_auth)) -> dict:
    sb = get_supabase()

    # We also fetch space_a's offset_transformation so we can move between the
    # building's world frame (what the frontend gizmo and the stored
    # offset_transformation use) and space_a's local frame (what ICP runs in,
    # because pcd_a is loaded from raw GLB bytes with no transform applied).
    spaces = (
        sb.table('spaces')
        .select('id,glb_path,offset_transformation')
        .in_('id', [req.space_a_id, req.space_b_id])
        .execute()
        .data
    )
    by_id = {s['id']: s for s in spaces}
    space_a = by_id.get(req.space_a_id)
    space_b = by_id.get(req.space_b_id)

    if not space_a or not space_b:
        raise HTTPException(404, 'One or both spaces not found')
    if not space_a['glb_path'] or not space_b['glb_path']:
        raise HTTPException(400, 'One or both spaces have no GLB export')

    t0 = time.perf_counter()
    with ThreadPoolExecutor(max_workers=2) as ex:
        fut_a = ex.submit(sb.storage.from_('spaces_bucket').download, space_a['glb_path'])
        fut_b = ex.submit(sb.storage.from_('spaces_bucket').download, space_b['glb_path'])
        glb_a = fut_a.result()
        glb_b = fut_b.result()
    print(f'[stitch] download: {time.perf_counter() - t0:.2f}s')

    with ThreadPoolExecutor(max_workers=2) as ex:
        fut_a = ex.submit(_glb_bytes_to_pcd, glb_a, 'pcd_a')
        fut_b = ex.submit(_glb_bytes_to_pcd, glb_b, 'pcd_b')
        pcd_a, times_a = fut_a.result()
        pcd_b, times_b = fut_b.result()

    # T_a_world is where space_a sits in the building's world frame. The
    # reference space (building_index=0) defines the world frame itself and
    # has no offset_transformation, so we use identity for it.
    a_offset = space_a.get('offset_transformation')
    T_a_world = (
        _to_matrix(RigidTransform.model_validate(a_offset))
        if a_offset
        else np.eye(4)
    )

    # The frontend sends initial_transform in world frame (it's space_b's
    # gizmo pose against the rendered building). ICP works on raw point
    # clouds in their own local frames, so we have to express the initial
    # guess in space_a's local frame:
    #   T_b_local = T_a_world^-1 @ T_b_world
    T_b_world_init = _to_matrix(req.initial_transform)
    T_b_local = np.linalg.inv(T_a_world) @ T_b_world_init

    estimation = (
        o3d.pipelines.registration.TransformationEstimationPointToPlane()
        if USE_POINT_TO_PLANE else
        o3d.pipelines.registration.TransformationEstimationPointToPoint()
    )

    t_icp = time.perf_counter()
    result = o3d.pipelines.registration.registration_icp(
        pcd_b, pcd_a,
        0.1,
        T_b_local,
        estimation,
        o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=200),
    )
    t_icp_elapsed = time.perf_counter() - t_icp

    print(f'[stitch] --- summary ---')
    print(f'[stitch] 1. sample:  {times_a["sample"] + times_b["sample"]:.2f}s')
    print(f'[stitch] 2. normals: {times_a["normals"] + times_b["normals"]:.2f}s')
    print(f'[stitch] 3. ICP:     {t_icp_elapsed:.2f}s  fitness={result.fitness:.4f}  rmse={result.inlier_rmse:.4f}')
    print(f'[stitch] total: {time.perf_counter() - t0:.2f}s')

    T_b_local = result.transformation

    # Lift the refined local-frame result back into world frame so the
    # frontend can drop it straight into spaces.offset_transformation,
    # which is always stored relative to the reference space.
    T_b_world = T_a_world @ T_b_local

    delta = np.linalg.norm(T_b_world[:3, 3] - T_b_world_init[:3, 3])
    print(f'[stitch] moved: {delta:.3f}m')

    return {
        'transform': _from_matrix(T_b_world),
        'fitness': float(result.fitness),
        'inlier_rmse': float(result.inlier_rmse),
    }
