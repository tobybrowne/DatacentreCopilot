#!/usr/bin/env python3
"""
Stitch multiple overlapping .glb files into one mesh using sequential registration.

Pass meshes in neighbour order.

Pipeline:
  Pass 1 — for each scan, RANSAC-align it against only its immediate predecessor.
            Chain the relative transforms to get each scan's global pose.
            Avoids overlap dilution: a small new scan only needs to match its neighbour,
            not an ever-growing accumulated map.
  Pass 2 — apply all global transforms, concatenate, and weld seam once.

Usage:
    pip install trimesh open3d scipy
    python merge_glb.py a.glb b.glb c.glb <output.glb>
    python merge_glb.py <input_dir> <output.glb>
"""

import argparse
import glob
import os
import numpy as np
import trimesh
import open3d as o3d

VOXEL_SIZE = 0.005
DEBUG_DIR = "./debug"

def clear_dir(path: str) -> None:
    if os.path.exists(path):
        for file in os.listdir(path):
            os.remove(os.path.join(path, file))
    else:
        os.makedirs(path)


def load_mesh(path: str) -> trimesh.Trimesh:
    scene_or_mesh = trimesh.load(path, force="mesh")
    if isinstance(scene_or_mesh, trimesh.Scene):
        mesh = trimesh.util.concatenate(list(scene_or_mesh.geometry.values()))
    else:
        mesh = scene_or_mesh
    if mesh.is_empty:
        raise ValueError(f"Failed to load or empty mesh: {path}")
    return mesh


def to_pcd(mesh: trimesh.Trimesh, n_points: int, normal_radius: float) -> o3d.geometry.PointCloud:
    samples, _ = trimesh.sample.sample_surface(mesh, n_points)
    pcd = o3d.geometry.PointCloud()
    pcd.points = o3d.utility.Vector3dVector(samples)
    pcd.estimate_normals(
        search_param=o3d.geometry.KDTreeSearchParamHybrid(radius=normal_radius, max_nn=30)
    )
    return pcd

# VOXEL - a 3d pixel, we divide are scan into these
# VOXEL-SIZE - the dimensions of these voxels (in metres, since our scan is in metres)
# MAX-CORRESPONDENCE-DISTANCE - the maximum distance between points in the two point clouds for them to be considered a match during registration (in metres)

# In our scenario theres a very small overlap 20%, between the scans 80% is junk, which throws off a lot of algorithms
# RANSAC may work well.

def coarse_align(
    source: trimesh.Trimesh,
    target: trimesh.Trimesh,
    voxel_size: float,
    debug_dir: str | None = None,
    stem: str = "mesh",
) -> np.ndarray:
    """Coarse alignment via FPFH descriptors + RANSAC. Handles translation and yaw."""
    normal_radius = voxel_size * 2
    feature_radius = voxel_size * 5

    def to_fpfh(mesh, label):
        samples, _ = trimesh.sample.sample_surface(mesh, 500_000)
        pcd = o3d.geometry.PointCloud()
        pcd.points = o3d.utility.Vector3dVector(samples)
        pcd = pcd.voxel_down_sample(voxel_size * 0.5)
        pcd.estimate_normals(o3d.geometry.KDTreeSearchParamHybrid(radius=normal_radius, max_nn=30))
        print(f"  {label}: {len(pcd.points)} points after downsample")

        debug_dir = DEBUG_DIR
        if debug_dir:
            # Paint normals as colours: normal (nx,ny,nz) in [-1,1] → RGB in [0,1]
            normals = np.asarray(pcd.normals)
            pcd.colors = o3d.utility.Vector3dVector(normals * 0.5 + 0.5)
            path = os.path.join(debug_dir, f"{stem}_{label}_normals.ply")
            o3d.io.write_point_cloud(path, pcd)
            print(f"  Normals → {path}")

        fpfh = o3d.pipelines.registration.compute_fpfh_feature(
            pcd, o3d.geometry.KDTreeSearchParamHybrid(radius=feature_radius, max_nn=100)
        )
        return pcd, fpfh

    pcd_src, fpfh_src = to_fpfh(source, "src")
    pcd_tgt, fpfh_tgt = to_fpfh(target, "tgt")

    print("Scale: ")
    print(pcd_src.get_max_bound() - pcd_src.get_min_bound())

    # result = o3d.pipelines.registration.registration_fgr_based_on_feature_matching(
    #     pcd_src, pcd_tgt, fpfh_src, fpfh_tgt,
    #     o3d.pipelines.registration.FastGlobalRegistrationOption(
    #         maximum_correspondence_distance=voxel_size * 1,
    #         iteration_number=1000,
    #         maximum_tuple_count=2000,
    #     ),
    # )
    # print(f"  FGR fitness={result.fitness:.4f}, rmse={result.inlier_rmse:.4f}")

    result = o3d.pipelines.registration.registration_ransac_based_on_feature_matching(
        pcd_src, pcd_tgt, fpfh_src, fpfh_tgt,
        mutual_filter=True,
        max_correspondence_distance=voxel_size * 1.5,
        estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPoint(False),
        ransac_n=3,
        checkers=[
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnEdgeLength(0.9),
            o3d.pipelines.registration.CorrespondenceCheckerBasedOnDistance(voxel_size * 1.5)
        ],
        criteria=o3d.pipelines.registration.RANSACConvergenceCriteria(10_000_000, 0.9999),
    )
    print(f"  RANSAC fitness={result.fitness:.4f}, rmse={result.inlier_rmse:.4f}")
    return result.transformation


def align(
    source: trimesh.Trimesh,
    target: trimesh.Trimesh,
    voxel_size: float,
    icp_voxel_size: float,
    debug_dir: str | None = None,
    stem: str = "mesh",
) -> tuple[np.ndarray, np.ndarray]:
    normal_radius = icp_voxel_size * 2

    coarse_transform = coarse_align(source, target, voxel_size, debug_dir, stem)

    # Multi-scale ICP from the RANSAC seed (commented out while tuning RANSAC)
    # transform = coarse_transform
    # for scale, distance in enumerate([icp_voxel_size * 3, icp_voxel_size, icp_voxel_size * 0.2]):
    #     result = o3d.pipelines.registration.registration_icp(
    #         pcd_src, pcd_tgt,
    #         distance,
    #         transform,
    #         estimation_method=o3d.pipelines.registration.TransformationEstimationPointToPlane(),
    #         criteria=o3d.pipelines.registration.ICPConvergenceCriteria(max_iteration=200),
    #     )
    #     print(f"  ICP scale {scale + 1} (dist={distance:.3f}): fitness={result.fitness:.4f}, rmse={result.inlier_rmse:.4f}")
    #     transform = result.transformation

    return coarse_transform, coarse_transform


def weld(mesh: trimesh.Trimesh, tolerance: float) -> trimesh.Trimesh:
    digits = max(0, int(-np.log10(tolerance)))
    mesh.vertices = np.round(mesh.vertices, digits)
    mesh.merge_vertices()
    unique_faces, _ = trimesh.grouping.unique_rows(np.sort(mesh.faces, axis=1))
    mesh.faces = mesh.faces[unique_faces]
    return mesh

# main function to merge all meshes in sequence
def merge_all(
    paths: list[str],
    output: str,
    tolerance: float,
    voxel_size: float,
    icp_voxel_size: float,
    debug_dir: str | None,
) -> None:
    if debug_dir:
        os.makedirs(debug_dir, exist_ok=True)

    print(f"Loading {os.path.basename(paths[0])} as base mesh...")
    first_mesh = load_mesh(paths[0])
    print(f"  {len(first_mesh.vertices)} vertices, {len(first_mesh.faces)} faces")

    meshes = [first_mesh]           # raw meshes (unmodified, for neighbour matching)
    transformed = [first_mesh]      # meshes in global frame (for incremental export)
    global_transforms = [np.eye(4)]

    stem0 = os.path.splitext(os.path.basename(paths[0]))[0]
    incremental_path = os.path.join(DEBUG_DIR, f"01_{stem0}_incremental.glb")
    first_mesh.export(incremental_path)
    print(f"  Incremental → {incremental_path}")

    # Match each scan against only its immediate predecessor, chain transforms,
    # and save an incremental GLB as soon as each scan is placed.
    for i, path in enumerate(paths[1:], start=2):
        name = os.path.basename(path)
        stem = os.path.splitext(name)[0]
        print(f"\n[{i}/{len(paths)}] Aligning {name} → previous scan only...")
        source = load_mesh(path)
        meshes.append(source)
        print(f"  {len(source.vertices)} vertices, {len(source.faces)} faces")

        relative_transform = coarse_align(source, meshes[-2], voxel_size, debug_dir, stem)
        global_transform = global_transforms[-1] @ relative_transform
        global_transforms.append(global_transform)

        placed = source.copy()
        placed.apply_transform(global_transform)
        transformed.append(placed)

        incremental = trimesh.util.concatenate(transformed)
        incremental_path = os.path.join(DEBUG_DIR, f"{i:02d}_{stem}_incremental.glb")
        incremental.export(incremental_path)
        print(f"  Incremental → {incremental_path}")

    print(f"\nFinalising...")
    accumulated = trimesh.util.concatenate(transformed)
    accumulated = weld(accumulated, tolerance)
    print(f"  Final mesh: {len(accumulated.vertices)} vertices, {len(accumulated.faces)} faces")

    print(f"\nWriting {output}...")
    accumulated.export(output)
    print("Done.")


def main():
    parser = argparse.ArgumentParser(
        description="Sequentially align and stitch .glb meshes — pass in neighbour order"
    )
    parser.add_argument(
        "inputs",
        nargs="+",
        help="A directory of .glb files, or two+ .glb paths with the output path last",
    )
    parser.add_argument(
        "--voxel-size", type=float, default=VOXEL_SIZE,
        help="Voxel size for FFT coarse alignment (default: 0.1m). Controls translation search resolution.",
    )
    parser.add_argument(
        "--icp-voxel-size", type=float, default=0.05,
        help="Voxel size for ICP fine alignment (default: 0.05m).",
    )
    parser.add_argument(
        "--tolerance", type=float, default=0.01,
        help="Vertex weld tolerance after alignment (default: 0.01)",
    )
    parser.add_argument(
        "--debug-dir",
        help="Save a coarse-alignment preview GLB per mesh to this directory for validation",
    )
    args = parser.parse_args()

    if len(args.inputs) == 2 and os.path.isdir(args.inputs[0]):
        input_dir, output = args.inputs
        paths = sorted(glob.glob(os.path.join(input_dir, "*.glb")))
        if not paths:
            parser.error(f"No .glb files found in {input_dir}")
        print(f"Found {len(paths)} .glb files (alphabetical order)")
    else:
        *paths, output = args.inputs
        if len(paths) < 2:
            parser.error("Provide at least two input .glb files and an output path")

    clear_dir(DEBUG_DIR)

    print(f"Merging {len(paths)} meshes → {output}\n")
    merge_all(paths, output, args.tolerance, args.voxel_size, args.icp_voxel_size, args.debug_dir)


if __name__ == "__main__":
    main()
