<script lang="ts">
  import { T } from '@threlte/core'
  import * as THREE from 'three'
  import type { BoundingBox } from './types'

  interface Props {
    boundingBox: BoundingBox
    color?: number
    shaded?: boolean
  }

  let { boundingBox: bb, color = 0x00ff88, shaded = false }: Props = $props()

  const geometry = $derived.by(() => {
    const { vertices_2d: verts, y_min, y_max } = bb
    const n = verts.length
    const positions: number[] = []
    const indices: number[] = []

    // Bottom ring (0..n-1), top ring (n..2n-1)
    for (const [x, z] of verts) {
      positions.push(x, y_min, z)
    }
    for (const [x, z] of verts) {
      positions.push(x, y_max, z)
    }

    // Side faces only
    for (let i = 0; i < n; i++) {
      const j = (i + 1) % n
      const b0 = i, b1 = j, t0 = i + n, t1 = j + n
      indices.push(b0, b1, t0, b1, t1, t0)
    }

    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
    geo.setIndex(indices)
    geo.computeVertexNormals()
    return geo
  })

  const lineSegments = $derived.by(() => {
    const { vertices_2d: verts, y_min, y_max } = bb
    const n = verts.length
    const positions: number[] = []
    for (let i = 0; i < n; i++) {
      const [x0, z0] = verts[i]
      const [x1, z1] = verts[(i + 1) % n]
      positions.push(x0, y_min, z0,  x1, y_min, z1)
      positions.push(x0, y_max, z0,  x1, y_max, z1)
      positions.push(x0, y_min, z0,  x0, y_max, z0)
    }
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
    return new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color }))
  })
</script>

{#if shaded}
  <T.Mesh geometry={geometry}>
    <T.MeshStandardMaterial
      {color}
      transparent
      opacity={0.15}
      side={THREE.DoubleSide}
      depthWrite={false}
    />
  </T.Mesh>
{/if}
<T is={lineSegments} />
