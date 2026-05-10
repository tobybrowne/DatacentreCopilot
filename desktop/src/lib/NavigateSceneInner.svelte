<script lang="ts">
  import { T, useThrelte } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity, type IntersectionEvent } from '@threlte/extras'
  import * as THREE from 'three'
  import BoundingBoxMesh from './BoundingBoxMesh.svelte'
  import type { BoundingBox, Position, RigidTransform, RoomSegment } from './types'

  const ROOM_COLORS = [
    0x00d4ff, 0xff5050, 0x50ff78, 0xffc800,
    0xb450ff, 0xff8c00, 0x00b4ff, 0xff3cb4,
    0x3cdcb4, 0xc8ff3c, 0xffa078, 0x7878ff,
  ]

  const COLLAPSED_BOX_COLORS = [
    0xffa500, 0xff69b4, 0x7fff00, 0x00ced1,
    0xff6347, 0xba55d3, 0x20b2aa, 0xffd700,
  ]

  interface Props {
    spaces: Array<{ url: string; transform: RigidTransform | null; boundingBox?: BoundingBox | null }>;
    showBoundingBoxes?: boolean;
    showScan?: boolean;
    startPos?: Position | null;
    endPos?: Position | null;
    pathGeometry?: THREE.TubeGeometry | null;
    navMeshMesh?: THREE.Mesh | null;
    recastInputDebug?: THREE.Group | null;
    rooms?: RoomSegment[];
    tightBoxes?: BoundingBox[];
    collapsedBoxes?: BoundingBox[];
    pickingEnabled?: boolean;
    onplace?: (pos: Position) => void;
  }

  let {
    spaces,
    showBoundingBoxes = false,
    showScan = true,
    startPos = null,
    endPos = null,
    pathGeometry = null,
    navMeshMesh = null,
    recastInputDebug = null,
    rooms = [],
    tightBoxes = [],
    collapsedBoxes = [],
    pickingEnabled = false,
    onplace
  }: Props = $props();

  const { invalidate } = useThrelte()
  const rot = new THREE.Matrix4().makeRotationX(Math.PI / 2)
  const roomsGroup = new THREE.Group()
  const tightBoxesGroup = new THREE.Group()
  const collapsedBoxesGroup = new THREE.Group()

  $effect(() => {
    roomsGroup.clear()
    rooms.forEach((room, i) => {
      const pts = room.polygon_2d
      const y = room.y_min - 1.0

      const shape = new THREE.Shape()
      shape.moveTo(pts[0][0], pts[0][1])
      for (let j = 1; j < pts.length; j++) shape.lineTo(pts[j][0], pts[j][1])
      shape.closePath()
      const fillGeo = new THREE.ShapeGeometry(shape)
      fillGeo.applyMatrix4(rot)
      const fill = new THREE.Mesh(fillGeo, new THREE.MeshBasicMaterial({
        color: ROOM_COLORS[i % ROOM_COLORS.length],
        transparent: true,
        opacity: 0.15,
        side: THREE.DoubleSide,
        depthWrite: false,
      }))
      fill.position.y = y
      roomsGroup.add(fill)

      const loopPts = [...pts, pts[0]].map(([x, z]) => new THREE.Vector3(x, 0, z))
      const outline = new THREE.Line(
        new THREE.BufferGeometry().setFromPoints(loopPts),
        new THREE.LineBasicMaterial({ color: 0xffffff, opacity: 0.9, transparent: true })
      )
      outline.position.y = y
      roomsGroup.add(outline)
    })
    invalidate()
  })

  const TIGHT_BOX_COLORS = [
    0xff8800, 0xff00cc, 0x00ffcc, 0xffff00,
    0x00aaff, 0xaa00ff, 0xff4400, 0x00ff44,
  ]

  $effect(() => {
    tightBoxesGroup.clear()
    tightBoxes.forEach((bb, i) => {
      const color = TIGHT_BOX_COLORS[i % TIGHT_BOX_COLORS.length]
      const { vertices_2d: verts, y_min, y_max } = bb
      const n = verts.length
      const positions: number[] = []
      for (let j = 0; j < n; j++) {
        const [x0, z0] = verts[j]
        const [x1, z1] = verts[(j + 1) % n]
        positions.push(x0, y_min, z0, x1, y_min, z1)
        positions.push(x0, y_max, z0, x1, y_max, z1)
        positions.push(x0, y_min, z0, x0, y_max, z0)
      }
      const geo = new THREE.BufferGeometry()
      geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
      tightBoxesGroup.add(new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color })))
    })
    invalidate()
  })

  $effect(() => {
    collapsedBoxesGroup.clear()
    collapsedBoxes.forEach((bb, i) => {
      const color = COLLAPSED_BOX_COLORS[i % COLLAPSED_BOX_COLORS.length]
      const { vertices_2d: verts, y_min, y_max } = bb
      const n = verts.length
      const positions: number[] = []
      for (let j = 0; j < n; j++) {
        const [x0, z0] = verts[j]
        const [x1, z1] = verts[(j + 1) % n]
        positions.push(x0, y_min, z0, x1, y_min, z1)
        positions.push(x0, y_max, z0, x1, y_max, z1)
        positions.push(x0, y_min, z0, x0, y_max, z0)
      }
      const geo = new THREE.BufferGeometry()
      geo.setAttribute('position', new THREE.Float32BufferAttribute(positions, 3))
      collapsedBoxesGroup.add(new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color })))
    })
    invalidate()
  })

  interactivity()

  function handleClick(e: IntersectionEvent<MouseEvent>): void {
    if (!pickingEnabled) return
    e.stopPropagation()
    const point: THREE.Vector3 = e.point
    if (!point) return
    onplace?.({ x: point.x, y: point.y, z: point.z })
  }

  // Per-space group refs for applying quaternion transforms
  let groupRefs: (THREE.Group | undefined)[] = $state([])

  $effect(() => {
    spaces.forEach((space, i) => {
      const g = groupRefs[i]
      if (!g) return
      if (space.transform) {
        const { position: p, quaternion: q } = space.transform
        g.position.set(p.x, p.y, p.z)
        g.quaternion.set(q.x, q.y, q.z, q.w)
      } else {
        g.position.set(0, 0, 0)
        g.quaternion.identity()
      }
    })
  })
</script>

<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} />

<T.PerspectiveCamera makeDefault position={[0, 2, 5]} fov={60}>
  <OrbitControls minDistance={0.5} screenSpacePanning={true} />
</T.PerspectiveCamera>

{#each spaces as space, i (space.url)}
  <T.Group bind:ref={groupRefs[i]}>
    {#if showScan}
      <GLTF url={space.url} onclick={handleClick} />
    {/if}
    {#if showBoundingBoxes && space.boundingBox}
      <BoundingBoxMesh boundingBox={space.boundingBox} />
    {/if}
  </T.Group>
{/each}

{#if startPos}
  <T.Mesh position={[startPos.x, startPos.y + 0.1, startPos.z]}>
    <T.SphereGeometry args={[0.12, 16, 16]} />
    <T.MeshStandardMaterial color={0x00ff88} emissive={0x00ff88} emissiveIntensity={0.8} />
  </T.Mesh>
{/if}

{#if endPos}
  <T.Mesh position={[endPos.x, endPos.y + 0.1, endPos.z]}>
    <T.SphereGeometry args={[0.12, 16, 16]} />
    <T.MeshStandardMaterial color={0xff4444} emissive={0xff4444} emissiveIntensity={0.8} />
  </T.Mesh>
{/if}

{#if pathGeometry}
  <T.Mesh geometry={pathGeometry}>
    <T.MeshStandardMaterial color={0x00d4ff} emissive={0x00d4ff} emissiveIntensity={0.6} />
  </T.Mesh>
{/if}

{#if navMeshMesh}
  <T is={navMeshMesh} />
{/if}

{#if recastInputDebug}
  <T is={recastInputDebug} />
{/if}

<T is={roomsGroup} />
<T is={tightBoxesGroup} />
<T is={collapsedBoxesGroup} />
