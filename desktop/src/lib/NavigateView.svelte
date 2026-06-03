<script lang="ts">
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import { exportNavMesh, NavMeshQuery, type NavMesh } from 'recast-navigation'
  import { floodFillPruneNavMesh } from '@recast-navigation/core'
  import * as THREE from 'three'
  import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js'
  import concaveman from 'concaveman'
  import polygonClipping from 'polygon-clipping'
  import type { MultiPolygon } from 'polygon-clipping'
  import NavigateSceneInner from './NavigateSceneInner.svelte'
  import Sidebar from './Sidebar.svelte'
  import DetailLayout from './DetailLayout.svelte'
  import Collapsible from './Collapsible.svelte'
  import ActionBanner from './ActionBanner.svelte'
  import Checkbox from './Checkbox.svelte'
  import Button from './Button.svelte'
  import type { BoundingBox, Position, RigidTransform, RoomSegment } from './types'
  import { saveNavMesh, saveLocBoundingBox, saveTightBoundingBox, supabase } from './supabase'
  import { buildNavMeshFromSpaces, loadNavMeshFromBuffer, computePath, pruneToLargestComponent, makeNavMeshResult, type NavMeshParams } from './navmesh'
  import { toast } from './toast'
  import { session } from './auth'
  import { get } from 'svelte/store'

  const MONO_URL = import.meta.env.VITE_MONO_URL as string

  interface Props {
    buildingId?: string | null;
    navmeshId?: string | null;
    buildingName: string;
    spaces: Array<{ id: string; url: string; transform: RigidTransform | null; tightBoundingBox?: BoundingBox | null }>;
    existingNavMesh?: { url: string; buildSettings: Record<string, unknown> } | null;
    existingFloorplanNavMesh?: { url: string; buildSettings: Record<string, unknown> } | null;
    floorplanId?: string | null;
    onback?: () => void;
  }

  let {
    buildingId = null,
    navmeshId = null,
    floorplanId = null,
    buildingName,
    spaces,
    existingNavMesh = null,
    existingFloorplanNavMesh = null,
    onback
  }: Props = $props();

  type Phase = 'loading' | 'idle' | 'pickStart' | 'pickEnd' | 'result' | 'error'
  let phase = $state<Phase>('loading')
  let loadingMsg = $state('Loading models…')
  let error: string | null = $state(null)

  let navMesh: NavMesh | null = $state(null)
  let navQuery: NavMeshQuery | null = null
  let navMeshDebugMesh: THREE.Mesh | null = $state(null)
  let floorplanDebugMesh: THREE.Mesh | null = $state(null)
  let startPos: Position | null = $state(null)
  let endPos: Position | null = $state(null)
  let pathGeometry: THREE.TubeGeometry | null = $state(null)
  let pathLength = $state(0)
  let showNavMesh = $state(true)
  let showFloorplanMesh = $state(false)
  let showPruned = $state(false)
  let showParams = $state(true)
  let showRouteSection = $state(true)
  let showRoomSection = $state(true)
  let showRooms = $state(true)
  let showScan = $state(true)
  let showBoundingBoxes = $state(false)
  let shadedBoxes = $state(false)
  let shadedBoxesCaps = $state(false)
  let collapsedBoxesBySpace: (BoundingBox | null)[] = $state([])
  let collapsedBoxes = $derived(collapsedBoxesBySpace.filter((b): b is BoundingBox => b !== null))
  let showCollapsedBoxes = $state(false)
  let tightBoxesBySpace: (BoundingBox | null)[] = $state([])
  let showTightBoxes = $state(false)
  let tightBoxes = $derived(tightBoxesBySpace.filter((b): b is BoundingBox => b !== null))

  function glbYToWorld(y: number, transform: RigidTransform | null): number {
    if (!transform) return y
    const { position: p, quaternion: q } = transform
    const Ryy = 1 - 2 * (q.x * q.x + q.z * q.z)
    return Ryy * y + p.y
  }

  function worldBB(bb: BoundingBox, transform: RigidTransform | null): [number, number][] {
    if (!transform) return bb.vertices_2d
    const { position: p, quaternion: q } = transform
    const yaw = Math.atan2(2 * (q.w * q.y + q.x * q.z), 1 - 2 * (q.y * q.y + q.z * q.z))
    const cos = Math.cos(yaw), sin = Math.sin(yaw)
    return bb.vertices_2d.map(([x, z]) => [
      cos * x + sin * z + p.x,
      -sin * x + cos * z + p.z,
    ])
  }

  function pointInPolygon(px: number, pz: number, poly: [number, number][]): boolean {
    let inside = false
    for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      const [xi, zi] = poly[i], [xj, zj] = poly[j]
      if (((zi > pz) !== (zj > pz)) && (px < (xj - xi) * (pz - zi) / (zj - zi) + xi))
        inside = !inside
    }
    return inside
  }

  function convexHull(pts: [number, number][]): [number, number][] {
    const sorted = [...pts].sort((a, b) => a[0] - b[0] || a[1] - b[1])
    const cross = (O: [number, number], A: [number, number], B: [number, number]) =>
      (A[0] - O[0]) * (B[1] - O[1]) - (A[1] - O[1]) * (B[0] - O[0])
    const lower: [number, number][] = []
    for (const p of sorted) {
      while (lower.length >= 2 && cross(lower[lower.length - 2], lower[lower.length - 1], p) <= 0) lower.pop()
      lower.push(p)
    }
    const upper: [number, number][] = []
    for (const p of [...sorted].reverse()) {
      while (upper.length >= 2 && cross(upper[upper.length - 2], upper[upper.length - 1], p) <= 0) upper.pop()
      upper.push(p)
    }
    lower.pop(); upper.pop()
    return [...lower, ...upper]
  }

  function assignRoomsToBuckets(): RoomSegment[][] {
    const spacePolys = spaces.map(space => {
      const bb = (space as any).boundingBox as BoundingBox | null
      if (!bb) return null
      return worldBB(bb, space.transform)
    })
    const buckets: RoomSegment[][] = spaces.map(() => [])
    for (const room of rooms) {
      let bestIdx = -1, bestCount = 0
      spacePolys.forEach((poly, i) => {
        if (!poly) return
        const count = room.polygon_2d.filter(([x, z]) => pointInPolygon(x, z, poly)).length
        if (count > bestCount) { bestCount = count; bestIdx = i }
      })
      if (bestIdx !== -1) buckets[bestIdx].push(room)
    }
    return buckets
  }

  async function computeTightBoxes(): Promise<void> {
    const buckets = assignRoomsToBuckets()
    const closeRing = (v: [number, number][]): [number, number][] => [...v, v[0]]
    const polyArea = (v: [number, number][]) => Math.abs(
      v.reduce((s, [x, z], k) => { const [nx, nz] = v[(k + 1) % v.length]; return s + x * nz - nx * z }, 0) / 2
    )

    const hulls: (BoundingBox | null)[] = spaces.map((space, i) => {
      if (buckets[i].length === 0) return null
      const bbOrig = (space as any).boundingBox as BoundingBox | null
      if (!bbOrig) return null
      const allVerts = buckets[i].flatMap(r => r.polygon_2d) as [number, number][]
      const hull = concaveman(allVerts, concavity)
      hull.pop() // concaveman closes the ring; drop the repeated first point
      if (hull.length < 3) return null
      return {
        vertices_2d: hull as [number, number][],
        y_min: glbYToWorld(bbOrig.y_min, space.transform),
        y_max: glbYToWorld(bbOrig.y_max, space.transform),
      }
    })

    const order = hulls
      .map((h, i) => [i, h ? polyArea(h.vertices_2d) : 0] as [number, number])
      .filter(([, a]) => a > 0)
      .sort(([, a], [, b]) => b - a)
      .map(([i]) => i)

    let claimed: MultiPolygon = []
    const result: (BoundingBox | null)[] = hulls.slice()

    for (const idx of order) {
      const h = hulls[idx]
      if (!h) continue
      const asMPoly: MultiPolygon = [[closeRing(h.vertices_2d)]]
      if (claimed.length === 0) {
        claimed = asMPoly
        continue
      }
      try {
        const clipped = polygonClipping.difference(asMPoly, claimed)
        if (clipped.length > 0) {
          const bestRing = clipped
            .map(p => p[0].slice(0, -1) as [number, number][])
            .reduce((a, b) => polyArea(a) >= polyArea(b) ? a : b)
          result[idx] = { vertices_2d: bestRing, y_min: h.y_min, y_max: h.y_max }
        } else {
          result[idx] = null
        }
      } catch {
        // keep original on clip failure
      }
      claimed = polygonClipping.union(claimed, asMPoly)
    }

    tightBoxesBySpace = result
    showTightBoxes = true

    await Promise.all(spaces.map((space, i) =>
      saveTightBoundingBox(space.id, result[i])
    ))
  }

  async function computeCollapsedBoxes(): Promise<void> {
    const spacePolys = spaces.map(space => {
      const bb = (space as any).boundingBox as BoundingBox | null
      if (!bb) return null
      return worldBB(bb, space.transform)
    })

    const buckets = assignRoomsToBuckets()
    const closeRing = (verts: [number, number][]): [number, number][] => [...verts, verts[0]]

    const centroidOf = (verts: [number, number][]): [number, number] => {
      const n = verts.length
      return [verts.reduce((s, [x]) => s + x, 0) / n, verts.reduce((s, [, z]) => s + z, 0) / n]
    }

    // Large polygon covering one side of the perpendicular bisector between ci and cj
    const EXTENT = 1e5
    const bisectorHalf = (ci: [number, number], cj: [number, number], side: 'i' | 'j'): [number, number][] => {
      const dx = cj[0] - ci[0], dz = cj[1] - ci[1]
      const len = Math.sqrt(dx * dx + dz * dz) || 1
      const nx = dx / len, nz = dz / len
      const px = -nz, pz = nx
      const mx = (ci[0] + cj[0]) / 2, mz = (ci[1] + cj[1]) / 2
      const s = side === 'i' ? -1 : 1
      return [
        [mx + px * EXTENT,                    mz + pz * EXTENT                   ],
        [mx - px * EXTENT,                    mz - pz * EXTENT                   ],
        [mx - px * EXTENT + s * nx * EXTENT,  mz - pz * EXTENT + s * nz * EXTENT ],
        [mx + px * EXTENT + s * nx * EXTENT,  mz + pz * EXTENT + s * nz * EXTENT ],
      ]
    }

    const area = (verts: [number, number][]) => Math.abs(
      verts.reduce((s, [x, z], k) => {
        const [nx, nz] = verts[(k + 1) % verts.length]
        return s + x * nz - nx * z
      }, 0) / 2
    )

    collapsedBoxesBySpace = spacePolys.map((bigPoly, i) => {
      if (!bigPoly || buckets[i].length === 0) return null
      const bbOrig = (spaces[i] as any).boundingBox as BoundingBox | null
      if (!bbOrig) return null

      const tbI = tightBoxesBySpace[i]
      const clips: MultiPolygon[] = []

      for (let j = 0; j < spaces.length; j++) {
        if (j === i) continue
        const bigPolyJ = spacePolys[j]
        if (!bigPolyJ) continue

        const tbJ = tightBoxesBySpace[j]

        try {
          const overlapZone = polygonClipping.intersection([[closeRing(bigPoly)]], [[closeRing(bigPolyJ)]])
          if (overlapZone.length > 0) {
            // Subtract tight box j from space i's area - use intersection test rather than
            // vertex-in-polygon which fails when tbJ straddles the boundary
            if (tbJ && tbJ.vertices_2d.length >= 3) {
              const tbJOverlap = polygonClipping.intersection([[closeRing(tbJ.vertices_2d)]], [[closeRing(bigPoly)]])
              if (tbJOverlap.length > 0) clips.push([[closeRing(tbJ.vertices_2d)]])
            }

            // Split the unclaimed overlap zone at the bisector between centroids
            let unclaimed = overlapZone
            if (tbI && tbI.vertices_2d.length >= 3)
              unclaimed = polygonClipping.difference(unclaimed, [[closeRing(tbI.vertices_2d)]])
            if (tbJ && tbJ.vertices_2d.length >= 3)
              unclaimed = polygonClipping.difference(unclaimed, [[closeRing(tbJ.vertices_2d)]])

            if (unclaimed.length > 0) {
              const ci = tbI && tbI.vertices_2d.length >= 3 ? centroidOf(tbI.vertices_2d) : centroidOf(bigPoly)
              const cj = tbJ && tbJ.vertices_2d.length >= 3 ? centroidOf(tbJ.vertices_2d) : centroidOf(bigPolyJ)
              const jHalf = bisectorHalf(ci, cj, 'j')
              const jPortion = polygonClipping.intersection(unclaimed, [[closeRing(jHalf)]])
              if (jPortion.length > 0) clips.push(jPortion)
            }
          }
        } catch (e) {
          console.warn(`[collapsedBox] clipping failed for spaces ${i}↔${j}:`, e)
        }
      }

      const yMin = glbYToWorld(bbOrig.y_min, spaces[i].transform)
      const yMax = glbYToWorld(bbOrig.y_max, spaces[i].transform)

      let fragments: BoundingBox[]
      if (clips.length === 0) {
        fragments = [{ vertices_2d: bigPoly, y_min: yMin, y_max: yMax }]
      } else {
        let result: MultiPolygon
        try {
          result = polygonClipping.difference([[closeRing(bigPoly)]], ...clips)
        } catch {
          return null
        }
        fragments = result.flatMap(poly => {
          const verts = poly[0].slice(0, -1) as [number, number][]
          if (verts.length < 3) return []
          return [{ vertices_2d: verts, y_min: yMin, y_max: yMax }]
        })
      }

      if (fragments.length === 0) return null
      return fragments.reduce((a, b) => area(a.vertices_2d) >= area(b.vertices_2d) ? a : b)
    })

    showCollapsedBoxes = true

    // Persist to Supabase
    await Promise.all(spaces.map((space, i) =>
      saveLocBoundingBox(space.id, collapsedBoxesBySpace[i])
    ))
  }
  let whiteBackground = $state(false)
  let exportTrigger = $state(0)

  function exportPng(): void {
    exportTrigger++
  }

  function handleExportBlob(blob: Blob): void {
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${buildingName}-navmesh.png`
    a.click()
    URL.revokeObjectURL(url)
  }

  let saveState: 'idle' | 'saving' | 'saved' | 'error' = $state('idle')
  let navMeshDirty = $state(false)
  let rooms: RoomSegment[] = $state([])
  let roomsState: 'idle' | 'computing' = $state('idle')
  let resolution: number = $state(0.2)
  let concavity: number = $state(30)

  async function fetchRooms(): Promise<void> {
    const segmentId = floorplanId ?? navmeshId
    if (!segmentId) return
    roomsState = 'computing'
    try {
      const token = get(session)?.access_token ?? ''
      const res = await fetch(`${MONO_URL}/navmesh-rooms/segment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ navmesh_id: segmentId, resolution }),
      })
      if (!res.ok) throw new Error(`Room segmentation failed: ${res.status}`)
      rooms = await res.json()
      console.log(rooms.length, 'rooms fetched')
      await computeTightBoxes()
      await computeCollapsedBoxes()
    } catch (e) {
      toast((e as Error).message)
    } finally {
      roomsState = 'idle'
    }
  }

  let params: NavMeshParams = $state({
    boundsYMax: 4.0,
    cs: 0.1,
    ch: 0.1,
    walkableSlopeAngle: 35,
    walkableHeight: 1.2,
    walkableClimb: 0.3,
    walkableRadius: 0,
    maxEdgeLen: 4.0,
    maxSimplificationError: 1.3,
    minRegionArea: 0.08,
    mergeRegionArea: 0.2,
    maxVertsPerPoly: 6,
    detailSampleDist: 6,
    detailSampleMaxError: 1,
  })

  let fpParams: NavMeshParams = $state({
    boundsYMax: 3,
    cs: 0.1,
    ch: 0.1,
    walkableSlopeAngle: 35,
    walkableHeight: 2.0,
    walkableClimb: 1.0,
    walkableRadius: 0,
    maxEdgeLen: 4.0,
    maxSimplificationError: 1.3,
    minRegionArea: 0.08,
    mergeRegionArea: 0.2,
    maxVertsPerPoly: 6,
    detailSampleDist: 6,
    detailSampleMaxError: 1,
  })
  let showFloorplanParams = $state(false)

  let prunedNavMeshMesh = $derived(navMeshDebugMesh ? pruneToLargestComponent(navMeshDebugMesh) : null)
  let activeNavMeshMesh = $derived(showPruned ? prunedNavMeshMesh : navMeshDebugMesh)
  let pickingEnabled = $derived(phase === 'pickStart' || phase === 'pickEnd')

  // Returns the centroid of the lowest-Y vertices in the debug mesh - reliably on
  // the floor rather than a table top or ceiling fragment.
  function floorSeedPoint(mesh: THREE.Mesh): { x: number; y: number; z: number } {
    const pos = mesh.geometry.attributes.position
    let minY = Infinity
    for (let i = 0; i < pos.count; i++) {
      const y = pos.getY(i)
      if (y < minY) minY = y
    }
    let sumX = 0, sumZ = 0, count = 0
    for (let i = 0; i < pos.count; i++) {
      if (Math.abs(pos.getY(i) - minY) < 0.1) {
        sumX += pos.getX(i)
        sumZ += pos.getZ(i)
        count++
      }
    }
    return { x: sumX / count, y: minY, z: sumZ / count }
  }

  async function handleSaveNavMesh(): Promise<void> {
    if (!navMesh || !navMeshDebugMesh || !buildingId) return
    saveState = 'saving'
    try {
      const data = exportNavMesh(navMesh)
      const exporter = new GLTFExporter()
      const glbData = await new Promise<ArrayBuffer>((resolve, reject) =>
        exporter.parse(navMeshDebugMesh!, resolve as (r: ArrayBuffer | object) => void, reject, { binary: true })
      )

      const fpResult = await buildNavMeshFromSpaces(spaces, fpParams)
      const fpData = exportNavMesh(fpResult.navMesh)
      const fpGlbData = await new Promise<ArrayBuffer>((resolve, reject) =>
        new GLTFExporter().parse(fpResult.debugMesh, resolve as (r: ArrayBuffer | object) => void, reject, { binary: true })
      )
      ;(fpResult.debugMesh.material as THREE.MeshStandardMaterial).color.set('#7b2fbe')
      floorplanDebugMesh = fpResult.debugMesh
      fpResult.navMesh.destroy()
      fpResult.navQuery.destroy()

      await saveNavMesh(
        buildingId,
        data,
        glbData as ArrayBuffer,
        { ...params } as unknown as Record<string, unknown>,
        { data: fpData, glbData: fpGlbData as ArrayBuffer, buildSettings: { ...fpParams } as unknown as Record<string, unknown> }
      )
      saveState = 'saved'
      navMeshDirty = false
    } catch (e) {
      toast((e as Error).message)
      saveState = 'error'
    }
  }

  function applyFloorPrune(result: { navMesh: NavMesh; navQuery: NavMeshQuery; debugMesh: THREE.Mesh }) {
    const seed = floorSeedPoint(result.debugMesh)
    const { success, nearestRef } = result.navQuery.findNearestPoly(seed, { halfExtents: { x: 2, y: 3, z: 2 } })
    if (!success) return result
    floodFillPruneNavMesh(result.navMesh, [nearestRef])
    // Rebuild debug mesh so the viewport reflects the pruned geometry.
    const pruned = makeNavMeshResult(result.navMesh)
    result.navQuery.destroy()
    return pruned
  }

  async function buildNavMesh(): Promise<void> {
    if (navQuery) { navQuery.destroy(); navQuery = null }
    if (navMesh) { navMesh.destroy(); navMesh = null }
    navMeshDebugMesh = null
    phase = 'loading'
    loadingMsg = 'Building navigation mesh…'
    error = null
    try {
      const result = applyFloorPrune(await buildNavMeshFromSpaces(spaces, params))
      navMesh = result.navMesh
      navQuery = result.navQuery
      navMeshDebugMesh = result.debugMesh
      navMeshDirty = true
      phase = 'idle'
      if (buildingId) await handleSaveNavMesh()
    } catch (e) {
      error = (e as Error).message
      phase = 'error'
    }
  }

  async function loadExistingNavMesh(): Promise<void> {
    if (!existingNavMesh) return
    phase = 'loading'
    loadingMsg = 'Loading saved navmesh…'
    try {
      const res = await fetch(existingNavMesh.url)
      if (!res.ok) throw new Error(`Failed to fetch navmesh: ${res.status}`)
      const buffer = await res.arrayBuffer()
      const result = applyFloorPrune(await loadNavMeshFromBuffer(new Uint8Array(buffer)))
      navMesh = result.navMesh
      navQuery = result.navQuery
      navMeshDebugMesh = result.debugMesh

      const bs = existingNavMesh.buildSettings
      for (const key of Object.keys(params) as (keyof typeof params)[]) {
        if (key in bs && typeof bs[key] === 'number') (params as Record<string, number>)[key] = bs[key] as number
      }

      if (existingFloorplanNavMesh) {
        const fpRes = await fetch(existingFloorplanNavMesh.url)
        if (fpRes.ok) {
          const fpBuf = await fpRes.arrayBuffer()
          const fpResult = applyFloorPrune(await loadNavMeshFromBuffer(new Uint8Array(fpBuf)))
          ;(fpResult.debugMesh.material as THREE.MeshStandardMaterial).color.set('#7b2fbe')
          floorplanDebugMesh = fpResult.debugMesh
          fpResult.navMesh.destroy()
          fpResult.navQuery.destroy()

          const fpBs = existingFloorplanNavMesh.buildSettings
          if (fpBs) {
            for (const key of Object.keys(fpParams) as (keyof typeof fpParams)[]) {
              if (key in fpBs && typeof fpBs[key] === 'number') (fpParams as Record<string, number>)[key] = fpBs[key] as number
            }
          }
        }
      }

      phase = 'idle'
    } catch (e) {
      error = (e as Error).message
      phase = 'error'
    }
  }

  onMount(async () => {
    tightBoxesBySpace = spaces.map(s => (s as any).tightBoundingBox ?? null)
    if (tightBoxesBySpace.some(b => b !== null)) showTightBoxes = true

    if (existingNavMesh) {
      await loadExistingNavMesh()
    } else {
      await buildNavMesh()
    }
  })

  function handlePlace(pos: Position): void {
    if (phase === 'pickStart') {
      startPos = pos
      phase = 'pickEnd'
    } else if (phase === 'pickEnd') {
      endPos = pos
      doComputePath()
    }
  }

  function doComputePath(): void {
    if (!navQuery || !startPos || !endPos) return
    try {
      const result = computePath(navQuery, startPos, endPos)
      pathGeometry = result.geometry
      pathLength = result.length
      phase = 'result'
    } catch (e) {
      error = (e as Error).message
      phase = 'error'
    }
  }

  function clearRoute(): void {
    startPos = null
    endPos = null
    pathGeometry = null
    pathLength = 0
    error = null
  }

  // Begin picking: prompt for the start point (instructions shown in the toast).
  function startRoute(): void {
    clearRoute()
    phase = 'pickStart'
  }

  // Abandon an in-progress route and return to idle.
  function cancelRoute(): void {
    clearRoute()
    phase = 'idle'
  }
</script>

<DetailLayout title={buildingName} {onback}>
<Sidebar>

  <!-- Visualisation toggles - always visible -->
  <section>
    <Checkbox bind:checked={showScan} label="Show scan" />
    <Checkbox bind:checked={showBoundingBoxes} label="Show bounding boxes" />
    {#if showBoundingBoxes || tightBoxes.length > 0 || collapsedBoxes.length > 0}
      <Checkbox bind:checked={shadedBoxes} label="Shade bounding boxes" />
      {#if shadedBoxes}
        <Checkbox bind:checked={shadedBoxesCaps} label="Shade caps" />
      {/if}
    {/if}
    <Checkbox bind:checked={showNavMesh} label="Show walkable area" />
    {#if floorplanDebugMesh}
      <Checkbox bind:checked={showFloorplanMesh} label="Show floorplan mesh" />
    {/if}
    <Checkbox bind:checked={showPruned} label="Show pruned only" />
    {#if rooms.length > 0}
      <Checkbox bind:checked={showRooms} label={`Show rooms (${rooms.length})`} />
    {/if}
    {#if tightBoxes.length > 0}
      <Checkbox bind:checked={showTightBoxes} label={`Show tight boxes (${tightBoxes.length})`} />
    {/if}
    {#if collapsedBoxes.length > 0}
      <Checkbox bind:checked={showCollapsedBoxes} label={`Show collapsed boxes (${collapsedBoxes.length})`} />
    {/if}
    <Checkbox bind:checked={whiteBackground} label="White background" />
  </section>

  <!-- Route -->
  <Collapsible title="Route" bind:open={showRouteSection}>
    {#if phase === 'loading'}
      <p class="hint">{loadingMsg}</p>
      <div class="spinner"></div>

    {:else if phase === 'idle'}
      <Button variant="primary" style="width:100%" onclick={startRoute}>Start route</Button>

    {:else if phase === 'pickStart' || phase === 'pickEnd'}
      <Button style="width:100%" onclick={cancelRoute}>Cancel</Button>

    {:else if phase === 'result'}
      <p class="distance">{pathLength.toFixed(1)}<span class="unit">m</span></p>
      <Button variant="primary" style="width:100%" onclick={startRoute}>New route</Button>

    {:else if phase === 'error'}
      <p class="hint danger">{error}</p>
      <Button style="width:100%" onclick={startRoute}>Try again</Button>
    {/if}
  </Collapsible>

  <!-- Room Division -->
  {#if navmeshId || floorplanId}
    <Collapsible title="Room Division" bind:open={showRoomSection}>
      <div class="param-row">
        <label>Resolution<span class="param-hint">higher = more rooms</span></label>
        <input type="number" min="0.01" step="0.05" bind:value={resolution} />
      </div>
      <div class="param-row">
        <label>Concavity<span class="param-hint">lower = tighter</span></label>
        <input type="number" min="0.1" step="0.5" bind:value={concavity} />
      </div>
      <Button
        variant="primary"
        style="width:100%"
        disabled={roomsState === 'computing'}
        onclick={fetchRooms}
      >
        {roomsState === 'computing' ? 'Computing…' : rooms.length > 0 ? 'Recompute rooms' : 'Compute rooms'}
      </Button>
    </Collapsible>
  {/if}

  <!-- Navmesh Params -->
  <Collapsible title="Navmesh Params" bind:open={showParams}>
      <div class="param-row">
        <label>Bounds Y max<span class="param-hint">m above floor</span></label>
        <input type="number" step="0.5" min="0.5" bind:value={params.boundsYMax} />
      </div>
      <div class="param-row">
        <label>Cell size (cs)<span class="param-hint">voxel XZ res</span></label>
        <input type="number" step="0.01" min="0.01" bind:value={params.cs} />
      </div>
      <div class="param-row">
        <label>Cell height (ch)<span class="param-hint">voxel Y res</span></label>
        <input type="number" step="0.01" min="0.01" bind:value={params.ch} />
      </div>
      <div class="param-row">
        <label>Walkable slope<span class="param-hint">degrees</span></label>
        <input type="number" step="1" min="0" max="90" bind:value={params.walkableSlopeAngle} />
      </div>
      <div class="param-row">
        <label>Walkable height<span class="param-hint">m</span></label>
        <input type="number" step="0.1" min="0.1" bind:value={params.walkableHeight} />
      </div>
      <div class="param-row">
        <label>Walkable climb<span class="param-hint">m</span></label>
        <input type="number" step="0.05" min="0" bind:value={params.walkableClimb} />
      </div>
      <div class="param-row">
        <label>Walkable radius<span class="param-hint">m</span></label>
        <input type="number" step="0.05" min="0" bind:value={params.walkableRadius} />
      </div>
      <div class="param-row">
        <label>Max edge len<span class="param-hint">m</span></label>
        <input type="number" step="0.5" min="0" bind:value={params.maxEdgeLen} />
      </div>
      <div class="param-row">
        <label>Max simplification err<span class="param-hint">m</span></label>
        <input type="number" step="0.1" min="0" bind:value={params.maxSimplificationError} />
      </div>
      <div class="param-row">
        <label>Min region area<span class="param-hint">m²</span></label>
        <input type="number" step="0.01" min="0" bind:value={params.minRegionArea} />
      </div>
      <div class="param-row">
        <label>Merge region area<span class="param-hint">m²</span></label>
        <input type="number" step="0.01" min="0" bind:value={params.mergeRegionArea} />
      </div>
      <div class="param-row">
        <label>Max verts/poly<span class="param-hint">3–6</span></label>
        <input type="number" step="1" min="3" max="6" bind:value={params.maxVertsPerPoly} />
      </div>
      <div class="param-row">
        <label>Detail sample dist<span class="param-hint">world units</span></label>
        <input type="number" step="1" min="0" bind:value={params.detailSampleDist} />
      </div>
      <div class="param-row">
        <label>Detail sample max err<span class="param-hint">world units</span></label>
        <input type="number" step="0.1" min="0" bind:value={params.detailSampleMaxError} />
      </div>
      <Button variant="primary" style="width:100%" onclick={buildNavMesh} disabled={saveState === 'saving'}>
        {saveState === 'saving' ? 'Saving…' : 'Rebuild'}
      </Button>
  </Collapsible>

  <!-- Floorplan Params -->
  <Collapsible title="Floorplan Params" bind:open={showFloorplanParams}>
      <div class="param-row">
        <label>Bounds Y max<span class="param-hint">m above floor</span></label>
        <input type="number" step="0.5" min="0.5" bind:value={fpParams.boundsYMax} />
      </div>
      <div class="param-row">
        <label>Cell size (cs)<span class="param-hint">voxel XZ res</span></label>
        <input type="number" step="0.01" min="0.01" bind:value={fpParams.cs} />
      </div>
      <div class="param-row">
        <label>Cell height (ch)<span class="param-hint">voxel Y res</span></label>
        <input type="number" step="0.01" min="0.01" bind:value={fpParams.ch} />
      </div>
      <div class="param-row">
        <label>Walkable slope<span class="param-hint">degrees</span></label>
        <input type="number" step="1" min="0" max="90" bind:value={fpParams.walkableSlopeAngle} />
      </div>
      <div class="param-row">
        <label>Walkable height<span class="param-hint">m</span></label>
        <input type="number" step="0.1" min="0.1" bind:value={fpParams.walkableHeight} />
      </div>
      <div class="param-row">
        <label>Walkable climb<span class="param-hint">m</span></label>
        <input type="number" step="0.05" min="0" bind:value={fpParams.walkableClimb} />
      </div>
      <div class="param-row">
        <label>Walkable radius<span class="param-hint">m</span></label>
        <input type="number" step="0.05" min="0" bind:value={fpParams.walkableRadius} />
      </div>
      <div class="param-row">
        <label>Max edge len<span class="param-hint">m</span></label>
        <input type="number" step="0.5" min="0" bind:value={fpParams.maxEdgeLen} />
      </div>
      <div class="param-row">
        <label>Max simplification err<span class="param-hint">m</span></label>
        <input type="number" step="0.1" min="0" bind:value={fpParams.maxSimplificationError} />
      </div>
      <div class="param-row">
        <label>Min region area<span class="param-hint">m²</span></label>
        <input type="number" step="0.01" min="0" bind:value={fpParams.minRegionArea} />
      </div>
      <div class="param-row">
        <label>Merge region area<span class="param-hint">m²</span></label>
        <input type="number" step="0.01" min="0" bind:value={fpParams.mergeRegionArea} />
      </div>
      <div class="param-row">
        <label>Max verts/poly<span class="param-hint">3–6</span></label>
        <input type="number" step="1" min="3" max="6" bind:value={fpParams.maxVertsPerPoly} />
      </div>
      <div class="param-row">
        <label>Detail sample dist<span class="param-hint">world units</span></label>
        <input type="number" step="1" min="0" bind:value={fpParams.detailSampleDist} />
      </div>
      <div class="param-row">
        <label>Detail sample max err<span class="param-hint">world units</span></label>
        <input type="number" step="0.1" min="0" bind:value={fpParams.detailSampleMaxError} />
      </div>
      <Button variant="primary" style="width:100%" onclick={handleSaveNavMesh} disabled={saveState === 'saving' || !navMesh}>
        {saveState === 'saving' ? 'Saving…' : 'Rebuild floorplan'}
      </Button>
  </Collapsible>

</Sidebar>

<div class="canvas-wrap">
  <Canvas rendererParameters={{ preserveDrawingBuffer: true, alpha: false }}>
    <NavigateSceneInner
      {spaces}
      {showScan}
      {showBoundingBoxes}
      {startPos}
      {endPos}
      {pathGeometry}
      {pickingEnabled}
      {whiteBackground}
      {shadedBoxes}
      {shadedBoxesCaps}
      {exportTrigger}
      exportScale={2}
      onexportblob={handleExportBlob}
      navMeshMesh={showNavMesh ? activeNavMeshMesh : null}
      floorplanMesh={showFloorplanMesh ? floorplanDebugMesh : null}
      rooms={showRooms ? rooms : []}
      tightBoxes={showTightBoxes ? tightBoxes : []}
      collapsedBoxes={showCollapsedBoxes ? collapsedBoxes : []}
      onplace={handlePlace}
    />
  </Canvas>
  <!-- <button class="bg-toggle" onclick={() => whiteBackground = !whiteBackground}>
    {whiteBackground ? 'Dark' : 'White'} bg
  </button> -->
  <button class="bg-toggle" style="bottom: 44px" onclick={exportPng}>
    Export PNG
  </button>
</div>
</DetailLayout>

{#if phase === 'pickStart'}
  <ActionBanner prompt="Click the map to set your" name="start point" oncancel={cancelRoute} />
{:else if phase === 'pickEnd'}
  <ActionBanner prompt="Click the map to set your" name="destination" oncancel={cancelRoute} />
{/if}

<style>
  .canvas-wrap {
    flex: 1;
    height: 100%;
    overflow: hidden;
    position: relative;
  }

  .bg-toggle {
    position: absolute;
    bottom: 12px;
    right: 12px;
    padding: 4px 10px;
    font-size: 12px;
    background: rgba(0,0,0,0.4);
    color: white;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 4px;
    cursor: pointer;
  }

  .bg-toggle:hover {
    background: rgba(0,0,0,0.6);
  }

  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }
  .hint.danger { color: var(--danger); }

  .distance {
    font-size: 36px;
    font-weight: 700;
    color: var(--accent);
    line-height: 1;
  }
  .unit { font-size: 16px; font-weight: 400; margin-left: 2px; }


  .spinner {
    width: 20px;
    height: 20px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  .param-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
    padding: 4px 0;
  }
  .param-row label {
    font-size: 11px;
    color: var(--text-muted);
    flex: 1;
    display: flex;
    flex-direction: column;
    gap: 1px;
  }
  .param-hint {
    font-size: 10px;
    color: var(--text-muted);
    opacity: 0.6;
  }
  .param-row input[type="number"] {
    width: 64px;
    padding: 3px 5px;
    font-size: 11px;
    text-align: right;
    background: var(--surface-raised, var(--surface));
    border: 1px solid var(--border);
    border-radius: 3px;
    color: var(--text);
    flex-shrink: 0;
  }
  .param-select {
    padding: 3px 5px;
    font-size: 11px;
    background: var(--surface-raised, var(--surface));
    border: 1px solid var(--border);
    border-radius: 3px;
    color: var(--text);
    flex-shrink: 0;
  }
</style>
