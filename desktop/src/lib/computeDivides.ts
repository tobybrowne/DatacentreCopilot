import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";
import type { RigidTransform } from "./types";

export interface DivideSegment {
  x1: number;
  z1: number;
  x2: number;
  z2: number;
  floorY: number;
}

export interface DivideCell {
  x: number;
  z: number;
  floorY: number;
  ownerIdx: number;
}

export interface DivideResult {
  segments: DivideSegment[];
  cells: DivideCell[];
  spaceCount: number;
}

// Distinct hues for up to 8 spaces
export const SPACE_COLORS = [
  new THREE.Color(0xff4444),
  new THREE.Color(0x4488ff),
  new THREE.Color(0x44dd88),
  new THREE.Color(0xffaa22),
  new THREE.Color(0xcc44ff),
  new THREE.Color(0xff44aa),
  new THREE.Color(0x44ffee),
  new THREE.Color(0xdddd44),
];

function rigidToMatrix(t: RigidTransform | null): THREE.Matrix4 {
  if (!t) return new THREE.Matrix4();
  const m = new THREE.Matrix4();
  m.compose(
    new THREE.Vector3(t.position.x, t.position.y, t.position.z),
    new THREE.Quaternion(
      t.quaternion.x,
      t.quaternion.y,
      t.quaternion.z,
      t.quaternion.w
    ),
    new THREE.Vector3(1, 1, 1)
  );
  return m;
}

// Wall detection from the density map.
//
// A vertical surface stacks many vertices into a single XZ voxel column, so wall
// cells stand out as density spikes vs. floor/ceiling. We:
//   1. Score each cell by aggregated density × edge bonus (scan boundaries are
//      usually exterior walls).
//   2. Hysteresis-threshold: cells above HIGH_FACTOR×median seed walls; cells
//      above LOW_FACTOR×median join only if connected to a seed (suppresses
//      isolated dense clutter — furniture, posts).
//   3. Bridge 1-cell gaps so the wall mask forms a continuous outline.
const EDGE_BONUS = 1.6;
const HIGH_FACTOR = 4.0;
const LOW_FACTOR = HIGH_FACTOR;
// |normal.y| below this counts as a vertical surface — i.e. a wall face.
// 0.3 ≈ within 17° of perfectly vertical, tolerant of mesh reconstruction noise.
const WALL_NORMAL_MAX_Y = 0.3;

const NEIGHBOURS_4: Array<[number, number]> = [
  [1, 0],
  [-1, 0],
  [0, 1],
  [0, -1],
];

function neighbourKeys(key: string): string[] {
  const [cx, cz] = key.split(",").map(Number);
  return NEIGHBOURS_4.map(([dx, dz]) => `${cx + dx},${cz + dz}`);
}

// For each triangle in the scene, if its world-space normal is near-horizontal
// (= vertical surface = wall face), accumulate its area into the XZ voxel
// containing its centroid. Floors, ceilings, tabletops, and roof-hole rims have
// vertical normals and contribute nothing — making this signal much more
// wall-specific than raw vertex density.
function accumulateWallFaceArea(
  scene: THREE.Group,
  matrix: THREE.Matrix4,
  voxelSize: number,
  out: Map<string, number>
): { minY: number } {
  let minY = Infinity;
  const a = new THREE.Vector3();
  const b = new THREE.Vector3();
  const c = new THREE.Vector3();
  const ab = new THREE.Vector3();
  const ac = new THREE.Vector3();
  const n = new THREE.Vector3();

  scene.traverse((obj: THREE.Object3D) => {
    if (!(obj as THREE.Mesh).isMesh) return;
    const mesh = obj as THREE.Mesh;
    const geom = mesh.geometry;
    const pos = geom.attributes.position;
    if (!pos) return;
    const idx = geom.index;
    const triCount = idx ? idx.count / 3 : pos.count / 3;
    const wm = mesh.matrixWorld;

    for (let t = 0; t < triCount; t++) {
      const i0 = idx ? idx.getX(t * 3) : t * 3;
      const i1 = idx ? idx.getX(t * 3 + 1) : t * 3 + 1;
      const i2 = idx ? idx.getX(t * 3 + 2) : t * 3 + 2;

      a.set(pos.getX(i0), pos.getY(i0), pos.getZ(i0)).applyMatrix4(wm).applyMatrix4(matrix);
      b.set(pos.getX(i1), pos.getY(i1), pos.getZ(i1)).applyMatrix4(wm).applyMatrix4(matrix);
      c.set(pos.getX(i2), pos.getY(i2), pos.getZ(i2)).applyMatrix4(wm).applyMatrix4(matrix);

      if (a.y < minY) minY = a.y;
      if (b.y < minY) minY = b.y;
      if (c.y < minY) minY = c.y;

      ab.subVectors(b, a);
      ac.subVectors(c, a);
      n.crossVectors(ab, ac);
      const len = n.length();
      if (len === 0) continue;
      if (Math.abs(n.y / len) >= WALL_NORMAL_MAX_Y) continue;

      const cx = (a.x + b.x + c.x) / 3;
      const cz = (a.z + b.z + c.z) / 3;
      const key = `${Math.floor(cx / voxelSize)},${Math.floor(cz / voxelSize)}`;
      out.set(key, (out.get(key) ?? 0) + len * 0.5);
    }
  });

  return { minY };
}

// Zhang-Suen thinning: collapses a thick binary mask to a 1-cell skeleton
// while preserving connectivity and endpoints. Used here because walls scanned
// from both sides leave two parallel high-density lines — thinning merges them.
function thinSkeleton(walls: Set<string>): Set<string> {
  const result = new Set(walls);

  // Neighbours in clockwise order starting from N: [N, NE, E, SE, S, SW, W, NW].
  function neigh(cx: number, cz: number): boolean[] {
    return [
      result.has(`${cx},${cz - 1}`),
      result.has(`${cx + 1},${cz - 1}`),
      result.has(`${cx + 1},${cz}`),
      result.has(`${cx + 1},${cz + 1}`),
      result.has(`${cx},${cz + 1}`),
      result.has(`${cx - 1},${cz + 1}`),
      result.has(`${cx - 1},${cz}`),
      result.has(`${cx - 1},${cz - 1}`),
    ];
  }

  // Count of 0→1 transitions in the circular sequence of neighbours.
  // For a 1-cell-thick line, this equals 1 except at branch points.
  function transitions(p: boolean[]): number {
    let count = 0;
    for (let i = 0; i < 8; i++) if (!p[i] && p[(i + 1) % 8]) count++;
    return count;
  }

  let changed = true;
  while (changed) {
    changed = false;

    for (let pass = 0; pass < 2; pass++) {
      const toRemove: string[] = [];
      for (const k of result) {
        const [cx, cz] = k.split(",").map(Number);
        const p = neigh(cx, cz);
        let b = 0;
        for (const v of p) if (v) b++;
        if (b < 2 || b > 6) continue;
        if (transitions(p) !== 1) continue;
        // pass 0: NE/SW corner; pass 1: NW/SE corner.
        if (pass === 0) {
          if (p[0] && p[2] && p[4]) continue;
          if (p[2] && p[4] && p[6]) continue;
        } else {
          if (p[0] && p[2] && p[6]) continue;
          if (p[0] && p[4] && p[6]) continue;
        }
        toRemove.push(k);
      }
      if (toRemove.length) {
        changed = true;
        for (const k of toRemove) result.delete(k);
      }
    }
  }

  return result;
}

function detectWalls(
  spaceData: Array<{ counts: Map<string, number> }>
): Set<string> {
  const density = new Map<string, number>();
  for (const { counts } of spaceData) {
    for (const [key, c] of counts) {
      density.set(key, (density.get(key) ?? 0) + c);
    }
  }
  if (density.size === 0) return new Set();

  const edgeCells = new Set<string>();
  for (const key of density.keys()) {
    for (const nk of neighbourKeys(key)) {
      if (!density.has(nk)) {
        edgeCells.add(key);
        break;
      }
    }
  }

  const scores = new Map<string, number>();
  for (const [key, d] of density) {
    scores.set(key, d * (edgeCells.has(key) ? EDGE_BONUS : 1));
  }

  const sorted = [...scores.values()].sort((a, b) => a - b);
  const median = sorted[Math.floor(sorted.length / 2)] || 1;
  const highThresh = median * HIGH_FACTOR;
  const lowThresh = median * LOW_FACTOR;

  const wallCells = new Set<string>();
  const queue: string[] = [];
  for (const [key, s] of scores) {
    if (s >= highThresh) {
      wallCells.add(key);
      queue.push(key);
    }
  }

  while (queue.length) {
    const key = queue.pop()!;
    for (const nk of neighbourKeys(key)) {
      if (wallCells.has(nk)) continue;
      if ((scores.get(nk) ?? 0) >= lowThresh) {
        wallCells.add(nk);
        queue.push(nk);
      }
    }
  }

  // Hysteresis on the gap-bridge: a non-wall cell becomes wall if it has wall
  // neighbours on opposite sides (closes 1-cell gaps without growing walls).
  const bridges: string[] = [];
  for (const key of density.keys()) {
    if (wallCells.has(key)) continue;
    const [cx, cz] = key.split(",").map(Number);
    const w = wallCells.has(`${cx - 1},${cz}`);
    const e = wallCells.has(`${cx + 1},${cz}`);
    const n = wallCells.has(`${cx},${cz - 1}`);
    const s = wallCells.has(`${cx},${cz + 1}`);
    if ((w && e) || (n && s)) bridges.push(key);
  }
  for (const k of bridges) wallCells.add(k);

  // Keep only the largest 8-connected component. Walls of a real building form
  // a single continuous outline — disconnected fragments are scan noise / clutter.
  const visited = new Set<string>();
  let largest: string[] = [];
  for (const start of wallCells) {
    if (visited.has(start)) continue;
    const comp: string[] = [];
    const stack = [start];
    while (stack.length) {
      const k = stack.pop()!;
      if (visited.has(k)) continue;
      visited.add(k);
      comp.push(k);
      const [cx, cz] = k.split(",").map(Number);
      for (let dx = -1; dx <= 1; dx++) {
        for (let dz = -1; dz <= 1; dz++) {
          if (dx === 0 && dz === 0) continue;
          const nk = `${cx + dx},${cz + dz}`;
          if (wallCells.has(nk) && !visited.has(nk)) stack.push(nk);
        }
      }
    }
    if (comp.length > largest.length) largest = comp;
  }

  return thinSkeleton(new Set(largest));
}

export async function computeDivides(
  entries: Array<{ glbUrl: string; transform: RigidTransform | null }>,
  voxelSize = 0.15
): Promise<DivideResult> {
  if (entries.length < 2)
    return { segments: [], cells: [], spaceCount: entries.length };

  const loader = new GLTFLoader();

  const spaceData = await Promise.all(
    entries.map(async ({ glbUrl, transform }, idx) => {
      const matrix = rigidToMatrix(transform);
      const gltf = await new Promise<any>((resolve, reject) =>
        loader.load(glbUrl, resolve, undefined, reject)
      );
      gltf.scene.updateMatrixWorld(true);

      const counts = new Map<string, number>();
      const wallArea = new Map<string, number>();
      let minY = Infinity;

      gltf.scene.traverse((obj: THREE.Object3D) => {
        if (!(obj as THREE.Mesh).isMesh) return;
        const pos = (obj as THREE.Mesh).geometry.attributes.position;
        for (let i = 0; i < pos.count; i += 4) {
          const v = new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i));
          v.applyMatrix4((obj as THREE.Mesh).matrixWorld).applyMatrix4(matrix);
          if (v.y < minY) minY = v.y;
          const key = `${Math.floor(v.x / voxelSize)},${Math.floor(
            v.z / voxelSize
          )}`;
          counts.set(key, (counts.get(key) ?? 0) + 1);
        }
      });

      accumulateWallFaceArea(gltf.scene, matrix, voxelSize, wallArea);

      return { idx, counts, wallArea, minY };
    })
  );

  const allKeys = new Set<string>();
  for (const { counts } of spaceData) {
    for (const key of counts.keys()) allKeys.add(key);
  }

  const globalMinY = Math.min(...spaceData.map((s) => s.minY).filter(isFinite));

  const wallCells = detectWalls(spaceData.map((s) => ({ counts: s.wallArea })));

  // Assign winner only to non-wall cells.
  const cellWinner = new Map<string, number>();
  for (const key of allKeys) {
    if (wallCells.has(key)) continue;
    let bestIdx = -1;
    let bestCount = -1;
    for (const { idx, counts } of spaceData) {
      const c = counts.get(key) ?? 0;
      if (c > bestCount) {
        bestCount = c;
        bestIdx = idx;
      }
    }
    if (bestIdx >= 0) cellWinner.set(key, bestIdx);
  }

  // Keep only the largest connected component per space — orphan small islands.
  for (let idx = 0; idx < entries.length; idx++) {
    const owned = [...cellWinner.entries()]
      .filter(([, w]) => w === idx)
      .map(([k]) => k);
    if (owned.length === 0) continue;

    const visited = new Set<string>();
    const components: string[][] = [];

    for (const start of owned) {
      if (visited.has(start)) continue;
      const component: string[] = [];
      const queue = [start];
      while (queue.length > 0) {
        const key = queue.pop()!;
        if (visited.has(key)) continue;
        visited.add(key);
        component.push(key);
        const [cx, cz] = key.split(",").map(Number);
        for (const nk of [
          `${cx + 1},${cz}`,
          `${cx - 1},${cz}`,
          `${cx},${cz + 1}`,
          `${cx},${cz - 1}`,
        ]) {
          if (!visited.has(nk) && cellWinner.get(nk) === idx) queue.push(nk);
        }
      }
      components.push(component);
    }

    if (components.length <= 1) continue;
    const largest = components.reduce((a, b) => (a.length > b.length ? a : b));
    for (const comp of components) {
      if (comp === largest) continue;
      for (const key of comp) cellWinner.set(key, -1);
    }
  }

  // Multi-source BFS: flood-fill orphaned cells from nearest assigned neighbour,
  // never crossing wall cells.
  const bfsQueue: string[] = [];
  for (const [key, w] of cellWinner) {
    if (w >= 0) bfsQueue.push(key);
  }
  let head = 0;
  while (head < bfsQueue.length) {
    const key = bfsQueue[head++];
    const winner = cellWinner.get(key)!;
    const [cx, cz] = key.split(",").map(Number);
    for (const nk of [
      `${cx + 1},${cz}`,
      `${cx - 1},${cz}`,
      `${cx},${cz + 1}`,
      `${cx},${cz - 1}`,
    ]) {
      if (!wallCells.has(nk) && cellWinner.get(nk) === -1) {
        cellWinner.set(nk, winner);
        bfsQueue.push(nk);
      }
    }
  }

  const floorY = isFinite(globalMinY) ? globalMinY + 0.02 : 0;

  const segments: DivideSegment[] = [];
  const cells: DivideCell[] = [];

  for (const key of allKeys) {
    const [cx, cz] = key.split(",").map(Number);
    const winner = cellWinner.get(key);
    if (winner === undefined || winner === -1) continue;

    cells.push({
      x: (cx + 0.5) * voxelSize,
      z: (cz + 0.5) * voxelSize,
      floorY,
      ownerIdx: winner,
    });

    // Segment where this cell borders a wall or a differently-owned cell.
    const eastKey = `${cx + 1},${cz}`;
    const eastOwner = cellWinner.get(eastKey);
    if (
      wallCells.has(eastKey) ||
      (eastOwner !== undefined && eastOwner !== winner)
    ) {
      const x = (cx + 1) * voxelSize;
      segments.push({
        x1: x,
        z1: cz * voxelSize,
        x2: x,
        z2: (cz + 1) * voxelSize,
        floorY,
      });
    }

    const southKey = `${cx},${cz + 1}`;
    const southOwner = cellWinner.get(southKey);
    if (
      wallCells.has(southKey) ||
      (southOwner !== undefined && southOwner !== winner)
    ) {
      const z = (cz + 1) * voxelSize;
      segments.push({
        x1: cx * voxelSize,
        z1: z,
        x2: (cx + 1) * voxelSize,
        z2: z,
        floorY,
      });
    }
  }

  return { segments, cells, spaceCount: entries.length };
}

export async function computeWalls(
  _entries: Array<{ glbUrl: string; transform: RigidTransform | null }>,
  _sliceHeight = 1.0
): Promise<DivideResult> {
  return { segments: [], cells: [], spaceCount: 0 };
}
