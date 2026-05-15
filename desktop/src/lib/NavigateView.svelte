<script lang="ts">
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import { exportNavMesh, NavMeshQuery, type NavMesh } from 'recast-navigation'
  import { floodFillPruneNavMesh } from '@recast-navigation/core'
  import * as THREE from 'three'
  import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js'
  import polygonClipping from 'polygon-clipping'
  import type { MultiPolygon } from 'polygon-clipping'
  import NavigateSceneInner from './NavigateSceneInner.svelte'
  import Sidebar from './Sidebar.svelte'
  import Checkbox from './Checkbox.svelte'
  import Button from './Button.svelte'
  import type { BoundingBox, Position, RigidTransform, RoomSegment } from './types'
  import { saveNavMesh, saveLocBoundingBox, supabase } from './supabase'
  import { buildNavMeshFromSpaces, loadNavMeshFromBuffer, computePath, pruneToLargestComponent, makeNavMeshResult, type NavMeshParams } from './navmesh'
  import { toast } from './toast'
  import { session } from './auth'
  import { get } from 'svelte/store'

  const MONO_URL = import.meta.env.VITE_MONO_URL as string

  interface Props {
    buildingId?: string | null;
    navmeshId?: string | null;
    buildingName: string;
    spaces: Array<{ id: string; url: string; transform: RigidTransform | null }>;
    existingNavMesh?: { url: string; buildSettings: Record<string, unknown> } | null;
    onback?: () => void;
  }

  let {
    buildingId = null,
    navmeshId = null,
    buildingName,
    spaces,
    existingNavMesh = null,
    onback
  }: Props = $props();

  type Phase = 'loading' | 'pickStart' | 'pickEnd' | 'result' | 'error'
  let phase = $state<Phase>('loading')
  let loadingMsg = $state('Loading models…')
  let error: string | null = $state(null)

  let navMesh: NavMesh | null = $state(null)
  let navQuery: NavMeshQuery | null = null
  let navMeshDebugMesh: THREE.Mesh | null = $state(null)
  let startPos: Position | null = $state(null)
  let endPos: Position | null = $state(null)
  let pathGeometry: THREE.TubeGeometry | null = $state(null)
  let pathLength = $state(0)
  let showNavMesh = $state(true)
  let showPruned = $state(false)
  let showParams = $state(true)
  let showRouteSection = $state(true)
  let showRoomSection = $state(true)
  let showRooms = $state(true)
  let showScan = $state(true)
  let showBoundingBoxes = $state(false)
  let collapsedBoxesBySpace: (BoundingBox | null)[] = $state([])
  let collapsedBoxes = $derived(collapsedBoxesBySpace.filter((b): b is BoundingBox => b !== null))
  let showCollapsedBoxes = $state(false)
  let tightBoxesBySpace: (BoundingBox | null)[] = $state([])
  let showTightBoxes = $state(false)
  let tightBoxes = $derived(tightBoxesBySpace.filter((b): b is BoundingBox => b !== null))

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

  function computeTightBoxes(): void {
    const buckets = assignRoomsToBuckets()
    const hulls: (BoundingBox | null)[] = spaces.map((space, i) => {
      if (buckets[i].length === 0) return null
      const bbOrig = (space as any).boundingBox as BoundingBox | null
      if (!bbOrig) return null
      const allVerts = buckets[i].flatMap(r => r.polygon_2d) as [number, number][]
      const hull = convexHull(allVerts)
      if (hull.length < 3) return null
      return { vertices_2d: hull, y_min: bbOrig.y_min, y_max: bbOrig.y_max }
    })

    const closeRing = (v: [number, number][]): [number, number][] => [...v, v[0]]
    const polyArea = (v: [number, number][]) => Math.abs(
      v.reduce((s, [x, z], k) => { const [nx, nz] = v[(k + 1) % v.length]; return s + x * nz - nx * z }, 0) / 2
    )

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

        // Subtract tight box j (j's firmly claimed area)
        if (tbJ && tbJ.vertices_2d.length >= 3 &&
            tbJ.vertices_2d.some(([x, z]) => pointInPolygon(x, z, bigPoly)))
          clips.push([[closeRing(tbJ.vertices_2d)]])

        // For the unclaimed overlap zone, split at the bisector between centroids
        // so each space keeps the half closer to it rather than leaving a void
        try {
          const overlapZone = polygonClipping.intersection([[closeRing(bigPoly)]], [[closeRing(bigPolyJ)]])
          if (overlapZone.length > 0) {
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
        } catch {}
      }

      let fragments: BoundingBox[]
      if (clips.length === 0) {
        fragments = [{ vertices_2d: bigPoly, y_min: bbOrig.y_min, y_max: bbOrig.y_max }]
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
          return [{ vertices_2d: verts, y_min: bbOrig.y_min, y_max: bbOrig.y_max }]
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
  let saveState: 'idle' | 'saving' | 'saved' | 'error' = $state('idle')
  let navMeshDirty = $state(false)
  let rooms: RoomSegment[] = $state([])
  let roomsState: 'idle' | 'computing' = $state('idle')
  let resolution: number = $state(0.2)

  async function fetchRooms(): Promise<void> {
    if (!navmeshId) return
    roomsState = 'computing'
    try {
      const token = get(session)?.access_token ?? ''
      const res = await fetch(`${MONO_URL}/navmesh-rooms/segment`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({ navmesh_id: navmeshId, resolution }),
      })
      if (!res.ok) throw new Error(`Room segmentation failed: ${res.status}`)
      rooms = await res.json()
      console.log(rooms.length, 'rooms fetched')
      computeTightBoxes()
    } catch (e) {
      toast((e as Error).message)
    } finally {
      roomsState = 'idle'
    }
  }

  let params: NavMeshParams = $state({
    boundsYMax: 3,
    cs: 0.1,
    ch: 0.1,
    walkableSlopeAngle: 35,
    walkableHeight: 2.0,
    walkableClimb: 0.3,
    walkableRadius: 0.1,
    maxEdgeLen: 4.0,
    maxSimplificationError: 1.3,
    minRegionArea: 0.08,
    mergeRegionArea: 0.2,
    maxVertsPerPoly: 6,
    detailSampleDist: 6,
    detailSampleMaxError: 1,
  })

  let prunedNavMeshMesh = $derived(navMeshDebugMesh ? pruneToLargestComponent(navMeshDebugMesh) : null)
  let activeNavMeshMesh = $derived(showPruned ? prunedNavMeshMesh : navMeshDebugMesh)
  let pickingEnabled = $derived(phase === 'pickStart' || phase === 'pickEnd')

  // Returns the centroid of the lowest-Y vertices in the debug mesh — reliably on
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
      await saveNavMesh(buildingId, data, glbData as ArrayBuffer, { ...params } as unknown as Record<string, unknown>)
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
      phase = 'pickStart'
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

      phase = 'pickStart'
    } catch (e) {
      error = (e as Error).message
      phase = 'error'
    }
  }

  onMount(async () => {
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

  function reset(): void {
    startPos = null
    endPos = null
    pathGeometry = null
    pathLength = 0
    error = null
    phase = 'pickStart'
  }
</script>

<Sidebar title={buildingName} {onback}>

  <!-- Visualisation toggles — always visible -->
  <section>
    <Checkbox bind:checked={showScan} label="Show scan" />
    <Checkbox bind:checked={showBoundingBoxes} label="Show bounding boxes" />
    <Checkbox bind:checked={showNavMesh} label="Show walkable area" />
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
  </section>

  <!-- Route -->
  <section class="collapsible-header" onclick={() => showRouteSection = !showRouteSection}>
    <label class="section-label" style="cursor:pointer;flex:1">Route</label>
    <span class="chevron" class:open={showRouteSection}>›</span>
  </section>
  {#if showRouteSection}
    <section class="collapsible-body">
      {#if phase === 'loading'}
        <p class="hint">{loadingMsg}</p>
        <div class="spinner"></div>

      {:else if phase === 'pickStart'}
        <p class="hint">Click the map to place your <strong class="green">start</strong> point.</p>

      {:else if phase === 'pickEnd'}
        <p class="hint">Click the map to place your <strong class="red">destination</strong>.</p>
        <Button style="width:100%" onclick={reset}>Reset</Button>

      {:else if phase === 'result'}
        <p class="distance">{pathLength.toFixed(1)}<span class="unit">m</span></p>
        <Button variant="primary" style="width:100%" onclick={reset}>New route</Button>

      {:else if phase === 'error'}
        <p class="hint danger">{error}</p>
        <Button style="width:100%" onclick={reset}>Try again</Button>
      {/if}
    </section>
  {/if}

  <!-- Room Division -->
  {#if navmeshId}
    <section class="collapsible-header" onclick={() => showRoomSection = !showRoomSection}>
      <label class="section-label" style="cursor:pointer;flex:1">Room Division</label>
      <span class="chevron" class:open={showRoomSection}>›</span>
    </section>
    {#if showRoomSection}
      <section class="collapsible-body">
        <div class="param-row">
          <label>Resolution</label>
          <input type="number" min="0.01" step="0.05" bind:value={resolution} />
        </div>
        <Button
          variant="primary"
          style="width:100%"
          disabled={roomsState === 'computing'}
          onclick={fetchRooms}
        >
          {roomsState === 'computing' ? 'Computing…' : rooms.length > 0 ? 'Recompute rooms' : 'Compute rooms'}
        </Button>
        {#if tightBoxes.length > 0}
          <Button style="width:100%" onclick={computeCollapsedBoxes}>
            {collapsedBoxes.length > 0 ? 'Recompute collapsed boxes' : 'Compute collapsed boxes'}
          </Button>
        {/if}
      </section>
    {/if}
  {/if}

  <!-- Navmesh Params -->
  <section class="collapsible-header" onclick={() => showParams = !showParams}>
    <label class="section-label" style="cursor:pointer;flex:1">Navmesh Params</label>
    <span class="chevron" class:open={showParams}>›</span>
  </section>
  {#if showParams}
    <section class="collapsible-body">
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
    </section>
  {/if}

</Sidebar>

<div class="canvas-wrap">
  <Canvas>
    <NavigateSceneInner
      {spaces}
      {showScan}
      {showBoundingBoxes}
      {startPos}
      {endPos}
      {pathGeometry}
      {pickingEnabled}
      navMeshMesh={showNavMesh ? activeNavMeshMesh : null}
      rooms={showRooms ? rooms : []}
      tightBoxes={showTightBoxes ? tightBoxes : []}
      collapsedBoxes={showCollapsedBoxes ? collapsedBoxes : []}
      onplace={handlePlace}
    />
  </Canvas>
</div>

<style>
  .canvas-wrap {
    flex: 1;
    height: 100vh;
    overflow: hidden;
  }

  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }
  .hint.danger { color: var(--danger); }
  .green { color: #00ff88; }
  .red { color: #ff4444; }

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

  .collapsible-header {
    flex-direction: row;
    align-items: center;
    cursor: pointer;
    user-select: none;
  }
  .collapsible-header:hover .section-label { color: var(--text); }

  .chevron {
    font-size: 16px;
    color: var(--text-muted);
    transition: transform 0.15s;
    transform: rotate(0deg);
  }
  .chevron.open { transform: rotate(90deg); }

  .collapsible-body { gap: 6px; }

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
</style>
