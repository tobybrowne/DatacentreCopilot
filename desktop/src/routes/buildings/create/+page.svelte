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
  import Button from '$lib/Button.svelte'
  import { downloadMergedGlb as mergeAndDownloadGlb } from '$lib/glbMerge'
  import { overlapArea, extractYaw } from '$lib/polygon2d'
  import type { Building, RigidTransform, Space } from '$lib/types'

  const MONO_URL = import.meta.env.VITE_MONO_URL as string
  const draftId = $page.url.searchParams.get('draft') ?? undefined
  const restitchId = $page.url.searchParams.get('restitch') ?? undefined
  const addSpaceId = $page.url.searchParams.get('addspace') ?? undefined

  type Phase = 'setup' | 'align' | 'complete'

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
  let currentIdx = $state(1)
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

  let glbSpaces = $derived(allSpaces.filter(s => s.glb_path))
  let unselectedSpaces = $derived(glbSpaces.filter(s => !orderedSpaceIds.includes(s.id)))
  let currentSpace = $derived(orderedSpaceIds[currentIdx] ? allSpaces.find(s => s.id === orderedSpaceIds[currentIdx]) ?? null : null)
  let builtSpacesForScene = $derived(builtSpaces.map(e => ({ url: e.glbUrl, transform: e.transform, boundingBox: e.space.bounding_box })))

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

  function moveUp(i: number): void {
    if (i <= frozenCount) return
    const ids = [...orderedSpaceIds]
    ;[ids[i-1], ids[i]] = [ids[i], ids[i-1]]
    orderedSpaceIds = ids
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
        currentIdx = frozenCount
      } else if (restitchId) {
        await resetBuildingForRestitch(restitchId, buildingName, orderedSpaceIds)
        activeBuildingId = restitchId
        const refSpace = allSpaces.find(s => s.id === orderedSpaceIds[0])!
        builtSpaces = [{ space: refSpace, glbUrl: await getSpaceGlbUrl(refSpace.glb_path!), transform: null }]
        currentIdx = 1
      } else {
        activeBuildingId = await createDraftBuilding(buildingName, orderedSpaceIds)
        const refSpace = allSpaces.find(s => s.id === orderedSpaceIds[0])!
        builtSpaces = [{ space: refSpace, glbUrl: await getSpaceGlbUrl(refSpace.glb_path!), transform: null }]
        currentIdx = 1
      }
    } catch (e) {
      error = (e as Error).message
      return
    }
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
    phase = 'align'
  }

  async function resumeBuilding(draft: Building & { spaces: Space[] }): Promise<void> {
    const sorted = [...draft.spaces].sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
    orderedSpaceIds = sorted.map(s => s.id)
    buildingName = draft.name ?? ''
    activeBuildingId = draft.id
    builtSpaces = await Promise.all(
      sorted
        .filter(s => s.building_index === 0 || s.offset_transformation !== null)
        .map(async s => ({ space: s, glbUrl: await getSpaceGlbUrl(s.glb_path!), transform: s.offset_transformation }))
    )
    currentIdx = builtSpaces.length
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
    phase = currentIdx >= orderedSpaceIds.length ? 'complete' : 'align'
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

  function goBack(): void {
    if (currentIdx <= 1) return
    const prev = builtSpaces[builtSpaces.length - 1]
    builtSpaces = builtSpaces.slice(0, -1)
    currentIdx--
    const t = prev.transform
    if (t) {
      bX = t.position?.x ?? 0
      bY = t.position?.y ?? 0
      bZ = t.position?.z ?? 0
      const q = t.quaternion
      bYDeg = q
        ? (Math.atan2(2 * (q.w * q.y + q.x * q.z), 1 - 2 * (q.y * q.y + q.z * q.z)) * 180) / Math.PI
        : 0
    } else {
      bX = 0; bY = 0; bZ = 0; bYDeg = 0
    }
    alignResult = null
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
    currentIdx++
    bX = 0; bY = 0; bZ = 0; bYDeg = 0
    alignResult = null
    phase = currentIdx >= orderedSpaceIds.length ? 'complete' : 'align'
  }

  function resetBuilding(): void {
    phase = 'setup'
    builtSpaces = []
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

<div class="layout">
  <Sidebar title="Building Manager" onback={() => goto('/buildings')}>
    {#if phase === 'setup'}
      <section>
        <label class="section-label">Building name</label>
        <input type="text" bind:value={buildingName} placeholder="e.g. Top Floor" />
      </section>

      <section class="spaces-pool">
        <label class="section-label">Add spaces <span class="muted">(click to add in order)</span></label>
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
          <label class="section-label">Stitch order</label>
          <ul class="order-list">
            {#each orderedSpaceIds as id, i (id)}
              {@const s = allSpaces.find(sp => sp.id === id)}
              {@const frozen = i < frozenCount}
              <li class="order-item" class:frozen-item={frozen}>
                <div class="order-left">
                  {#if i === 0}
                    <span class="ref-badge">ref</span>
                  {:else if frozen}
                    <span class="done-badge">✓</span>
                  {:else}
                    <button class="up-btn" onclick={() => moveUp(i)} disabled={i <= frozenCount}>↑</button>
                  {/if}
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
      <section>
        <label class="section-label">
          Aligning {currentIdx}/{orderedSpaceIds.length - 1}
        </label>
        <p class="hint space-name">{currentSpace?.name || ''}</p>
      </section>

      <section>
        <label class="section-label">Gizmo mode</label>
        <div class="mode-row">
          <button class="mode-btn" class:active={mode === 'translate'} onclick={() => mode = 'translate'}>Move</button>
          <button class="mode-btn" class:active={mode === 'rotate'} onclick={() => mode = 'rotate'}>Rotate</button>
        </div>
        <p class="hint">Drag the gizmo axes · Right-drag to orbit</p>
      </section>

      <section>
        <label class="section-label">Position</label>
        <div class="pos-row">
          <span class="muted">X {bX.toFixed(2)}  Y {bY.toFixed(2)}  Z {bZ.toFixed(2)}  R {bYDeg.toFixed(1)}°</span>
          <Button size="sm" onclick={() => { bX = 0; bY = 0; bZ = 0; bYDeg = 0; alignResult = null }}>Reset</Button>
        </div>
      </section>

      <section>
        <Button variant="primary" style="width:100%" onclick={refine} disabled={refining}>
          {refining ? 'Snapping…' : 'Snap align'}
        </Button>
      </section>

      {#if alignResult}
        <section class="result" class:good={alignResult.fitness > 0.3} class:bad={alignResult.fitness <= 0.1}>
          <label class="section-label">ICP Result</label>
          <div class="stat"><span>Fitness</span><strong>{alignResult.fitness.toFixed(3)}</strong></div>
          <div class="stat"><span>RMSE</span><strong>{alignResult.inlier_rmse.toFixed(4)}m</strong></div>
          {#if alignResult.fitness < 0.1}
            <p class="warn">Low fitness - rough alignment may be off</p>
          {/if}
        </section>
      {/if}

      <section>
        <Button style="width:100%" onclick={() => showBoundingBoxes = !showBoundingBoxes}>
          {showBoundingBoxes ? 'Hide boxes' : 'Show boxes'}
        </Button>
      </section>

      <section class="nav-section">
        <div class="nav-row">
          <Button disabled={currentIdx <= frozenCount} onclick={goBack}>← Back</Button>
          <Button variant="primary" onclick={confirmAlign}>
            {currentIdx < orderedSpaceIds.length - 1 ? 'Next →' : 'Finish →'}
          </Button>
        </div>
        <Button style="width:100%" onclick={resetBuilding}>Cancel</Button>
      </section>

    {:else if phase === 'complete'}
      <section>
        <label class="section-label">All scans stitched</label>
        <p class="hint placed">{builtSpaces.length} spaces ready to save as "{buildingName}".</p>
      </section>

      <section>
        <Button variant="primary" style="width:100%" onclick={downloadMergedGlb} disabled={downloading}>
          {downloading ? 'Exporting…' : '↓ Download GLB'}
        </Button>
      </section>
      <section class="row-section">
        <Button onclick={resetBuilding}>Reset</Button>
        <Button variant="primary" onclick={saveBuilding} disabled={saving}>
          {saving ? 'Saving…' : 'Save building'}
        </Button>
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
    {:else if phase === 'complete'}
      <Canvas rendererParameters={{ preserveDrawingBuffer: true, alpha: false }}>
        <NavigateSceneInner spaces={builtSpacesForScene} {showBoundingBoxes} {exportTrigger} exportScale={2} onexportblob={handleExportBlob} />
      </Canvas>
      <button class="export-btn" onclick={() => exportTrigger++}>Export PNG</button>
    {:else}
      <div class="placeholder">
        {phase === 'setup' ? 'Configure your building to begin' : 'Loading scan…'}
      </div>
    {/if}
  </div>
</div>

<style>
  .layout {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .scene-wrap {
    position: relative;
    flex: 1;
    height: 100vh;
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


  .row-section { flex-direction: row; }
  .row-section button { flex: 1; }
  .nav-section { gap: 6px; }
  .nav-row { display: flex; gap: 6px; }
  .nav-row :global(button) { flex: 1; }

  .muted { text-transform: none; letter-spacing: 0; font-size: 10px; }
  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }
  .hint.placed { color: var(--text); }
  .hint.space-name { font-weight: 600; color: var(--accent); font-size: 13px; }

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

  .ref-badge {
    font-size: 9px;
    padding: 1px 5px;
    border-radius: 3px;
    background: var(--accent-dim);
    color: var(--accent);
    text-transform: uppercase;
    letter-spacing: 0.05em;
    flex-shrink: 0;
  }
  .done-badge {
    font-size: 10px;
    padding: 1px 5px;
    border-radius: 3px;
    background: transparent;
    color: var(--text-muted);
    flex-shrink: 0;
  }
  .frozen-item .order-name { color: var(--text-muted); }
  .up-btn { padding: 1px 5px; font-size: 11px; border-radius: 3px; flex-shrink: 0; }
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

  .pos-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    margin-bottom: 4px;
  }
  .muted { font-size: 11px; color: var(--text-muted); font-family: monospace; }

  .result { border-top: 1px solid var(--border); }
  .result.good .section-label { color: #88ff88; }
  .result.bad .section-label { color: var(--danger); }
  .stat { display: flex; justify-content: space-between; font-size: 12px; padding: 2px 0; }
  .stat span { color: var(--text-muted); }
  .warn { font-size: 11px; color: var(--pending); margin-top: 4px; }

  .err { padding: 8px 16px; font-size: 12px; color: var(--danger); }
</style>
