<script lang="ts">
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { onMount } from 'svelte'
  import { fetchSpaces, fetchBuildingById, getSpaceGlbUrl, createDraftBuilding, updateBuildingSpaceTransform, finalizeDraftBuilding, upsertCentroidAnchor } from '$lib/supabase'
  import { computeTransform, posToV3 } from '$lib/stitching'
  import { computeCentroids } from '$lib/centroid'
  import Scene from '$lib/Scene.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import type { Building, Position, RigidTransform, Space } from '$lib/types'
  import { downloadMergedGlb as mergeAndDownloadGlb } from '$lib/glbMerge'

  const draftId = $page.url.searchParams.get('draft') ?? undefined

  type Phase = 'setup' | 'pickSource' | 'pickTarget' | 'preview' | 'complete'

  interface SpaceEntry {
    space: Space
    glbUrl: string
    transform: RigidTransform | null
  }

  let allSpaces: Space[] = $state([])
  let buildingName = $state('')
  let orderedSpaceIds: string[] = $state([])

  let phase = $state<Phase>('setup')
  let builtSpaces: SpaceEntry[] = $state([])
  let currentIdx = $state(1)
  let activeBuildingId: string | null = null

  let srcPoints: Position[] = $state([])
  let tgtPoints: Position[] = $state([])
  let pointPlaced = $state(false)
  let currentTransform: RigidTransform | null = $state(null)

  let saving = $state(false)
  let error: string | null = $state(null)

  onMount(async () => {
    try {
      allSpaces = await fetchSpaces()
      if (draftId) {
        const draft = await fetchBuildingById(draftId)
        await resumeBuilding(draft)
      }
    } catch (e) { error = (e as Error).message }
  })

  let glbSpaces = $derived(allSpaces.filter(s => s.glb_path))
  let unselectedSpaces = $derived(glbSpaces.filter(s => !orderedSpaceIds.includes(s.id)))
  let pickingSource = $derived(phase === 'pickSource')
  let pairsDone = $derived(tgtPoints.length)
  let currentSpace = $derived(orderedSpaceIds[currentIdx] ? allSpaces.find(s => s.id === orderedSpaceIds[currentIdx]) ?? null : null)
  let currentSourceGlbUrl: string | null = $state(null)
  $effect(() => {
    if (currentSpace?.glb_path) {
      getSpaceGlbUrl(currentSpace.glb_path).then(url => currentSourceGlbUrl = url).catch(() => currentSourceGlbUrl = null)
    } else {
      currentSourceGlbUrl = null
    }
  })

  let lastBuilt = $derived(builtSpaces[builtSpaces.length - 1])
  let mergedSpaces = $derived(phase === 'complete'
    ? builtSpaces.map(e => ({ url: e.glbUrl, transform: e.transform }))
    : lastBuilt ? [{ url: lastBuilt.glbUrl, transform: lastBuilt.transform }] : [])

  let scenePhase = $derived((phase === 'setup' || phase === 'complete') ? 'idle' : phase as any)

  function addSpace(spaceId: string): void {
    if (!orderedSpaceIds.includes(spaceId)) orderedSpaceIds = [...orderedSpaceIds, spaceId]
  }

  function removeSpace(spaceId: string): void {
    orderedSpaceIds = orderedSpaceIds.filter(id => id !== spaceId)
  }

  function moveUp(i: number): void {
    if (i === 0) return
    const ids = [...orderedSpaceIds]
    ;[ids[i-1], ids[i]] = [ids[i], ids[i-1]]
    orderedSpaceIds = ids
  }

  async function startBuilding(): Promise<void> {
    if (!buildingName.trim() || orderedSpaceIds.length < 2) return
    try {
      activeBuildingId = await createDraftBuilding(buildingName, orderedSpaceIds)
    } catch (e) {
      error = (e as Error).message
      return
    }
    const refSpace = allSpaces.find(s => s.id === orderedSpaceIds[0])!
    builtSpaces = [{ space: refSpace, glbUrl: await getSpaceGlbUrl(refSpace.glb_path!), transform: null }]
    currentIdx = 1
    srcPoints = []
    tgtPoints = []
    pointPlaced = false
    currentTransform = null
    phase = 'pickSource'
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
    srcPoints = []
    tgtPoints = []
    pointPlaced = false
    currentTransform = null
    phase = currentIdx >= orderedSpaceIds.length ? 'complete' : 'pickSource'
  }

  function handleMeshClick(detail: { position: Position; spaceIndex: number | null }): void {
    const position = detail.position
    if (phase === 'pickSource' && !pointPlaced) {
      srcPoints = [...srcPoints, position]
      pointPlaced = true
    } else if (phase === 'pickTarget' && !pointPlaced) {
      tgtPoints = [...tgtPoints, position]
      pointPlaced = true
    }
  }

  function continueStitch(): void {
    if (!pointPlaced) return
    pointPlaced = false
    if (phase === 'pickSource') {
      phase = 'pickTarget'
    } else if (phase === 'pickTarget') {
      if (tgtPoints.length === 3) {
        currentTransform = computeTransform(srcPoints.map(posToV3), tgtPoints.map(posToV3))
        phase = 'preview'
      } else {
        phase = 'pickSource'
      }
    }
  }

  function undoStitch(): void {
    if (pointPlaced) {
      if (phase === 'pickSource') srcPoints = srcPoints.slice(0, -1)
      else if (phase === 'pickTarget') tgtPoints = tgtPoints.slice(0, -1)
      pointPlaced = false
    } else {
      if (phase === 'pickSource' && tgtPoints.length > 0) {
        tgtPoints = tgtPoints.slice(0, -1)
        phase = 'pickTarget'
        pointPlaced = false
      } else if (phase === 'pickTarget' && srcPoints.length > 0) {
        srcPoints = srcPoints.slice(0, -1)
        phase = 'pickSource'
        pointPlaced = false
      }
    }
  }

  async function confirmStitch(): Promise<void> {
    if (!currentTransform || !currentSpace || !activeBuildingId) return
    try {
      await updateBuildingSpaceTransform(activeBuildingId, currentSpace.id, currentTransform)
    } catch (e) {
      error = (e as Error).message
      return
    }
    builtSpaces = [...builtSpaces, {
      space: currentSpace,
      glbUrl: currentSourceGlbUrl!,
      transform: currentTransform,
    }]
    currentIdx++
    srcPoints = []
    tgtPoints = []
    pointPlaced = false
    currentTransform = null
    if (currentIdx >= orderedSpaceIds.length) {
      phase = 'complete'
    } else {
      phase = 'pickSource'
    }
  }

  function resetBuilding(): void {
    phase = 'setup'
    builtSpaces = []
    srcPoints = []
    tgtPoints = []
    pointPlaced = false
    currentTransform = null
    activeBuildingId = null
    orderedSpaceIds = []
    buildingName = ''
  }

  let recomputingCentroids = $state(false)
  let voxelSize = $state(0.5)
  let overlapPenalty = $state(1)
  let pointClouds: Array<{ points: import('$lib/types').Position[]; color: number }> = $state([])

  const SPACE_COLORS = [0xff6644, 0x44aaff, 0x44ff88, 0xffcc00, 0xff44cc, 0x00ffff]

  async function recomputeCentroids(): Promise<void> {
    if (recomputingCentroids || builtSpaces.length === 0) return
    recomputingCentroids = true
    pointClouds = []
    try {
      const entries = await Promise.all(
        builtSpaces
          .filter(e => e.space.glb_path)
          .map(async e => ({ space: e.space, glbUrl: await getSpaceGlbUrl(e.space.glb_path!) }))
      )

      const { centroids, voronoiPoints } = await computeCentroids(entries, voxelSize, overlapPenalty)

      pointClouds = [...voronoiPoints.entries()].map(([spaceId, points], i) => ({
        points,
        color: SPACE_COLORS[i % SPACE_COLORS.length],
      }))

      await Promise.all([...centroids.entries()].map(([spaceId, pos]) =>
        upsertCentroidAnchor(spaceId, pos)
      ))
    } catch (e) {
      error = (e as Error).message
    } finally {
      recomputingCentroids = false
    }
  }

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
      await recomputeCentroids()
      goto('/buildings')
    } catch (e) {
      error = (e as Error).message
    } finally {
      saving = false
    }
  }
</script>

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
            <li class="order-item">
              <div class="order-left">
                {#if i === 0}
                  <span class="ref-badge">ref</span>
                {:else}
                  <button class="up-btn" onclick={() => moveUp(i)} disabled={i === 1}>↑</button>
                {/if}
                <span class="order-name">{s?.name || id}</span>
              </div>
              <button class="remove-btn" onclick={() => removeSpace(id)}>×</button>
            </li>
          {/each}
        </ul>
      </section>
    {/if}

    <section>
      <button
        class="primary" style="width:100%"
        disabled={!buildingName.trim() || orderedSpaceIds.length < 2}
        onclick={startBuilding}
      >
        Start stitching →
      </button>
    </section>

  {:else if phase === 'pickSource' || phase === 'pickTarget'}
    <section>
      <label class="section-label">
        Stitching {currentIdx}/{orderedSpaceIds.length - 1}
      </label>
      <p class="hint space-name">{currentSpace?.name || ''}</p>
    </section>

    <section>
      <label class="section-label">Pairs</label>
      <div class="pairs-grid">
        {#each [0, 1, 2] as i}
          <span class="pair-dot src" class:filled={i < srcPoints.length}></span>
          <span class="pair-dot tgt" class:filled={i < tgtPoints.length}></span>
        {/each}
      </div>
    </section>

    <section>
      {#if pointPlaced}
        <p class="hint placed">
          Point on <strong class:src-label={pickingSource} class:tgt-label={!pickingSource}>
            {pickingSource ? 'new scan' : 'merged model'}
          </strong> placed.
        </p>
        <button class="primary" style="width:100%" onclick={continueStitch}>Continue →</button>
      {:else}
        <p class="hint">
          Pair {pairsDone + 1}/3 — double-click a point on the
          <strong class:src-label={pickingSource} class:tgt-label={!pickingSource}>
            {pickingSource ? 'new scan' : 'merged model'}
          </strong>
        </p>
      {/if}
    </section>

    <section class="row-section">
      <button onclick={undoStitch} disabled={srcPoints.length === 0 && tgtPoints.length === 0}>Undo</button>
      <button onclick={resetBuilding}>Cancel</button>
    </section>

  {:else if phase === 'preview'}
    <section>
      <label class="section-label">Preview — {currentIdx}/{orderedSpaceIds.length - 1}</label>
      <p class="hint">Red dots should overlap cyan. Happy with the alignment?</p>
    </section>

    <section class="row-section">
      <button onclick={() => { phase = 'pickSource'; srcPoints = []; tgtPoints = []; pointPlaced = false; currentTransform = null }}>Redo</button>
      <button class="primary" onclick={confirmStitch}>
        {currentIdx < orderedSpaceIds.length - 1 ? 'Next scan →' : 'Finish →'}
      </button>
    </section>

  {:else if phase === 'complete'}
    <section>
      <label class="section-label">All scans stitched</label>
      <p class="hint placed">{builtSpaces.length} spaces ready to save as "{buildingName}".</p>
    </section>

    <section>
      <button class="primary" style="width:100%" onclick={downloadMergedGlb} disabled={downloading}>
        {downloading ? 'Exporting…' : '↓ Download GLB'}
      </button>
    </section>
    <section class="row-section">
      <button onclick={resetBuilding}>Reset</button>
      <button class="primary" onclick={saveBuilding} disabled={saving}>
        {saving ? 'Saving…' : 'Save building'}
      </button>
    </section>
  {/if}
</Sidebar>

<Scene
  stitchPhase={scenePhase}
  stitchSourceGlbUrl={currentSourceGlbUrl}
  {mergedSpaces}
  {pointClouds}
  stitchSourcePoints={srcPoints}
  stitchTargetPoints={tgtPoints}
  stitchTransform={currentTransform}
  onplace={handleMeshClick}
/>

{#if error}
  <div class="error-toast" onclick={() => error = null}>{error}</div>
{/if}

<style>
  .row-section { flex-direction: row; }
  .row-section button { flex: 1; }

  .muted { text-transform: none; letter-spacing: 0; font-size: 10px; }

  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }
  .hint.placed { color: var(--text); }
  .hint.space-name { font-weight: 600; color: var(--accent); font-size: 13px; }

  .src-label { color: #ff4444; }
  .tgt-label { color: #44ffcc; }

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
  .up-btn {
    padding: 1px 5px;
    font-size: 11px;
    border-radius: 3px;
    flex-shrink: 0;
  }
  .remove-btn {
    padding: 1px 6px;
    font-size: 13px;
    color: var(--text-muted);
    border-color: transparent;
    background: transparent;
    flex-shrink: 0;
  }
  .remove-btn:hover { color: var(--danger); }

  .pairs-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    grid-template-rows: auto auto;
    gap: 6px 12px;
  }
  .pair-dot {
    width: 14px;
    height: 14px;
    border-radius: 50%;
    border: 2px solid var(--border);
    background: transparent;
    transition: background 0.15s, border-color 0.15s;
    justify-self: center;
  }
  .pair-dot.src.filled { background: #ff4444; border-color: #ff4444; }
  .pair-dot.tgt.filled { background: #44ffcc; border-color: #44ffcc; }
</style>
