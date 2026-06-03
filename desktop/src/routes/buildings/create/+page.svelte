<script lang="ts">
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { onMount } from 'svelte'
  import { get } from 'svelte/store'
  import { Canvas } from '@threlte/core'
  import { fetchSpaces, fetchBuildingById, getSpaceGlbUrl, createDraftBuilding, prepareAddSpace, resetBuildingForRestitch, updateBuildingSpaceTransform, finalizeDraftBuilding } from '$lib/supabase'
  import { session } from '$lib/auth'
  import BuildingStitchScene from '$lib/BuildingStitchScene.svelte'
  import NavigateSceneInner from '$lib/NavigateSceneInner.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import DetailLayout from '$lib/DetailLayout.svelte'
  import Button from '$lib/Button.svelte'
  import { downloadMergedGlb as mergeAndDownloadGlb } from '$lib/glbMerge'
  import { overlapArea, extractYaw } from '$lib/polygon2d'
  import type { Building, RigidTransform, Space } from '$lib/types'

  const MONO_URL = import.meta.env.VITE_MONO_URL as string
  const draftId = $page.url.searchParams.get('draft') ?? undefined
  const restitchId = $page.url.searchParams.get('restitch') ?? undefined
  const addSpaceId = $page.url.searchParams.get('addspace') ?? undefined

  type Phase = 'setup' | 'align'

  interface SpaceEntry {
    space: Space
    glbUrl: string
    transform: RigidTransform | null
  }

  let showBoundingBoxes = $state(false)
  let exportTrigger = $state(0)

  function handleExportBlob(blob: Blob): void {
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = 'building-stitch.png'
    a.click()
    URL.revokeObjectURL(url)
  }

  let allSpaces: Space[] = $state([])
  let buildingName = $state('')
  let orderedSpaceIds: string[] = $state([])

  let phase = $state<Phase>('setup')
  let builtSpaces: SpaceEntry[] = $state([])
  // The scan currently being aligned (chosen by the user); null = picking next.
  let currentSpaceId: string | null = $state(null)
  let activeBuildingId: string | null = null

  let bX = $state(0)
  let bY = $state(0)
  let bZ = $state(0)
  let bYDeg = $state(0)
  let bYRot = $derived((bYDeg * Math.PI) / 180)
  let mode: 'translate' | 'rotate' = $state('translate')

  let frozenCount = $state(0)
  let frozenSpaces: SpaceEntry[] = []

  let refining = $state(false)
  let alignResult: { fitness: number; inlier_rmse: number } | null = $state(null)
  let saving = $state(false)
  let error: string | null = $state(null)

  onMount(async () => {
    try {
      allSpaces = await fetchSpaces()
      if (draftId) {
        const draft = await fetchBuildingById(draftId)
        await resumeBuilding(draft)
      } else if (restitchId) {
        const existing = await fetchBuildingById(restitchId)
        buildingName = existing.name ?? ''
      } else if (addSpaceId) {
        const existing = await fetchBuildingById(addSpaceId)
        await loadForAddSpace(existing)
      }
    } catch (e) { error = (e as Error).message }
  })

  // The building being edited (if any) — its own spaces remain selectable.
  const editingBuildingId = draftId ?? restitchId ?? addSpaceId ?? null
  let glbSpaces = $derived(allSpaces.filter(s => s.glb_path))
  // Only offer spaces not already assigned to another building.
  let availableSpaces = $derived(glbSpaces.filter(s => s.building_id == null || s.building_id === editingBuildingId))
  let unselectedSpaces = $derived(availableSpaces.filter(s => !orderedSpaceIds.includes(s.id)))
  let currentSpace = $derived(currentSpaceId ? allSpaces.find(s => s.id === currentSpaceId) ?? null : null)
  let builtSpacesForScene = $derived(builtSpaces.map(e => ({ url: e.glbUrl, transform: e.transform, boundingBox: e.space.bounding_box })))

  // Selected scans not yet placed and not currently being aligned — the pool to pick from.
  let placedIds = $derived(new Set(builtSpaces.map(e => e.space.id)))
  let remainingSpaces = $derived(
    orderedSpaceIds
      .filter(id => !placedIds.has(id) && id !== currentSpaceId)
      .map(id => allSpaces.find(s => s.id === id))
      .filter((s): s is Space => !!s)
  )
  // Before any reference scan is placed, the first pick just anchors the origin.
  let needsReference = $derived(builtSpaces.length === 0)
  // Every selected scan placed and nothing mid-alignment → ready to save.
  let allPlaced = $derived(
    builtSpaces.length > 0 && !currentSpaceId && orderedSpaceIds.every(id => placedIds.has(id))
  )

  const bestReferenceIndex = $derived.by(() => {
    if (builtSpaces.length === 0) return null
    const newBB = currentSpace?.bounding_box

    // Try overlap first
    if (newBB) {
      let bestIdx = -1, bestArea = 0
      for (let i = 0; i < builtSpaces.length; i++) {
        const entry = builtSpaces[i]
        if (!entry.space.bounding_box) continue
        const t = entry.transform
        const area = overlapArea(
          newBB, bX, bZ, bYRot,
          entry.space.bounding_box,
          t?.position.x ?? 0, t?.position.z ?? 0, t ? extractYaw(t) : 0
        )
        if (area > bestArea) { bestArea = area; bestIdx = i }
      }
      if (bestIdx >= 0) return bestIdx
    }

    // Fallback: nearest centroid in world space
    const centroid = (verts: [number,number][], tx: number, tz: number, yaw: number): [number,number] => {
      const cx = verts.reduce((s,v) => s+v[0], 0) / verts.length
      const cz = verts.reduce((s,v) => s+v[1], 0) / verts.length
      const cos = Math.cos(yaw), sin = Math.sin(yaw)
      return [cos*cx + sin*cz + tx, -sin*cx + cos*cz + tz]
    }
    const newVerts = newBB?.vertices_2d ?? [[bX, bZ]]
    const [nx, nz] = centroid(newVerts as [number,number][], bX, bZ, bYRot)
    let bestIdx = 0, minDist = Infinity
    for (let i = 0; i < builtSpaces.length; i++) {
      const entry = builtSpaces[i]
      const t = entry.transform
      const verts = entry.space.bounding_box?.vertices_2d ?? [[0, 0]]
      const [bx, bz] = centroid(verts as [number,number][], t?.position.x ?? 0, t?.position.z ?? 0, t ? extractYaw(t) : 0)
      const dist = Math.hypot(nx - bx, nz - bz)
      if (dist < minDist) { minDist = dist; bestIdx = i }

    }
    return bestIdx
  })

  let currentSpaceGlbUrl: string | null = $state(null)
  $effect(() => {
    currentSpaceGlbUrl = null
    if (currentSpace?.glb_path) {
      getSpaceGlbUrl(currentSpace.glb_path).then(url => currentSpaceGlbUrl = url).catch(() => {})
    }
  })

  function addSpace(spaceId: string): void {
    if (!orderedSpaceIds.includes(spaceId)) orderedSpaceIds = [...orderedSpaceIds, spaceId]
  }

  function removeSpace(spaceId: string): void {
    const idx = orderedSpaceIds.indexOf(spaceId)
    if (idx < frozenCount) return
    orderedSpaceIds = orderedSpaceIds.filter(id => id !== spaceId)
  }

  async function loadForAddSpace(existing: Building & { spaces: Space[] }): Promise<void> {
    const sorted = [...existing.spaces]
      .filter(s => s.glb_path)
      .sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
    buildingName = existing.name ?? ''
    orderedSpaceIds = sorted.map(s => s.id)
    activeBuildingId = existing.id
    frozenCount = sorted.length
    frozenSpaces = await Promise.all(
      sorted.map(async s => ({
        space: s,
        glbUrl: await getSpaceGlbUrl(s.glb_path!),
        transform: s.offset_transformation as RigidTransform | null,
      }))
    )
  }

  async function startBuilding(): Promise<void> {
    const hasNewSpaces = addSpaceId ? orderedSpaceIds.length > frozenCount : orderedSpaceIds.length >= 2
    if (!buildingName.trim() || !hasNewSpaces) return
    try {
      if (addSpaceId) {
        const newSpaceIds = orderedSpaceIds.slice(frozenCount)
        await prepareAddSpace(addSpaceId, frozenCount, newSpaceIds)
        activeBuildingId = addSpaceId
        builtSpaces = [...frozenSpaces]
      } else if (restitchId) {
        await resetBuildingForRestitch(restitchId, buildingName, orderedSpaceIds)
        activeBuildingId = restitchId
        builtSpaces = []
      } else {
        activeBuildingId = await createDraftBuilding(buildingName, orderedSpaceIds)
        builtSpaces = []
      }
    } catch (e) {
      error = (e as Error).message
      return
    }
    currentSpaceId = null
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
    phase = 'align'
  }

  async function resumeBuilding(draft: Building & { spaces: Space[] }): Promise<void> {
    const sorted = [...draft.spaces].sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
    orderedSpaceIds = sorted.map(s => s.id)
    buildingName = draft.name ?? ''
    activeBuildingId = draft.id
    // A placed scan is one with a stored transform (the reference gets an identity transform).
    builtSpaces = await Promise.all(
      sorted
        .filter(s => s.offset_transformation !== null)
        .map(async s => ({ space: s, glbUrl: await getSpaceGlbUrl(s.glb_path!), transform: s.offset_transformation }))
    )
    currentSpaceId = null
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
    phase = 'align'
  }

  function rigidTransform(): RigidTransform {
    const half = bYRot / 2
    return {
      position: { x: bX, y: bY, z: bZ },
      quaternion: { x: 0, y: Math.sin(half), z: 0, w: Math.cos(half) },
    }
  }

  async function refine(): Promise<void> {
    if (!currentSpace || refining) return
    const refIdx = bestReferenceIndex ?? builtSpaces.length - 1
    const spaceAId = builtSpaces[refIdx].space.id
    refining = true
    error = null
    alignResult = null
    try {
      const token = get(session)?.access_token ?? ''
      const res = await fetch(`${MONO_URL}/stitch/refine`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body: JSON.stringify({
          space_a_id: spaceAId,
          space_b_id: currentSpace.id,
          initial_transform: rigidTransform(),
        }),
      })
      if (!res.ok) throw new Error(await res.text())
      const data = await res.json()
      alignResult = { fitness: data.fitness, inlier_rmse: data.inlier_rmse }
      const t = data.transform as RigidTransform
      bX = t.position.x
      bY = t.position.y
      bZ = t.position.z
      const q = t.quaternion
      bYDeg = (Math.atan2(2 * (q.w * q.y + q.x * q.z), 1 - 2 * (q.y * q.y + q.z * q.z)) * 180) / Math.PI
    } catch (e) {
      error = (e as Error).message
    } finally {
      refining = false
    }
  }

  // User picks which scan to align next. The first pick (no reference yet)
  // anchors the origin; later picks open the alignment gizmo.
  function pickNext(space: Space): void {
    if (needsReference) placeReference(space)
    else beginAlign(space.id)
  }

  function beginAlign(spaceId: string): void {
    currentSpaceId = spaceId
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
  }

  const IDENTITY: RigidTransform = { position: { x: 0, y: 0, z: 0 }, quaternion: { x: 0, y: 0, z: 0, w: 1 } }

  async function placeReference(space: Space): Promise<void> {
    if (!activeBuildingId) return
    try {
      await updateBuildingSpaceTransform(activeBuildingId, space.id, IDENTITY)
    } catch (e) {
      error = (e as Error).message
      return
    }
    builtSpaces = [...builtSpaces, { space, glbUrl: await getSpaceGlbUrl(space.glb_path!), transform: IDENTITY }]
  }

  function cancelAlign(): void {
    currentSpaceId = null
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
  }

  // Mark a placed scan as unplaced: drop its stored transform so it returns to the pool.
  async function unplace(spaceId: string): Promise<void> {
    if (!activeBuildingId) return
    try {
      await updateBuildingSpaceTransform(activeBuildingId, spaceId, null)
    } catch (e) {
      error = (e as Error).message
      return
    }
    builtSpaces = builtSpaces.filter(e => e.space.id !== spaceId)
    if (currentSpaceId === spaceId) cancelAlign()
  }

  async function confirmAlign(): Promise<void> {
    if (!currentSpace || !activeBuildingId) return
    const transform = rigidTransform()
    try {
      await updateBuildingSpaceTransform(activeBuildingId, currentSpace.id, transform)
    } catch (e) {
      error = (e as Error).message
      return
    }
    builtSpaces = [...builtSpaces, {
      space: currentSpace,
      glbUrl: currentSpaceGlbUrl!,
      transform,
    }]
    currentSpaceId = null
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
  }

  function resetBuilding(): void {
    phase = 'setup'
    builtSpaces = []
    currentSpaceId = null
    if (addSpaceId) {
      orderedSpaceIds = frozenSpaces.map(e => e.space.id)
      activeBuildingId = addSpaceId
    } else {
      activeBuildingId = null
      orderedSpaceIds = []
      buildingName = ''
    }
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
  }

  const SPACE_COLORS = [0xff6644, 0x44aaff, 0x44ff88, 0xffcc00, 0xff44cc, 0x00ffff]

  let downloading = $state(false)

  async function downloadMergedGlb(): Promise<void> {
    if (downloading || builtSpaces.length === 0) return
    downloading = true
    try {
      await mergeAndDownloadGlb(builtSpaces.map(e => ({ glbUrl: e.glbUrl, transform: e.transform })), buildingName)
    } catch (e) {
      error = (e as Error).message
    } finally {
      downloading = false
    }
  }

  async function saveBuilding(): Promise<void> {
    if (saving || !activeBuildingId) return
    saving = true
    try {
      await finalizeDraftBuilding(activeBuildingId)
      goto('/buildings')
    } catch (e) {
      error = (e as Error).message
    } finally {
      saving = false
    }
  }
</script>

<DetailLayout title={buildingName?.trim() || 'New Building'} onback={() => goto('/buildings')}>
  {#snippet badge()}<span class="pill draft">Draft</span>{/snippet}
  <Sidebar>
    {#if phase === 'setup'}
      <section>
        <label class="section-label">Building name</label>
        <input type="text" bind:value={buildingName} placeholder="e.g. Top Floor" />
      </section>

      <section class="spaces-pool">
        <label class="section-label">Add spaces</label>
        {#if unselectedSpaces.length === 0}
          <p class="hint">All spaces added.</p>
        {:else}
          <ul class="pool-list">
            {#each unselectedSpaces as s (s.id)}
              <li class="pool-item" onclick={() => addSpace(s.id)}>
                <span>{s.name || s.id}</span>
                <span class="add-icon">+</span>
              </li>
            {/each}
          </ul>
        {/if}
      </section>

      {#if orderedSpaceIds.length > 0}
        <section class="order-section">
          <label class="section-label">Selected scans <span class="muted">({orderedSpaceIds.length})</span></label>
          <ul class="order-list">
            {#each orderedSpaceIds as id, i (id)}
              {@const s = allSpaces.find(sp => sp.id === id)}
              {@const frozen = i < frozenCount}
              <li class="order-item" class:frozen-item={frozen}>
                <div class="order-left">
                  {#if frozen}<span class="done-badge">✓</span>{/if}
                  <span class="order-name">{s?.name || id}</span>
                </div>
                {#if !frozen}
                  <button class="remove-btn" onclick={() => removeSpace(id)}>×</button>
                {/if}
              </li>
            {/each}
          </ul>
        </section>
      {/if}

      <section>
        <Button
          variant="primary" style="width:100%"
          disabled={!buildingName.trim() || (addSpaceId ? orderedSpaceIds.length <= frozenCount : orderedSpaceIds.length < 2)}
          onclick={startBuilding}
        >
          {addSpaceId ? 'Start adding →' : 'Start stitching →'}
        </Button>
      </section>

    {:else if phase === 'align'}
      <!-- Placed scans -->
      <section class="order-section">
        <label class="section-label">Placed <span class="muted">({builtSpaces.length}/{orderedSpaceIds.length})</span></label>
        {#if builtSpaces.length === 0}
          <p class="hint">None yet.</p>
        {:else}
          <ul class="order-list">
            {#each builtSpaces as e, i (e.space.id)}
              {@const frozen = i < frozenCount}
              <li class="order-item" class:frozen-item={frozen}>
                <div class="order-left">
                  <span class="done-badge">✓</span>
                  <span class="order-name">{e.space.name || e.space.id}</span>
                </div>
                {#if !frozen}
                  <button class="remove-btn" title="Mark unplaced" onclick={() => unplace(e.space.id)}>Unplace</button>
                {/if}
              </li>
            {/each}
          </ul>
        {/if}
      </section>

      <!-- Unplaced scans -->
      <section class="spaces-pool">
        <label class="section-label">Unplaced</label>
        {#if remainingSpaces.length === 0}
          <p class="hint">{currentSpaceId ? 'Aligning the last scan…' : 'All scans placed.'}</p>
        {:else}
          <ul class="pool-list">
            {#each remainingSpaces as s (s.id)}
              <li class="pool-item" onclick={() => pickNext(s)}>
                <span>{s.name || s.id}</span>
                <span class="add-icon">{needsReference ? '★' : '→'}</span>
              </li>
            {/each}
          </ul>
        {/if}
        {#if needsReference && !currentSpaceId}
          <p class="hint">★ The first scan you pick anchors the origin.</p>
        {/if}
      </section>

      <!-- Alignment controls for the scan being positioned -->
      {#if currentSpaceId}
        <section class="aligning-block">
          <label class="section-label">Aligning</label>

          <div class="mode-row">
            <button class="mode-btn" class:active={mode === 'translate'} onclick={() => mode = 'translate'}>Move</button>
            <button class="mode-btn" class:active={mode === 'rotate'} onclick={() => mode = 'rotate'}>Rotate</button>
          </div>

          <Button variant="primary" style="width:100%" onclick={refine} disabled={refining}>
            {refining ? 'Snapping…' : 'Snap align'}
          </Button>

          {#if alignResult}
            <div class="result" class:good={alignResult.fitness > 0.3} class:bad={alignResult.fitness <= 0.1}>
              <div class="stat"><span>Fitness</span><strong>{alignResult.fitness.toFixed(3)}</strong></div>
              <div class="stat"><span>RMSE</span><strong>{alignResult.inlier_rmse.toFixed(4)}m</strong></div>
              {#if alignResult.fitness < 0.1}
                <p class="warn">Low fitness - rough alignment may be off</p>
              {/if}
            </div>
          {/if}

          <div class="nav-row">
            <Button onclick={cancelAlign}>Cancel</Button>
            <Button variant="primary" onclick={confirmAlign}>Place →</Button>
          </div>
        </section>
      {/if}

      <section>
        <Button style="width:100%" onclick={() => showBoundingBoxes = !showBoundingBoxes}>
          {showBoundingBoxes ? 'Hide boxes' : 'Show boxes'}
        </Button>
      </section>

      <!-- Save once everything is placed -->
      {#if allPlaced}
        <section>
          <p class="hint placed">All {builtSpaces.length} scans placed — ready to save "{buildingName}".</p>
          <Button variant="primary" style="width:100%;margin-bottom:6px" onclick={downloadMergedGlb} disabled={downloading}>
            {downloading ? 'Exporting…' : '↓ Download GLB'}
          </Button>
          <Button variant="primary" style="width:100%" onclick={saveBuilding} disabled={saving}>
            {saving ? 'Saving…' : 'Save building'}
          </Button>
        </section>
      {/if}

      <section>
        <Button style="width:100%" onclick={resetBuilding}>Cancel building</Button>
      </section>
    {/if}

    {#if error}
      <p class="err">{error}</p>
    {/if}
  </Sidebar>

  <div class="scene-wrap">
    {#if phase === 'align' && currentSpaceGlbUrl}
      <Canvas rendererParameters={{ preserveDrawingBuffer: true, alpha: false }}>
        <BuildingStitchScene
          builtSpaces={builtSpacesForScene}
          newSpaceUrl={currentSpaceGlbUrl}
          newX={bX}
          newY={bY}
          newZ={bZ}
          newYRot={bYRot}
          newBoundingBox={currentSpace?.bounding_box ?? null}
          {mode}
          {showBoundingBoxes}
          {bestReferenceIndex}
          {exportTrigger}
          onexportblob={handleExportBlob}
          ontransform={(x, y, z, yRot) => {
            bX = x
            bY = y
            bZ = z
            bYDeg = (yRot * 180) / Math.PI
          }}
        />
      </Canvas>
      <button class="export-btn" onclick={() => exportTrigger++}>Export PNG</button>
    {:else if phase === 'align' && !currentSpaceId && builtSpaces.length > 0}
      <Canvas rendererParameters={{ preserveDrawingBuffer: true, alpha: false }}>
        <NavigateSceneInner spaces={builtSpacesForScene} {showBoundingBoxes} {exportTrigger} exportScale={2} onexportblob={handleExportBlob} />
      </Canvas>
      <button class="export-btn" onclick={() => exportTrigger++}>Export PNG</button>
    {:else}
      <div class="placeholder">
        {phase === 'setup'
          ? 'Configure your building to begin'
          : (phase === 'align' && !currentSpaceId)
            ? 'Pick the reference scan to begin'
            : 'Loading scan…'}
      </div>
    {/if}
  </div>
</DetailLayout>

<style>
  .scene-wrap {
    position: relative;
    flex: 1;
    height: 100%;
    overflow: hidden;
  }

  .export-btn {
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
  .export-btn:hover { background: rgba(0,0,0,0.6); }


  .nav-row { display: flex; gap: 6px; margin-top: 8px; }
  .nav-row :global(button) { flex: 1; }

  .aligning-block { border-top: 1px solid var(--border); gap: 10px; }

  .muted { text-transform: none; letter-spacing: 0; font-size: 10px; }
  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }
  .hint.placed { color: var(--text); }

  .spaces-pool { overflow: hidden; }
  .pool-list { list-style: none; display: flex; flex-direction: column; gap: 2px; overflow-y: auto; }
  .pool-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 4px;
    border-radius: 4px;
    cursor: pointer;
    font-size: 13px;
    transition: background 0.1s;
  }
  .pool-item:hover { background: #202020; }
  .add-icon { color: var(--accent); font-size: 16px; line-height: 1; }

  .order-section { overflow: hidden; }
  .order-list { list-style: none; display: flex; flex-direction: column; gap: 4px; }
  .order-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 5px 0;
    font-size: 13px;
  }
  .order-left { display: flex; align-items: center; gap: 6px; flex: 1; min-width: 0; }
  .order-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .done-badge {
    font-size: 10px;
    padding: 1px 5px;
    border-radius: 3px;
    background: transparent;
    color: var(--text-muted);
    flex-shrink: 0;
  }
  .frozen-item .order-name { color: var(--text-muted); }
  .remove-btn {
    padding: 1px 6px;
    font-size: 13px;
    color: var(--text-muted);
    border-color: transparent;
    background: transparent;
    flex-shrink: 0;
  }
  .remove-btn:hover { color: var(--danger); }

  .mode-row { display: flex; gap: 6px; }
  .mode-btn {
    flex: 1;
    padding: 5px 0;
    font-size: 12px;
    border-radius: 5px;
    border: 1px solid var(--border);
    background: transparent;
    color: var(--text-muted);
    cursor: pointer;
    transition: all 0.15s;
  }
  .mode-btn.active { border-color: var(--accent); color: var(--accent); background: var(--accent-dim); }

  .muted { font-size: 11px; color: var(--text-muted); }

  .result { border-top: 1px solid var(--border); padding-top: 8px; }
  .stat { display: flex; justify-content: space-between; font-size: 12px; padding: 2px 0; }
  .stat span { color: var(--text-muted); }
  .warn { font-size: 11px; color: var(--pending); margin-top: 4px; }

  .err { padding: 8px 16px; font-size: 12px; color: var(--danger); }

  .pill {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 2px 8px;
    border-radius: 6px;
    flex-shrink: 0;
  }
  .pill.draft { background: var(--pending); color: #000; }
</style>
