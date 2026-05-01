import {
  init as initRecast,
  NavMeshQuery,
  importNavMesh,
  type NavMesh,
} from "recast-navigation";
import { threeToSoloNavMesh, NavMeshHelper } from "@recast-navigation/three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import * as THREE from "three";
import type { Position, RigidTransform } from "./types";

export interface NavMeshParams {
  boundsYMax: number;
  cs: number;
  ch: number;
  walkableSlopeAngle: number;
  walkableHeight: number;
  walkableClimb: number;
  walkableRadius: number;
  maxEdgeLen: number;
  maxSimplificationError: number;
  minRegionArea: number;
  mergeRegionArea: number;
  maxVertsPerPoly: number;
  detailSampleDist: number;
  detailSampleMaxError: number;
}

export interface NavMeshResult {
  navMesh: NavMesh;
  navQuery: NavMeshQuery;
  debugMesh: THREE.Mesh;
}

export interface PathResult {
  geometry: THREE.TubeGeometry;
  length: number;
}

async function loadMeshes(
  spaces: Array<{ url: string; transform: RigidTransform | null }>,
): Promise<THREE.Mesh[]> {
  const loader = new GLTFLoader();
  const meshes: THREE.Mesh[] = [];

  for (const [si, space] of spaces.entries()) {
    const gltf = await loader.loadAsync(space.url);
    console.log(
      `[NavMesh] space[${si}] gltf.scene pos:`,
      gltf.scene.position,
      "quat:",
      gltf.scene.quaternion,
      "transform:",
      space.transform,
    );

    const group = new THREE.Group();
    if (space.transform) {
      const { position: p, quaternion: q } = space.transform;
      group.position.set(p.x, p.y, p.z);
      group.quaternion.set(q.x, q.y, q.z, q.w);
    }
    group.add(gltf.scene);
    group.updateWorldMatrix(true, true);

    const spaceBox = new THREE.Box3();
    const beforeCount = meshes.length;
    group.traverse((obj) => {
      if ((obj as THREE.Mesh).isMesh) {
        const src = obj as THREE.Mesh;
        const baked = src.geometry.clone().applyMatrix4(src.matrixWorld);
        spaceBox.expandByObject(new THREE.Mesh(baked));
        meshes.push(new THREE.Mesh(baked, src.material));
      }
    });
    console.log(
      `[NavMesh] space[${si}] bounds:`,
      spaceBox.min,
      spaceBox.max,
      `(${meshes.length - beforeCount} meshes)`,
    );
  }

  return meshes;
}

function makeResult(navMesh: NavMesh): NavMeshResult {
  const navQuery = new NavMeshQuery(navMesh);
  navQuery.defaultQueryHalfExtents = { x: 2, y: 4, z: 2 };
  const helper = new NavMeshHelper(navMesh, {
    navMeshMaterial: new THREE.MeshStandardMaterial({
      color: "#00d4ff",
      opacity: 0.4,
      transparent: true,
      side: THREE.DoubleSide,
    }),
  });
  return { navMesh, navQuery, debugMesh: helper.mesh };
}

export async function buildNavMeshFromSpaces(
  spaces: Array<{ url: string; transform: RigidTransform | null }>,
  params: NavMeshParams,
): Promise<NavMeshResult> {
  await initRecast();
  const meshes = await loadMeshes(spaces);

  const inputBox = new THREE.Box3();
  let totalVerts = 0;
  meshes.forEach((m) => {
    inputBox.expandByObject(m);
    totalVerts += m.geometry.attributes.position.count;
  });
  console.log(
    "[NavMesh] input meshes:",
    meshes.length,
    "verts:",
    totalVerts,
    "bounds:",
    inputBox.min,
    inputBox.max,
  );

  const { boundsYMax, ...recastParams } = params;
  const yMax = inputBox.min.y + boundsYMax;
  const clipped = meshes.map((m) => {
    const pos = m.geometry.attributes.position;
    const idx = m.geometry.index;
    const outPos: number[] = [];
    const outIdx: number[] = [];
    const remap = new Int32Array(pos.count).fill(-1);
    const triCount = idx ? idx.count / 3 : pos.count / 3;
    for (let t = 0; t < triCount; t++) {
      const ia = idx ? idx.getX(t * 3) : t * 3;
      const ib = idx ? idx.getX(t * 3 + 1) : t * 3 + 1;
      const ic = idx ? idx.getX(t * 3 + 2) : t * 3 + 2;
      if (pos.getY(ia) > yMax && pos.getY(ib) > yMax && pos.getY(ic) > yMax)
        continue;
      for (const vi of [ia, ib, ic]) {
        if (remap[vi] === -1) {
          remap[vi] = outPos.length / 3;
          outPos.push(pos.getX(vi), pos.getY(vi), pos.getZ(vi));
        }
        outIdx.push(remap[vi]);
      }
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute("position", new THREE.Float32BufferAttribute(outPos, 3));
    g.setIndex(outIdx);
    return new THREE.Mesh(g, m.material);
  });

  const result = threeToSoloNavMesh(clipped, { ...recastParams });
  if (!result.success || !result.navMesh) {
    throw new Error(
      "Failed to generate navigation mesh. The scan geometry may be too noisy.",
    );
  }

  const navResult = makeResult(result.navMesh);

  const cx = (inputBox.min.x + inputBox.max.x) / 2;
  const cz = (inputBox.min.z + inputBox.max.z) / 2;
  const floorProbe = navResult.navQuery.findClosestPoint({
    x: cx,
    y: inputBox.min.y + 0.5,
    z: cz,
  });
  console.log("[NavMesh] floor probe result:", floorProbe);

  const navBox = new THREE.Box3().setFromObject(navResult.debugMesh);
  const navPos = navResult.debugMesh.geometry.attributes.position;
  console.log(
    "[NavMesh] nav poly verts:",
    navPos.count,
    "bounds (world):",
    navBox.min,
    navBox.max,
  );

  return navResult;
}

export async function loadNavMeshFromBuffer(
  data: Uint8Array,
): Promise<NavMeshResult> {
  await initRecast();
  const result = importNavMesh(data);
  if (!result.navMesh) throw new Error("Failed to import navmesh");
  return makeResult(result.navMesh);
}

export function computePath(
  navQuery: NavMeshQuery,
  startPos: Position,
  endPos: Position,
): PathResult {
  const { point: snappedStart, success: startOk } =
    navQuery.findClosestPoint(startPos);
  const { point: snappedEnd, success: endOk } =
    navQuery.findClosestPoint(endPos);

  if (!startOk || !endOk) {
    throw new Error(
      "One or both points are too far from any walkable surface. Try clicking closer to the floor.",
    );
  }

  const { path } = navQuery.computePath(snappedStart, snappedEnd);

  if (path.length < 2) {
    throw new Error(
      "No path found — the two points may be in disconnected areas.",
    );
  }

  const elevated = path.map((p) => new THREE.Vector3(p.x, p.y + 0.05, p.z));
  const curve = new THREE.CatmullRomCurve3(elevated);
  const geometry = new THREE.TubeGeometry(
    curve,
    elevated.length * 4,
    0.04,
    8,
    false,
  );

  const length = path.reduce((acc, pt, i) => {
    if (i === 0) return 0;
    const prev = path[i - 1];
    return acc + Math.hypot(pt.x - prev.x, pt.z - prev.z);
  }, 0);

  return { geometry, length };
}
