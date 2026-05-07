import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import type { RigidTransform } from './types'

export interface DivideSegment {
  x1: number; z1: number
  x2: number; z2: number
  floorY: number
}

export interface DivideCell {
  x: number; z: number
  floorY: number
  ownerIdx: number
}

export interface DivideResult {
  segments: DivideSegment[]
  cells: DivideCell[]
  spaceCount: number
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
]

function rigidToMatrix(t: RigidTransform | null): THREE.Matrix4 {
  if (!t) return new THREE.Matrix4()
  const m = new THREE.Matrix4()
  m.compose(
    new THREE.Vector3(t.position.x, t.position.y, t.position.z),
    new THREE.Quaternion(t.quaternion.x, t.quaternion.y, t.quaternion.z, t.quaternion.w),
    new THREE.Vector3(1, 1, 1)
  )
  return m
}

export async function computeDivides(
  entries: Array<{ glbUrl: string; transform: RigidTransform | null }>,
  voxelSize = 0.15
): Promise<DivideResult> {
  if (entries.length < 2) return { segments: [], cells: [], spaceCount: entries.length }

  const loader = new GLTFLoader()

  const spaceData = await Promise.all(entries.map(async ({ glbUrl, transform }, idx) => {
    const matrix = rigidToMatrix(transform)
    const gltf = await new Promise<any>((resolve, reject) =>
      loader.load(glbUrl, resolve, undefined, reject)
    )
    gltf.scene.updateMatrixWorld(true)

    const counts = new Map<string, number>()
    let minY = Infinity

    gltf.scene.traverse((obj: THREE.Object3D) => {
      if (!(obj as THREE.Mesh).isMesh) return
      const pos = (obj as THREE.Mesh).geometry.attributes.position
      for (let i = 0; i < pos.count; i += 4) {
        const v = new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i))
        v.applyMatrix4((obj as THREE.Mesh).matrixWorld).applyMatrix4(matrix)
        if (v.y < minY) minY = v.y
        const key = `${Math.floor(v.x / voxelSize)},${Math.floor(v.z / voxelSize)}`
        counts.set(key, (counts.get(key) ?? 0) + 1)
      }
    })

    return { idx, counts, minY }
  }))

  const allKeys = new Set<string>()
  for (const { counts } of spaceData) {
    for (const key of counts.keys()) allKeys.add(key)
  }

  const cellWinner = new Map<string, number>()
  for (const key of allKeys) {
    let bestIdx = -1
    let bestCount = -1
    for (const { idx, counts } of spaceData) {
      const c = counts.get(key) ?? 0
      if (c > bestCount) { bestCount = c; bestIdx = idx }
    }
    if (bestIdx >= 0) cellWinner.set(key, bestIdx)
  }

  // Keep only the largest connected component per space — orphan small islands
  for (let idx = 0; idx < entries.length; idx++) {
    const owned = [...cellWinner.entries()].filter(([, w]) => w === idx).map(([k]) => k)
    if (owned.length === 0) continue

    const visited = new Set<string>()
    const components: string[][] = []

    for (const start of owned) {
      if (visited.has(start)) continue
      const component: string[] = []
      const queue = [start]
      while (queue.length > 0) {
        const key = queue.pop()!
        if (visited.has(key)) continue
        visited.add(key)
        component.push(key)
        const [cx, cz] = key.split(',').map(Number)
        for (const nk of [`${cx+1},${cz}`, `${cx-1},${cz}`, `${cx},${cz+1}`, `${cx},${cz-1}`]) {
          if (!visited.has(nk) && cellWinner.get(nk) === idx) queue.push(nk)
        }
      }
      components.push(component)
    }

    if (components.length <= 1) continue
    const largest = components.reduce((a, b) => a.length > b.length ? a : b)
    const largestSet = new Set(largest)
    for (const comp of components) {
      if (comp === largest) continue
      for (const key of comp) cellWinner.set(key, -1) // mark as orphaned
    }
  }

  // Multi-source BFS: flood-fill orphaned cells from nearest assigned neighbour
  const bfsQueue: string[] = []
  for (const [key, w] of cellWinner) {
    if (w >= 0) bfsQueue.push(key)
  }
  let head = 0
  while (head < bfsQueue.length) {
    const key = bfsQueue[head++]
    const winner = cellWinner.get(key)!
    const [cx, cz] = key.split(',').map(Number)
    for (const nk of [`${cx+1},${cz}`, `${cx-1},${cz}`, `${cx},${cz+1}`, `${cx},${cz-1}`]) {
      if (cellWinner.get(nk) === -1) {
        cellWinner.set(nk, winner)
        bfsQueue.push(nk)
      }
    }
  }

  const globalMinY = Math.min(...spaceData.map(s => s.minY).filter(isFinite))
  const floorY = isFinite(globalMinY) ? globalMinY + 0.02 : 0

  const segments: DivideSegment[] = []
  const cells: DivideCell[] = []

  for (const key of allKeys) {
    const [cx, cz] = key.split(',').map(Number)
    const winner = cellWinner.get(key)!

    cells.push({
      x: (cx + 0.5) * voxelSize,
      z: (cz + 0.5) * voxelSize,
      floorY,
      ownerIdx: winner,
    })

    const eastKey = `${cx + 1},${cz}`
    if (cellWinner.has(eastKey) && cellWinner.get(eastKey) !== winner) {
      const x = (cx + 1) * voxelSize
      segments.push({ x1: x, z1: cz * voxelSize, x2: x, z2: (cz + 1) * voxelSize, floorY })
    }

    const southKey = `${cx},${cz + 1}`
    if (cellWinner.has(southKey) && cellWinner.get(southKey) !== winner) {
      const z = (cz + 1) * voxelSize
      segments.push({ x1: cx * voxelSize, z1: z, x2: (cx + 1) * voxelSize, z2: z, floorY })
    }
  }

  return { segments, cells, spaceCount: entries.length }
}
