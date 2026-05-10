#!/usr/bin/env python3
"""
Segment a navmesh GLB into rooms and export a single coloured GLB.

Algorithm:
  1. Build a dual graph where nodes are triangles and edges connect adjacent triangles.
  2. Each dual-graph edge is weighted by the length of the shared navmesh edge
     (i.e. the width of the passage between the two triangles).
  3. Remove dual-graph edges narrower than --threshold (doorway cut).
  4. Connected components of the pruned graph = rooms.
  5. Assign each room a distinct colour and export one merged GLB.

Usage:
  python segment_rooms.py navmesh.glb -o coloured.glb -t 1.2
"""

import argparse
import json
import os
from collections import defaultdict

import numpy as np
import trimesh
import networkx as nx


# Visually distinct RGBA colours (alpha=200 for slight transparency)
PALETTE = np.array([
    [0,   212, 255, 200],  # cyan
    [255,  80,  80, 200],  # red
    [80,  255, 120, 200],  # green
    [255, 200,   0, 200],  # yellow
    [180,  80, 255, 200],  # purple
    [255, 140,   0, 200],  # orange
    [0,   180, 255, 200],  # sky blue
    [255,  60, 180, 200],  # pink
    [60,  220, 180, 200],  # teal
    [200, 255,  60, 200],  # lime
    [255, 160, 120, 200],  # salmon
    [120, 120, 255, 200],  # lavender
], dtype=np.uint8)


def load_mesh(path: str) -> trimesh.Trimesh:
    scene = trimesh.load(path, force="scene")
    if isinstance(scene, trimesh.Scene):
        meshes = list(scene.geometry.values())
        if not meshes:
            raise ValueError("No geometry found in GLB")
        mesh = trimesh.util.concatenate(meshes)
    else:
        mesh = scene
    if not isinstance(mesh, trimesh.Trimesh):
        raise ValueError(f"Expected a triangle mesh, got {type(mesh)}")
    mesh.merge_vertices()
    return mesh


def fix_tjunctions(
    verts: np.ndarray, faces: np.ndarray
) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
    """
    Repair T-junctions: wherever a mesh vertex lies exactly on an edge of another
    face (but is not a vertex of it), split that face at the junction point.
    Returns (verts, new_faces, origin) where origin[new_fi] = old_fi before splits.
    """
    faces_list = list(map(list, faces))
    origins = list(range(len(faces_list)))

    for _ in range(20):
        edge_faces: dict[tuple, list[int]] = defaultdict(list)
        for fi, face in enumerate(faces_list):
            for i in range(3):
                e = tuple(sorted((face[i], face[(i + 1) % 3])))
                edge_faces[e].append(fi)

        # Vertices that appear on open (single-face) edges are potential T-junction points
        open_verts: set[int] = set()
        for fids in edge_faces.values():
            if len(fids) == 1:
                open_verts.update(fids)  # wrong — fids are face ids not vert ids
        # Correct: collect the vertex indices on open edges
        open_verts = set()
        for (a, b), fids in edge_faces.items():
            if len(fids) == 1:
                open_verts.add(a)
                open_verts.add(b)

        if not open_verts:
            break

        splits: dict[int, tuple[int, int]] = {}
        for fi, face in enumerate(faces_list):
            face_vset = set(face)
            for i in range(3):
                a, b = face[i], face[(i + 1) % 3]
                pa, pb = verts[a], verts[b]
                ev = pb - pa
                el2 = float(np.dot(ev, ev))
                if el2 < 1e-20:
                    continue
                for vi in open_verts:
                    if vi in face_vset:
                        continue
                    t = float(np.dot(verts[vi] - pa, ev)) / el2
                    if not (1e-6 < t < 1 - 1e-6):
                        continue
                    r = verts[vi] - (pa + t * ev)
                    if float(np.dot(r, r)) < 1e-12:
                        splits[fi] = (i, vi)
                        break
                if fi in splits:
                    break

        if not splits:
            break

        new_faces: list[list[int]] = []
        new_origins: list[int] = []
        for fi, face in enumerate(faces_list):
            if fi in splits:
                i, vi = splits[fi]
                a, b, c = face[i], face[(i + 1) % 3], face[(i + 2) % 3]
                new_faces += [[a, vi, c], [vi, b, c]]
                new_origins += [origins[fi], origins[fi]]
            else:
                new_faces.append(face)
                new_origins.append(origins[fi])

        faces_list = new_faces
        origins = new_origins

    return verts, np.array(faces_list), np.array(origins)


def subdivide_for_analysis(mesh: trimesh.Trimesh, max_area_ratio: float = 4.0):
    """
    Subdivide faces larger than max_area_ratio × median area so the dual graph
    has roughly uniform node density. T-junctions created by selective subdivision
    are repaired after each pass so the mesh stays manifold.
    Returns (subdivided_mesh, face_origin) where face_origin[new_i] = original face index.
    """
    target = np.percentile(mesh.area_faces, 99)
    verts = mesh.vertices.copy()
    faces = mesh.faces.copy()
    face_origin = np.arange(len(faces), dtype=np.intp)

    for _ in range(2):
        areas = trimesh.Trimesh(vertices=verts, faces=faces, process=False).area_faces
        large = np.where(areas > target)[0]
        if len(large) == 0:
            break
        print(f"    Splitting {len(large)} outlier faces (>{target:.3f} m²) → {len(faces) - len(large) + len(large)*4} faces")
        new_verts, new_faces, index_dict = trimesh.remesh.subdivide(
            verts, faces, face_index=large, return_index=True
        )
        large_set = set(large.tolist())
        unchanged = [i for i in range(len(faces)) if i not in large_set]
        new_origin = np.empty(len(new_faces), dtype=np.intp)
        for new_i, prev_i in enumerate(unchanged):
            new_origin[new_i] = face_origin[prev_i]
        for prev_i, new_indices in index_dict.items():
            for new_idx in new_indices:
                new_origin[new_idx] = face_origin[int(prev_i)]
        face_origin = new_origin
        verts, faces = new_verts, new_faces

        # Repair T-junctions so the dual graph stays connected
        verts, faces, tj_origin = fix_tjunctions(verts, faces)
        face_origin = face_origin[tj_origin]

    return trimesh.Trimesh(vertices=verts, faces=faces, process=False), face_origin


def build_dual_graph(mesh: trimesh.Trimesh) -> nx.Graph:
    faces = mesh.faces
    verts = mesh.vertices
    centroids = verts[faces].mean(axis=1)

    edge_to_faces: dict[tuple, list[int]] = defaultdict(list)
    for fi, face in enumerate(faces):
        for i in range(3):
            e = tuple(sorted((face[i], face[(i + 1) % 3])))
            edge_to_faces[e].append(fi)

    G = nx.Graph()
    G.add_nodes_from(range(len(faces)))

    for (v0, v1), face_ids in edge_to_faces.items():
        if len(face_ids) == 2:
            fi, fj = face_ids
            width = float(np.linalg.norm(verts[v1] - verts[v0]))
            dist = float(np.linalg.norm(centroids[fi] - centroids[fj]))
            G.add_edge(fi, fj, width=width, dist=dist)

    return G


def area_weighted_edge_betweenness(G: nx.Graph, face_areas: np.ndarray, weight: str = "dist") -> dict:
    """
    Edge betweenness where each source-target pair contributes area[s]*area[t] instead of 1.
    Makes the score invariant to mesh resolution: a 2m² triangle contributes the same
    flow demand as 200 tiny triangles covering the same area.
    Uses Brandes' algorithm with area weights in the back-propagation step.
    """
    import heapq

    betweenness: dict[tuple, float] = {(min(u, v), max(u, v)): 0.0 for u, v in G.edges()}
    nodes = list(G.nodes())

    for s in nodes:
        S: list[int] = []
        P: dict[int, list[int]] = {v: [] for v in nodes}
        sigma: dict[int, float] = {v: 0.0 for v in nodes}
        sigma[s] = 1.0
        d: dict[int, float] = {v: float("inf") for v in nodes}
        d[s] = 0.0

        pq = [(0.0, s)]
        while pq:
            dv, v = heapq.heappop(pq)
            if dv > d[v]:
                continue
            S.append(v)
            for w in G.neighbors(v):
                nd = d[v] + G[v][w].get(weight, 1.0)
                if nd < d[w] - 1e-10:
                    d[w] = nd
                    P[w] = [v]
                    sigma[w] = sigma[v]
                    heapq.heappush(pq, (nd, w))
                elif abs(nd - d[w]) < 1e-10:
                    P[w].append(v)
                    sigma[w] += sigma[v]

        # Back-propagation: delta[w] accumulates area[t] for all t in w's subtree
        delta: dict[int, float] = {v: 0.0 for v in nodes}
        while S:
            w = S.pop()
            for v in P[w]:
                coeff = sigma[v] / sigma[w]
                contrib = face_areas[s] * coeff * (face_areas[w] + delta[w])
                key = (min(v, w), max(v, w))
                betweenness[key] = betweenness.get(key, 0.0) + contrib
                delta[v] += coeff * (face_areas[w] + delta[w])

    return betweenness


def segment_betweenness(mesh: trimesh.Trimesh) -> tuple[list[set[int]], dict]:
    G = build_dual_graph(mesh)

    centrality = nx.edge_betweenness_centrality(G, weight="dist")

    scores = np.array(list(centrality.values()))
    cutoff = scores.mean() + 2.0 * scores.std()

    doorways = [(u, v) for (u, v), s in centrality.items() if s > cutoff]
    print(f"  {len(doorways)} doorway edges detected (betweenness > {cutoff:.4f})")
    G.remove_edges_from(doorways)

    return list(nx.connected_components(G)), centrality


def segment_louvain(mesh: trimesh.Trimesh, resolution: float = 0.2, G: nx.Graph | None = None) -> tuple[list[set[int]], None]:
    from networkx.algorithms.community import louvain_communities
    if G is None:
        G = build_dual_graph(mesh)
    communities = louvain_communities(G, weight="width", seed=42, resolution=resolution)
    return [set(c) for c in communities], None


def tune_louvain_resolution(mesh: trimesh.Trimesh, G: nx.Graph, target_rooms: int, min_area: float) -> float:
    """Binary search on Louvain resolution to hit a target final room count."""
    from networkx.algorithms.community import louvain_communities

    face_areas = mesh.area_faces

    def count_rooms(res: float) -> int:
        communities = louvain_communities(G, weight="width", seed=42, resolution=res)
        return sum(
            1 for c in communities
            if face_areas[list(c)].sum() >= min_area
        )

    # Find an upper bound where count_rooms is still >= target (high resolution
    # can over-fragment to tiny pieces, all filtered by min_area → 0 rooms).
    hi = 0.1
    while count_rooms(hi) < target_rooms and hi < 10.0:
        hi *= 2
    lo = 0.01

    for _ in range(15):
        mid = (lo + hi) / 2
        n = count_rooms(mid)
        if n == target_rooms:
            return mid
        elif n < target_rooms:
            lo = mid
        else:
            hi = mid

    return (lo + hi) / 2


def export_betweenness_mesh(mesh: trimesh.Trimesh, centrality: dict, output_path: str) -> None:
    node_scores = np.zeros(len(mesh.faces))
    for (u, v), score in centrality.items():
        node_scores[u] = max(node_scores[u], score)
        node_scores[v] = max(node_scores[v], score)

    vmin, vmax = node_scores.min(), node_scores.max()
    normalized = (node_scores - vmin) / (vmax - vmin) if vmax > vmin else np.zeros_like(node_scores)

    # hot colormap: black → red → yellow → white
    r = np.clip(normalized * 3.0, 0, 1)
    g = np.clip(normalized * 3.0 - 1.0, 0, 1)
    b = np.clip(normalized * 3.0 - 2.0, 0, 1)
    colors = (np.stack([r, g, b, np.full_like(r, 0.9)], axis=1) * 255).astype(np.uint8)

    vis_mesh = mesh.copy()
    vis_mesh.unmerge_vertices()
    vis_mesh.visual = trimesh.visual.ColorVisuals(mesh=vis_mesh, face_colors=colors)
    vis_mesh.export(output_path)
    print(f"Betweenness map  → {output_path}")


def merge_wide_divisions(
    components: list[set[int]],
    G_full: nx.Graph,
    max_division_width: float,
) -> list[set[int]]:
    """Merge room pairs whose shared boundary is wider than max_division_width."""
    # Use Union-Find via a label array
    labels = list(range(len(components)))
    face_to_comp = {}
    for ci, comp in enumerate(components):
        for fi in comp:
            face_to_comp[fi] = ci

    def root(x):
        while labels[x] != x:
            labels[x] = labels[labels[x]]
            x = labels[x]
        return x

    def union(a, b):
        ra, rb = root(a), root(b)
        if ra != rb:
            labels[rb] = ra

    # For every edge in the full graph that crosses a room boundary,
    # accumulate the total passage width between the two rooms
    passage: dict[tuple[int, int], float] = {}
    for u, v, d in G_full.edges(data=True):
        cu, cv = face_to_comp.get(u), face_to_comp.get(v)
        if cu is None or cv is None or cu == cv:
            continue
        key = (min(cu, cv), max(cu, cv))
        passage[key] = passage.get(key, 0.0) + d["width"]

    for (ca, cb), width in passage.items():
        if width > max_division_width:
            union(ca, cb)

    # Rebuild components grouped by root label
    merged: dict[int, set[int]] = {}
    for ci, comp in enumerate(components):
        r = root(ci)
        if r not in merged:
            merged[r] = set()
        merged[r].update(comp)

    return list(merged.values())


def face_centroid(mesh: trimesh.Trimesh, face_ids: list[int]) -> np.ndarray:
    return mesh.vertices[mesh.faces[face_ids]].mean(axis=(0, 1))


def main():
    parser = argparse.ArgumentParser(description="Colour a navmesh GLB by room")
    parser.add_argument("input", help="Input navmesh GLB")
    parser.add_argument("-o", "--output", default=None, help="Output GLB path (default: <input>_rooms.glb)")
    parser.add_argument(
        "--min-area",
        type=float, default=2.0,
        help="Segments smaller than this area in m² are merged into their nearest larger room (default: 2.0)",
    )
    parser.add_argument(
        "--method",
        choices=["louvain", "betweenness"],
        default="louvain",
        help="Segmentation algorithm: louvain (fast, default) or betweenness (slow, more precise)",
    )
    parser.add_argument(
        "--rooms",
        type=int, default=None,
        help="Target number of rooms — auto-tunes Louvain resolution to match (louvain only)",
    )
    args = parser.parse_args()

    if args.output is None:
        stem = os.path.splitext(args.input)[0]
        args.output = f"{stem}_rooms.glb"

    print(f"Loading {args.input} …")
    mesh = load_mesh(args.input)
    print(f"  {len(mesh.vertices)} vertices, {len(mesh.faces)} triangles, total area {mesh.area:.1f} m²")

    # print(f"Subdividing non-uniform faces for analysis …")
    # sub_mesh, face_origin = subdivide_for_analysis(mesh)
    # print(f"  {len(sub_mesh.faces)} triangles after subdivision")
    sub_mesh, face_origin = mesh, np.arange(len(mesh.faces))

    G_full = build_dual_graph(sub_mesh)
    if args.method == "louvain":
        if args.rooms is not None:
            print(f"Tuning Louvain resolution for {args.rooms} rooms …")
            resolution = tune_louvain_resolution(sub_mesh, G_full, args.rooms, args.min_area)
            print(f"  resolution = {resolution:.4f}")
        else:
            resolution = 0.2
        print("Segmenting (Louvain) …")
        components, centrality = segment_louvain(sub_mesh, resolution=resolution, G=G_full)
    else:
        print("Segmenting (betweenness centrality) …")
        components, centrality = segment_betweenness(sub_mesh)
    print(f"  {len(components)} raw segments")

    if centrality is not None:
        betweenness_path = os.path.splitext(args.output)[0].replace("_rooms", "") + "_betweenness.glb"
        export_betweenness_mesh(sub_mesh, centrality, betweenness_path)

    components.sort(key=len, reverse=True)

    # Split into named rooms (large) and fragments (small) — areas measured on sub_mesh
    rooms_comps = []
    fragments = []
    for comp in components:
        face_ids = list(comp)
        sub = trimesh.Trimesh(vertices=sub_mesh.vertices, faces=sub_mesh.faces[face_ids])
        if sub.area >= args.min_area:
            rooms_comps.append(face_ids)
        else:
            fragments.append(face_ids)

    if not rooms_comps:
        # All segments too small — treat the largest fragment as a room
        fragments.sort(key=lambda f: len(f), reverse=True)
        rooms_comps.append(fragments.pop(0))
        print(f"  Warning: no segments above min-area {args.min_area} m², using largest segment as single room")

    print(f"  {len(rooms_comps)} rooms, {len(fragments)} fragments → BFS flood-fill from room seeds")

    G_orig = build_dual_graph(sub_mesh)

    # Seed BFS with every sub_mesh face already assigned to a room
    face_to_room: dict[int, int] = {}
    queue: list[int] = []
    for ri, fids in enumerate(rooms_comps):
        for fi in fids:
            face_to_room[fi] = ri
            queue.append(fi)

    head = 0
    while head < len(queue):
        fi = queue[head]; head += 1
        ri = face_to_room[fi]
        for nb in G_orig.neighbors(fi):
            if nb not in face_to_room:
                face_to_room[nb] = ri
                queue.append(nb)

    room_centroids = np.array([
        face_centroid(sub_mesh, fids) for fids in rooms_comps
    ])
    for fi in range(len(sub_mesh.faces)):
        if fi not in face_to_room:
            fc = sub_mesh.vertices[sub_mesh.faces[fi]].mean(axis=0)
            face_to_room[fi] = int(np.argmin(np.linalg.norm(room_centroids - fc, axis=1)))

    # Map sub_mesh face assignments back to original mesh faces (majority vote)
    orig_face_votes: dict[int, dict[int, int]] = defaultdict(lambda: defaultdict(int))
    for sub_fi, ri in face_to_room.items():
        orig_face_votes[int(face_origin[sub_fi])][ri] += 1
    orig_face_to_room: dict[int, int] = {
        fi: max(votes, key=votes.__getitem__)
        for fi, votes in orig_face_votes.items()
    }
    # Fallback for any original face not covered (shouldn't happen)
    for fi in range(len(mesh.faces)):
        if fi not in orig_face_to_room:
            fc = mesh.vertices[mesh.faces[fi]].mean(axis=0)
            orig_face_to_room[fi] = int(np.argmin(np.linalg.norm(room_centroids - fc, axis=1)))

    # Rebuild rooms_comps in terms of original mesh face indices
    n_rooms = len(rooms_comps)
    rooms_comps = [[] for _ in range(n_rooms)]
    for fi, ri in orig_face_to_room.items():
        rooms_comps[ri].append(fi)

    # Unmerge vertices so each triangle owns its own 3 verts — prevents
    # the GPU interpolating colours across shared vertices at room boundaries.
    mesh.unmerge_vertices()

    # Assign colours and build output
    face_colors = np.zeros((len(mesh.faces), 4), dtype=np.uint8)
    summary_rooms = []

    for room_idx, face_ids in enumerate(rooms_comps):
        color = PALETTE[room_idx % len(PALETTE)]
        face_colors[face_ids] = color

        sub = trimesh.Trimesh(vertices=mesh.vertices, faces=mesh.faces[face_ids])
        centroid = sub.centroid
        bounds = sub.bounds
        summary_rooms.append({
            "id": room_idx,
            "color_rgba": color.tolist(),
            "triangle_count": len(face_ids),
            "area_m2": round(float(sub.area), 3),
            "centroid": {k: round(float(v), 3) for k, v in zip("xyz", centroid)},
            "bounds": {
                "min": {k: round(float(v), 3) for k, v in zip("xyz", bounds[0])},
                "max": {k: round(float(v), 3) for k, v in zip("xyz", bounds[1])},
            },
        })
        print(f"  Room {room_idx:02d}: {len(face_ids):4d} triangles, {sub.area:6.1f} m²  colour {color[:3].tolist()}")

    print(f"  {len(rooms_comps)} rooms total")

    # Apply face colours and export
    mesh.visual = trimesh.visual.ColorVisuals(mesh=mesh, face_colors=face_colors)
    mesh.export(args.output)
    print(f"\nColoured navmesh → {args.output}")

    summary_path = os.path.splitext(args.output)[0] + ".json"
    with open(summary_path, "w") as f:
        json.dump({
            "input": args.input,
            "fragment_merge_threshold_m2": args.min_area,
            "room_count": room_idx,
            "rooms": summary_rooms,
        }, f, indent=2)
    print(f"Summary        → {summary_path}")


if __name__ == "__main__":
    main()
