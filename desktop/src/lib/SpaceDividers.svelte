<script lang="ts">
  import { useThrelte } from '@threlte/core'
  import * as THREE from 'three'
  import { type DivideResult, SPACE_COLORS } from './computeDivides'

  interface Props {
    result: DivideResult
    cellOpacity?: number
    lineWidth?: number
  }

  let { result, cellOpacity = 0.45, lineWidth = 0.06 }: Props = $props()

  const { scene } = useThrelte()

  // PlaneGeometry(1,1) in XY → after Euler(-PI/2,0,0) lies flat in XZ:
  //   local X → world X,  local Y → world Z
  const flatQuat = new THREE.Quaternion().setFromEuler(new THREE.Euler(-Math.PI / 2, 0, 0))
  // For vertical walls:
  //   X-aligned segment (z=const): wall extends in X and Y — no rotation needed
  //   Z-aligned segment (x=const): wall extends in Z and Y — rotate PI/2 around Y
  const identityQuat = new THREE.Quaternion()
  const yHalfQuat = new THREE.Quaternion().setFromEuler(new THREE.Euler(0, Math.PI / 2, 0))
  const voxelSize = 0.15
  const wallHeight = 6.5

  $effect(() => {
    const { segments, cells } = result
    const added: THREE.Object3D[] = []

    // ── Coloured ownership cells ──
    if (cells.length > 0) {
      const cellGeo = new THREE.PlaneGeometry(1, 1)
      const cellMat = new THREE.MeshBasicMaterial({
        transparent: true,
        opacity: cellOpacity,
        depthWrite: false,
        side: THREE.DoubleSide,
      })
      const cellMesh = new THREE.InstancedMesh(cellGeo, cellMat, cells.length)
      cellMesh.instanceColor = new THREE.InstancedBufferAttribute(
        new Float32Array(cells.length * 3), 3
      )

      const matrix = new THREE.Matrix4()
      cells.forEach(({ x, z, floorY, ownerIdx }, i) => {
        matrix.compose(
          new THREE.Vector3(x, floorY, z),
          flatQuat,
          new THREE.Vector3(voxelSize * 0.98, voxelSize * 0.98, 1)
        )
        cellMesh.setMatrixAt(i, matrix)
        cellMesh.setColorAt(i, SPACE_COLORS[ownerIdx % SPACE_COLORS.length])
      })

      cellMesh.instanceMatrix.needsUpdate = true
      cellMesh.instanceColor!.needsUpdate = true
      scene.add(cellMesh)
      added.push(cellMesh)
    }

    // ── Boundary lines (white, slightly above cells) ──
    if (segments.length > 0) {
      const lineGeo = new THREE.PlaneGeometry(1, 1)
      const lineMat = new THREE.MeshBasicMaterial({
        color: 0xffffff,
        transparent: true,
        opacity: 0.65,
        depthWrite: false,
        side: THREE.DoubleSide,
      })
      const lineMesh = new THREE.InstancedMesh(lineGeo, lineMat, segments.length)
      const matrix = new THREE.Matrix4()

      segments.forEach(({ x1, z1, x2, z2, floorY }, i) => {
        const isZAligned = Math.abs(x2 - x1) < 0.001
        // X-aligned (z=const): PlaneGeometry in XY already extends in X+Y — use identity
        // Z-aligned (x=const): rotate PI/2 around Y so plane extends in Z+Y
        const quat = isZAligned ? yHalfQuat : identityQuat
        matrix.compose(
          new THREE.Vector3((x1 + x2) / 2, floorY + wallHeight / 2, (z1 + z2) / 2),
          quat,
          new THREE.Vector3(voxelSize, wallHeight, 1)
        )
        lineMesh.setMatrixAt(i, matrix)
      })

      lineMesh.instanceMatrix.needsUpdate = true
      scene.add(lineMesh)
      added.push(lineMesh)
    }

    return () => {
      for (const obj of added) {
        scene.remove(obj)
        const mesh = obj as THREE.InstancedMesh
        mesh.geometry.dispose()
        ;(mesh.material as THREE.Material).dispose()
      }
    }
  })
</script>
