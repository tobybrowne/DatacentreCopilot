import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import type { BuildingSpace, Position, RigidTransform } from './types'

const DEFAULT_VOXEL_SIZE = 0.5  // metres

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

async function loadBuildingVertices(glbUrl: string, matrix: THREE.Matrix4, step = 10): Promise<THREE.Vector3[]> {
  const loader = new GLTFLoader()
  const gltf = await new Promise<any>((resolve, reject) => loader.load(glbUrl, resolve, undefined, reject))
  gltf.scene.updateMatrixWorld(true)
  const out: THREE.Vector3[] = []
  gltf.scene.traverse((obj: THREE.Object3D) => {
    if (!(obj as THREE.Mesh).isMesh) return
    const pos = (obj as THREE.Mesh).geometry.attributes.position
    for (let i = 0; i < pos.count; i += step) {
      const v = new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i))
      v.applyMatrix4((obj as THREE.Mesh).matrixWorld).applyMatrix4(matrix)
      out.push(v)
    }
  })
  return out
}

interface SpaceEntry {
  bs: BuildingSpace
  glbUrl: string
}

export interface CentroidResult {
  centroids: Map<string, Position>
  voronoiPoints: Map<string, Position[]>
}

export async function computeCentroids(spaces: SpaceEntry[], voxelSize = DEFAULT_VOXEL_SIZE, overlapPenalty = 1): Promise<CentroidResult> {
  const loaded = await Promise.all(spaces.map(async ({ bs, glbUrl }) => {
    const matrix = rigidToMatrix(bs.offset_transformation)
    const invMatrix = matrix.clone().invert()
    const vertices = await loadBuildingVertices(glbUrl, matrix)
    const bbox = new THREE.Box3().setFromPoints(vertices)
    return { bs, matrix, invMatrix, vertices, bbox }
  }))

  // Voxel occupancy: key -> Set of owning space_ids
  const cellOwners = new Map<string, Set<string>>()
  for (const space of loaded) {
    for (const v of space.vertices) {
      const key = `${Math.floor(v.x / voxelSize)},${Math.floor(v.z / voxelSize)}`
      if (!cellOwners.has(key)) cellOwners.set(key, new Set())
      cellOwners.get(key)!.add(space.bs.space_id)
    }
  }

  // Weighted centroid per space (building frame)
  const buildingCentroids = new Map<string, THREE.Vector3>()
  const centroids = new Map<string, Position>()

  for (const space of loaded) {
    let sumX = 0, sumZ = 0, totalWeight = 0
    const seen = new Set<string>()

    for (const v of space.vertices) {
      const cx = Math.floor(v.x / voxelSize)
      const cz = Math.floor(v.z / voxelSize)
      const key = `${cx},${cz}`
      if (seen.has(key)) continue
      seen.add(key)
      const owners = cellOwners.get(key)!
      const w = 1 / Math.pow(owners.size, overlapPenalty)
      sumX += (cx + 0.5) * voxelSize * w
      sumZ += (cz + 0.5) * voxelSize * w
      totalWeight += w
    }

    const centerY = (space.bbox.min.y + space.bbox.max.y) / 2
    const bc = new THREE.Vector3(sumX / totalWeight, centerY, sumZ / totalWeight)
    buildingCentroids.set(space.bs.space_id, bc)

    const local = bc.clone().applyMatrix4(space.invMatrix)
    centroids.set(space.bs.space_id, { x: local.x, y: local.y, z: local.z })
  }

  // Voronoi: assign every known cell to the closest centroid (XZ only)
  const voronoiPoints = new Map<string, Position[]>()
  for (const id of buildingCentroids.keys()) voronoiPoints.set(id, [])

  const spaceY = new Map(loaded.map(s => [s.bs.space_id, (s.bbox.min.y + s.bbox.max.y) / 2]))

  for (const [key, owners] of cellOwners) {
    const [cx, cz] = key.split(',').map(Number)
    const x = (cx + 0.5) * voxelSize
    const z = (cz + 0.5) * voxelSize

    let closestId = ''
    let closestDist = Infinity
    for (const [id, bc] of buildingCentroids) {
      const dx = x - bc.x, dz = z - bc.z
      const d = dx * dx + dz * dz
      if (d < closestDist) { closestDist = d; closestId = id }
    }

    const y = spaceY.get(closestId) ?? 0
    voronoiPoints.get(closestId)!.push({ x, y, z })
  }

  return { centroids, voronoiPoints }
}
