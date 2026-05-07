<script lang="ts">
  import { useThrelte } from '@threlte/core'
  import * as THREE from 'three'
  import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'

  interface Props {
    glbUrl: string
    voxelSize?: number
    opacity?: number
  }

  let { glbUrl, voxelSize = 0.15, opacity = 0.82 }: Props = $props()

  const { scene } = useThrelte()

  // jet-style: blue → cyan → green → yellow → red
  function heatColor(t: number): THREE.Color {
    const r = t < 0.5 ? 0 : (t - 0.5) * 2
    const g = t < 0.25 ? t * 4 : t < 0.75 ? 1 : (1 - t) * 4
    const b = t < 0.25 ? 1 : t < 0.5 ? (0.5 - t) * 4 : 0
    return new THREE.Color(r, g, b)
  }

  async function buildHeatmap(url: string): Promise<THREE.InstancedMesh | null> {
    const loader = new GLTFLoader()
    const gltf = await new Promise<any>((resolve, reject) =>
      loader.load(url, resolve, undefined, reject)
    )
    gltf.scene.updateMatrixWorld(true)

    const counts = new Map<string, number>()
    let minY = Infinity

    gltf.scene.traverse((obj: THREE.Object3D) => {
      if (!(obj as THREE.Mesh).isMesh) return
      const pos = (obj as THREE.Mesh).geometry.attributes.position
      for (let i = 0; i < pos.count; i++) {
        const v = new THREE.Vector3(pos.getX(i), pos.getY(i), pos.getZ(i))
        v.applyMatrix4((obj as THREE.Mesh).matrixWorld)
        if (v.y < minY) minY = v.y
        const key = `${Math.floor(v.x / voxelSize)},${Math.floor(v.z / voxelSize)}`
        counts.set(key, (counts.get(key) ?? 0) + 1)
      }
    })

    if (counts.size === 0) return null

    const maxCount = Math.max(...counts.values())
    const cells = Array.from(counts.entries())
    const floorY = isFinite(minY) ? minY + 0.02 : 0

    const geo = new THREE.PlaneGeometry(voxelSize * 0.96, voxelSize * 0.96)
    const mat = new THREE.MeshBasicMaterial({
      transparent: true,
      opacity,
      depthWrite: false,
      side: THREE.DoubleSide,
    })

    const mesh = new THREE.InstancedMesh(geo, mat, cells.length)
    mesh.instanceColor = new THREE.InstancedBufferAttribute(
      new Float32Array(cells.length * 3), 3
    )

    const quat = new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, 0))
    const matrix = new THREE.Matrix4()

    cells.forEach(([key, count], i) => {
      const [cx, cz] = key.split(',').map(Number)
      matrix.compose(
        new THREE.Vector3((cx + 0.5) * voxelSize, floorY, (cz + 0.5) * voxelSize),
        quat,
        new THREE.Vector3(1, 1, 1)
      )
      mesh.setMatrixAt(i, matrix)
      mesh.setColorAt(i, heatColor(count / maxCount))
    })

    mesh.instanceMatrix.needsUpdate = true
    mesh.instanceColor!.needsUpdate = true
    return mesh
  }

  $effect(() => {
    const url = glbUrl
    let cancelled = false
    let addedMesh: THREE.InstancedMesh | null = null

    buildHeatmap(url).then(mesh => {
      if (cancelled || !mesh) return
      addedMesh = mesh
      scene.add(mesh)
    })

    return () => {
      cancelled = true
      if (addedMesh) {
        scene.remove(addedMesh)
        addedMesh.geometry.dispose()
        ;(addedMesh.material as THREE.Material).dispose()
      }
    }
  })
</script>
