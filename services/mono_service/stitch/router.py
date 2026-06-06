import hashlib
import io
import os
import tempfile
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
import open3d as o3d
import trimesh
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from scipy.spatial.transform import Rotation

from common import get_supabase, require_auth

router = APIRouter(prefix='/stitch')

NORMAL_RADIUS = 0.02  # neighbourhood radius for normal estimation
# SAMPLES_PER_M2 = 100
SAMPLES_PER_M2 = 200
GLOBAL_VOXEL = 0.15  # coarse voxel (m) for FPFH-based global registration
USE_POINT_TO_PLANE = True  # True = point-to-plane (faster, needs good normals), False = point-to-point (slower, more robust on noisy/partial data)

# /refine_live writes a debug GLB (scan mesh + aligned headset points) to
# ALIGNMENT_GLB_DIR/align_<space_id>_<timestamp>.glb each call, so the alignment
# can be eyeballed and successive passes compared.
ALIGNMENT_GLB_DIR = os.environ.get('STITCH_ALIGNMENT_GLB_DIR', 'stitch_debug')


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


class RefineLiveRequest(BaseModel):
    space_id: str
    points: list[list[float]]                       # live headset mesh points, in the headset world frame
    initial_transform: RigidTransform | None = None # GLB -> world seed; if omitted, global registration is used
    global_align: bool = False                      # force global registration even when a seed is given
    voxel: float = 0.05                             # server-side downsample of the live cloud, metres


def to_matrix(rt: RigidTransform) -> np.ndarray:
    q = rt.quaternion
    R = Rotation.from_quat([q.x, q.y, q.z, q.w]).as_matrix()
    T = np.eye(4)
    T[:3, :3] = R
    T[:3, 3] = [rt.position.x, rt.position.y, rt.position.z]
    return T


def from_matrix(T: np.ndarray) -> dict:
    q = Rotation.from_matrix(T[:3, :3]).as_quat()
    return {
        'position': {'x': float(T[0, 3]), 'y': float(T[1, 3]), 'z': float(T[2, 3])},
        'quaternion': {'x': float(q[0]), 'y': float(q[1]), 'z': float(q[2]), 'w': float(q[3])},
    }


def run_icp(
    pcd_b: o3d.geometry.PointCloud,
    pcd_a: o3d.geometry.PointCloud,
    T_b_local_init: np.ndarray,
    max_corr: float = 0.1,
    coarse_max_corr: float | None = 0.3,
    max_iter: int = 200,
) -> o3d.pipelines.registration.RegistrationResult:
    """Coarse-to-fine ICP. Coarse pass widens the convergence basin (catches
    larger initial misalignments); fine pass tightens for precision. Pass
    coarse_max_corr=None for a single-pass refinement.
    Returned RegistrationResult carries the fine-pass fitness/RMSE.
    """
    estimation = (
        o3d.pipelines.registration.TransformationEstimationPointToPlane()
        if USE_POINT_TO_PLANE else
        o3d.pipelines.registration.TransformationEstimationPointToPoint()
    )
    criteria = o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=max_iter)
    T = T_b_local_init
    if coarse_max_corr is not None and coarse_max_corr > max_corr:
        coarse = o3d.pipelines.registration.registration_icp(
            pcd_b, pcd_a, coarse_max_corr, T, estimation, criteria,
        )
        T = coarse.transformation
    return o3d.pipelines.registration.registration_icp(
        pcd_b, pcd_a, max_corr, T, estimation, criteria,
    )


def run_global_registration(
    source: o3d.geometry.PointCloud,
    target: o3d.geometry.PointCloud,
    voxel: float = GLOBAL_VOXEL,
) -> o3d.pipelines.registration.RegistrationResult:
    """Anchor-free coarse alignment via FPFH feature matching + RANSAC.

    Returns a source->target transform good enough to seed ICP, so a hand-placed
    initial pose (anchors) is not required. Both clouds are downsampled to a
    coarse voxel, normals + FPFH features are computed, and RANSAC finds the
    rigid transform whose feature correspondences are most consistent.
    """
    def prep(pcd: o3d.geometry.PointCloud):
        down = pcd.voxel_down_sample(voxel)
        down.estimate_normals(
            o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 2.0, max_nn=30)
        )
        fpfh = o3d.pipelines.registration.compute_fpfh_feature(
            down, o3d.geometry.KDTreeSearchParamHybrid(radius=voxel * 5.0, max_nn=100)
        )
        return down, fpfh

    src_down, src_fpfh = prep(source)
    tgt_down, tgt_fpfh = prep(target)
    dist = voxel * 1.5
    return o3d.pipelines.registration.registration_ransac_based_on_feature_matching(
        src_down, tgt_down, src_fpfh, tgt_fpfh, True, dist,
        o3d.pipelines.registration.TransformationEstimationPointToPoint(False), 3,
        [
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnEdgeLength(0.9),
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnDistance(dist),
        ],
        o3d.pipelines.registration.RANSACConvergenceCriteria(100000, 0.999),
    )


def glb_bytes_to_pcd(data: bytes, label: str) -> tuple[o3d.geometry.PointCloud, dict]:
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
        # Seed from GLB bytes so each mesh samples deterministically but
        # different meshes get independent samples. Keeps pairwise ICP runs
        # reproducible across invocations.
        seed = int(hashlib.md5(data).hexdigest()[:8], 16)
        np.random.seed(seed)
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


DOT_SIZE = 0.03  # edge length (m) of each headset-point marker cube in the debug GLB


def _points_to_dot_mesh(points: np.ndarray, size: float) -> trimesh.Trimesh:
    """Turn points into a single mesh of small cube markers, so they render as
    discrete dots in every glTF viewer (a glTF POINTS primitive is often shown
    as tiny/invisible specks or odd spiky geometry depending on the viewer)."""
    base = trimesh.creation.box(extents=(size, size, size))
    bv = np.asarray(base.vertices)             # (8, 3)
    bf = np.asarray(base.faces)                # (12, 3)
    n = len(points)
    verts = (bv[None, :, :] + points[:, None, :]).reshape(-1, 3)
    faces = (bf[None, :, :] + (np.arange(n)[:, None, None] * len(bv))).reshape(-1, 3)
    dots = trimesh.Trimesh(vertices=verts, faces=faces, process=False)
    dots.visual.vertex_colors = np.tile(np.array([220, 40, 40, 255], dtype=np.uint8), (len(verts), 1))
    return dots


def build_alignment_glb(glb_data: bytes, points_glb: np.ndarray) -> bytes:
    """Debug GLB: the space scan mesh plus the headset points as red cube dots,
    both in GLB space, so the post-alignment overlay can be inspected in any
    glTF viewer."""
    mesh = trimesh.load(io.BytesIO(glb_data), file_type='glb', force='mesh')
    dots = _points_to_dot_mesh(points_glb, DOT_SIZE)
    return trimesh.Scene([mesh, dots]).export(file_type='glb')


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
        fut_a = ex.submit(glb_bytes_to_pcd, glb_a, 'pcd_a')
        fut_b = ex.submit(glb_bytes_to_pcd, glb_b, 'pcd_b')
        pcd_a, times_a = fut_a.result()
        pcd_b, times_b = fut_b.result()

    # T_a_world is where space_a sits in the building's world frame. The
    # reference space (building_index=0) defines the world frame itself and
    # has no offset_transformation, so we use identity for it.
    a_offset = space_a.get('offset_transformation')
    T_a_world = (
        to_matrix(RigidTransform.model_validate(a_offset))
        if a_offset
        else np.eye(4)
    )

    # The frontend sends initial_transform in world frame (it's space_b's
    # gizmo pose against the rendered building). ICP works on raw point
    # clouds in their own local frames, so we have to express the initial
    # guess in space_a's local frame:
    #   T_b_local = T_a_world^-1 @ T_b_world
    T_b_world_init = to_matrix(req.initial_transform)
    T_b_local = np.linalg.inv(T_a_world) @ T_b_world_init

    t_icp = time.perf_counter()
    result = run_icp(pcd_b, pcd_a, T_b_local)
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
        'transform': from_matrix(T_b_world),
        'fitness': float(result.fitness),
        'inlier_rmse': float(result.inlier_rmse),
    }


@router.post('/refine_live')
async def refine_live(req: RefineLiveRequest, _: None = Depends(require_auth)) -> dict:
    """Refine a headset's GLB->world calibration against the live spatial mesh.

    The headset seeds this with its Kabsch anchor calibration and uploads its
    (downsampled) world-mesh point cloud. We register the partial live cloud
    onto the complete GLB model and return the refined GLB->world transform.

    Live cloud is the ICP source and the GLB is the target, so correspondences
    are found against the complete model and we reuse the GLB's precomputed
    normals (point-to-plane needs normals on the target only).
    """
    sb = get_supabase()
    rows = (
        sb.table('spaces').select('id,glb_path').eq('id', req.space_id).execute().data
    )
    space = rows[0] if rows else None
    if not space:
        raise HTTPException(404, 'Space not found')
    if not space['glb_path']:
        raise HTTPException(400, 'Space has no GLB export')
    if len(req.points) < 100:
        raise HTTPException(400, 'Too few live points to register')

    t0 = time.perf_counter()
    glb = sb.storage.from_('spaces_bucket').download(space['glb_path'])
    pcd_glb, _times = glb_bytes_to_pcd(glb, 'pcd_glb')  # target (complete model)

    pcd_live = o3d.geometry.PointCloud()
    pcd_live.points = o3d.utility.Vector3dVector(np.asarray(req.points, dtype=np.float64))
    if req.voxel and req.voxel > 0:
        pcd_live = pcd_live.voxel_down_sample(req.voxel)

    # Coarse alignment (world->GLB) that seeds ICP. ICP registers live(world)
    # onto GLB, so the seed is expressed world->GLB and the result inverted back
    # to GLB->world. Use the anchor seed when supplied, otherwise fall back to
    # feature-based global registration so anchors aren't needed to initialise.
    if req.global_align or req.initial_transform is None:
        t_glob = time.perf_counter()
        gr = run_global_registration(pcd_live, pcd_glb)
        init_world_to_glb = gr.transformation
        print(
            f'[stitch] refine_live: global reg {time.perf_counter() - t_glob:.2f}s '
            f'fitness={gr.fitness:.4f} rmse={gr.inlier_rmse:.4f}'
        )
    else:
        init_world_to_glb = np.linalg.inv(to_matrix(req.initial_transform))

    coarse_glb_to_world = np.linalg.inv(init_world_to_glb)

    t_icp = time.perf_counter()
    result = run_icp(pcd_live, pcd_glb, init_world_to_glb)
    T_glb_to_world = np.linalg.inv(result.transformation)

    delta = np.linalg.norm(T_glb_to_world[:3, 3] - coarse_glb_to_world[:3, 3])
    print(
        f'[stitch] refine_live: live_pts={len(pcd_live.points)} '
        f'icp={time.perf_counter() - t_icp:.2f}s total={time.perf_counter() - t0:.2f}s '
        f'fitness={result.fitness:.4f} rmse={result.inlier_rmse:.4f} moved={delta:.3f}m'
    )

    debug_glb_path = None
    try:
        # result.transformation maps the live cloud (world) into GLB space,
        # so it places the headset points onto the scan post-alignment.
        pts = np.asarray(pcd_live.points)
        pts_glb = (result.transformation @ np.c_[pts, np.ones(len(pts))].T).T[:, :3]
        glb_out = build_alignment_glb(glb, pts_glb)
        os.makedirs(ALIGNMENT_GLB_DIR, exist_ok=True)
        stamp = time.strftime('%Y%m%d-%H%M%S')
        debug_glb_path = os.path.join(ALIGNMENT_GLB_DIR, f'align_{req.space_id}_{stamp}.glb')
        with open(debug_glb_path, 'wb') as f:
            f.write(glb_out)
        print(f'[stitch] refine_live: debug GLB -> {os.path.abspath(debug_glb_path)}')
    except Exception as e:
        print(f'[stitch] refine_live: debug GLB save failed: {e}')
        debug_glb_path = None

    return {
        'transform': from_matrix(T_glb_to_world),
        'fitness': float(result.fitness),
        'inlier_rmse': float(result.inlier_rmse),
        'debug_glb_path': debug_glb_path,
    }


class LowpolyRequest(BaseModel):
    space_id: str
    target_faces: int = 20000   # decimation target; meshes already below this are returned unchanged


def decimate_glb(data: bytes, target_faces: int) -> bytes:
    """Quadric-decimate a GLB scan to roughly target_faces triangles and re-export
    as GLB. Geometry only — vertex colours/textures are dropped, which is fine for
    the dollhouse map since it overrides the material anyway."""
    mesh = trimesh.load(io.BytesIO(data), file_type='glb', force='mesh')
    if isinstance(mesh, trimesh.Scene):
        mesh = trimesh.util.concatenate(list(mesh.geometry.values()))

    n_faces = len(mesh.faces)
    if n_faces <= target_faces:
        print(f'[stitch] decimate: {n_faces} faces already <= target {target_faces}, returning as-is')
        return data

    o3d_mesh = o3d.geometry.TriangleMesh(
        o3d.utility.Vector3dVector(np.asarray(mesh.vertices)),
        o3d.utility.Vector3iVector(np.asarray(mesh.faces)),
    )
    o3d_mesh = o3d_mesh.simplify_quadric_decimation(int(target_faces))
    out = trimesh.Trimesh(
        vertices=np.asarray(o3d_mesh.vertices),
        faces=np.asarray(o3d_mesh.triangles),
        process=False,
    )
    print(f'[stitch] decimate: {n_faces} -> {len(out.faces)} faces (target {target_faces})')
    return out.export(file_type='glb')


@router.post('/lowpoly')
async def lowpoly(req: LowpolyRequest, _: None = Depends(require_auth)) -> Response:
    """Return a decimated GLB for a space, for lightweight map/overview rendering.
    The client caches the result on-device keyed by the space's updated_at."""
    sb = get_supabase()
    rows = sb.table('spaces').select('id,glb_path').eq('id', req.space_id).execute().data
    space = rows[0] if rows else None
    if not space:
        raise HTTPException(404, 'Space not found')
    if not space['glb_path']:
        raise HTTPException(400, 'Space has no GLB export')

    t0 = time.perf_counter()
    data = sb.storage.from_('spaces_bucket').download(space['glb_path'])
    out = decimate_glb(data, req.target_faces)
    print(f'[stitch] lowpoly {req.space_id}: {len(data)} -> {len(out)} bytes in {time.perf_counter() - t0:.2f}s')
    return Response(content=out, media_type='model/gltf-binary')
