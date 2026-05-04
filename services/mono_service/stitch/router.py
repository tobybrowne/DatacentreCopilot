import os
import tempfile

import numpy as np
import open3d as o3d
import trimesh
from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from scipy.spatial.transform import Rotation

from common import get_supabase, require_auth

router = APIRouter(prefix='/stitch')

VOXEL_SIZE = 0.01
N_SAMPLE = 200_000
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


def _glb_bytes_to_pcd(data: bytes, voxel_size: float) -> o3d.geometry.PointCloud:
    with tempfile.NamedTemporaryFile(suffix='.glb', delete=False) as f:
        f.write(data)
        tmp = f.name
    try:
        loaded = trimesh.load(tmp, force='mesh')
        if isinstance(loaded, trimesh.Scene):
            mesh = trimesh.util.concatenate(list(loaded.geometry.values()))
        else:
            mesh = loaded
        samples, _ = trimesh.sample.sample_surface(mesh, N_SAMPLE)
        pcd = o3d.geometry.PointCloud()
        pcd.points = o3d.utility.Vector3dVector(samples)
        pcd = pcd.voxel_down_sample(voxel_size)
        if USE_POINT_TO_PLANE:
            pcd.estimate_normals(
                o3d.geometry.KDTreeSearchParamHybrid(radius=voxel_size * 2, max_nn=30)
            )
        return pcd
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

    glb_a = sb.storage.from_('spaces_bucket').download(space_a['glb_path'])
    glb_b = sb.storage.from_('spaces_bucket').download(space_b['glb_path'])

    pcd_a = _glb_bytes_to_pcd(glb_a, VOXEL_SIZE)
    pcd_b = _glb_bytes_to_pcd(glb_b, VOXEL_SIZE)

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

    # Multi-scale ICP: medium → fine. Tight distances assume a good manual
    # pre-alignment. `dist` is the max distance two points can be apart
    # while still being matched — too high lets bad matches corrupt the
    # result, too low demands an even better initial guess.
    estimation = (
        o3d.pipelines.registration.TransformationEstimationPointToPlane()
        if USE_POINT_TO_PLANE else
        o3d.pipelines.registration.TransformationEstimationPointToPoint()
    )
    for dist in [VOXEL_SIZE * 2, VOXEL_SIZE]:
        result = o3d.pipelines.registration.registration_icp(
            pcd_b, pcd_a,
            dist,
            T_b_local,
            estimation,
            o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=200),
        )
        T_b_local = result.transformation

    # Lift the refined local-frame result back into world frame so the
    # frontend can drop it straight into spaces.offset_transformation,
    # which is always stored relative to the reference space.
    T_b_world = T_a_world @ T_b_local

    return {
        'transform': _from_matrix(T_b_world),
        'fitness': float(result.fitness),
        'inlier_rmse': float(result.inlier_rmse),
    }
