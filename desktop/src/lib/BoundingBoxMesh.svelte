<script lang="ts">
  import { T, useThrelte } from '@threlte/core'
  import * as THREE from 'three'
  import { LineSegments2 } from 'three/examples/jsm/lines/LineSegments2.js'
  import { LineSegmentsGeometry } from 'three/examples/jsm/lines/LineSegmentsGeometry.js'
  import { LineMaterial } from 'three/examples/jsm/lines/LineMaterial.js'
  import type { BoundingBox } from './types'

  interface Props {
    boundingBox: BoundingBox
    color?: number
    shaded?: boolean
    shadedCaps?: boolean
  }

  let { boundingBox: bb, color = 0x00ff88, shaded = false, shadedCaps = false }: Props = $props()

  const { size } = useThrelte()

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

  const capGeometry = $derived.by(() => {
    const { vertices_2d: verts, y_min, y_max } = bb
    const n = verts.length
    const positions: number[] = []
    for (const [x, z] of verts) positions.push(x, y_min, z)
    for (const [x, z] of verts) positions.push(x, y_max, z)
    const contour = verts.map(([x, z]) => new THREE.Vector2(x, z))
    const tris = THREE.ShapeUtils.triangulateShape(contour, [])
    const indices: number[] = []
    for (const [a, b, c] of tris) {
      indices.push(a, b, c)
      indices.push(n + a, n + c, n + b)
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
      positions.push(x0, y_min, z0, x1, y_min, z1)
      positions.push(x0, y_max, z0, x1, y_max, z1)
      positions.push(x0, y_min, z0, x0, y_max, z0)
    }
    const geo = new LineSegmentsGeometry()
    geo.setPositions(positions)
    const mat = new LineMaterial({ color, linewidth: 1.5 })
    mat.resolution.set(size.current.width, size.current.height)
    return new LineSegments2(geo, mat)
  })
</script>

{#if shaded}
  <T.Mesh geometry={geometry}>
    <T.MeshStandardMaterial {color} transparent opacity={0.4} side={THREE.DoubleSide} depthWrite={false} />
  </T.Mesh>
{/if}
{#if shadedCaps}
  <T.Mesh geometry={capGeometry}>
    <T.MeshStandardMaterial {color} transparent opacity={0.4} side={THREE.DoubleSide} depthWrite={false} />
  </T.Mesh>
{/if}
<T is={lineSegments} />
