<script lang="ts">
  import { T } from '@threlte/core'
  import * as THREE from 'three'
  import type { BoundingBox } from './types'

  interface Props {
    boundingBox: BoundingBox
    color?: number
  }

  let { boundingBox: bb, color = 0x00ff88 }: Props = $props()

  const lineSegments = $derived.by(() => {
    const { vertices_2d: verts, y_min, y_max } = bb
    const n = verts.length
    const positions: number[] = []
    for (let i = 0; i < n; i++) {
      const [x0, z0] = verts[i]
      const [x1, z1] = verts[(i + 1) % n]
      positions.push(x0, y_min, z0,  x1, y_min, z1)  // bottom edge
      positions.push(x0, y_max, z0,  x1, y_max, z1)  // top edge
      positions.push(x0, y_min, z0,  x0, y_max, z0)  // vertical edge
    }
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
    return new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color }))
  })
</script>

<T is={lineSegments} />
