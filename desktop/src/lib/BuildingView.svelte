<script lang="ts">

  import { onMount } from 'svelte'
  import { fetchSpaces, fetchDraftBuildings, fetchCompletedBuildings, getSpaceGlbUrl, createDraftBuilding, updateBuildingSpaceTransform, finalizeDraftBuilding, deleteBuilding, upsertCentroidAnchor, fetchAnchors } from './supabase'
  import { computeTransform, posToV3 } from './stitching'
  import { computeCentroids } from './centroid'
  import Scene from './Scene.svelte'
  import type { Anchor, Building, Position, RigidTransform, Space } from './types'
  import * as THREE from 'three'
  import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
  import { GLTFExporter } from 'three/examples/jsm/exporters/GLTFExporter.js'

  interface Props {
    onback?: () => void;
  }

  let { onback }: Props = $props()

  type Phase = 'setup' | 'view' | 'pickSource' | 'pickTarget' | 'preview' | 'complete'

  interface SpaceEntry {
    space: Space
    glbUrl: string
    transform: RigidTransform | null  // null = reference (index 0)
  }

  // Setup state
  let allSpaces: Space[] = $state([])
  let draftBuildings: (Building & { spaces: Space[] })[] = $state([])
  let completedBuildings: (Building & { spaces: Space[] })[] = $state([])
  let buildingName = $state('')
  let orderedSpaceIds: string[] = $state([])  // user-chosen order; index 0 = reference

  // Build-up state
  let phase = $state<Phase>('setup')
  let builtSpaces: SpaceEntry[] = $state([])   // spaces confirmed so far (index 0 is reference)
  let currentIdx = $state(1)                    // index into orderedSpaceIds being stitched now
  let activeBuildingId: string | null = null

  // Current stitch point picking
  let srcPoints: Position[] = $state([])
  let tgtPoints: Position[] = $state([])
  let pointPlaced = $state(false)
  let currentTransform: RigidTransform | null = $state(null)

  let saving = $state(false)
  let error: string | null = $state(null)

  onMount(async () => {
    try {
      [allSpaces, draftBuildings, completedBuildings] = await Promise.all([
        fetchSpaces(), fetchDraftBuildings(), fetchCompletedBuildings()
      ])
    } catch (e) { error = (e as Error).message }
  })

  // ── Derived ──
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

  // Only show the most recently confirmed space as the stitch target
  let lastBuilt = $derived(builtSpaces[builtSpaces.length - 1])
  let mergedSpaces = $derived((phase === 'view' || phase === 'complete')
    ? builtSpaces.map(e => ({ url: e.glbUrl, transform: e.transform }))
    : lastBuilt ? [{ url: lastBuilt.glbUrl, transform: lastBuilt.transform }] : [])

  // Scene stitchPhase: only show idle when setup/view/complete
  let scenePhase = $derived((phase === 'setup' || phase === 'view' || phase === 'complete') ? 'idle' : phase as any)

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

  async function discardDraft(draft: Building & { spaces: Space[] }): Promise<void> {
    try {
      await deleteBuilding(draft.id)
      draftBuildings = draftBuildings.filter(d => d.id !== draft.id)
    } catch (e) {
      error = (e as Error).message
    }
  }

  async function deleteCompletedBuilding(building: Building & { spaces: Space[] }): Promise<void> {
    try {
      await deleteBuilding(building.id)
      completedBuildings = completedBuildings.filter(b => b.id !== building.id)
      if (activeBuildingId === building.id) resetBuilding()
    } catch (e) {
      error = (e as Error).message
    }
  }

  async function viewBuilding(building: Building & { spaces: Space[] }): Promise<void> {
    const sorted = [...building.spaces].sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
    builtSpaces = await Promise.all(sorted.map(async s => ({ space: s, glbUrl: await getSpaceGlbUrl(s.glb_path!), transform: s.offset_transformation })))
    buildingName = building.name ?? ''
    activeBuildingId = building.id
    loadBuildingAnchors(builtSpaces)
    phase = 'view'
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
    // Draft stays in DB and can be resumed later
    phase = 'setup'
    builtSpaces = []
    srcPoints = []
    tgtPoints = []
    pointPlaced = false
    currentTransform = null
    activeBuildingId = null
    orderedSpaceIds = []
    buildingName = ''
    Promise.all([fetchDraftBuildings(), fetchCompletedBuildings()])
      .then(([drafts, completed]) => { draftBuildings = drafts; completedBuildings = completed })
      .catch(() => {})
  }

  let buildingAnchors: Anchor[] = $state([])

  async function loadBuildingAnchors(spaces: SpaceEntry[]): Promise<void> {
    const all = await Promise.all(spaces.map(e => fetchAnchors(e.space.id)))
    const flat = all.flat()
    // Transform each anchor's glb_position into building frame using the space's offset transform
    buildingAnchors = flat
      .filter(a => a.glb_position)
      .map(a => {
        const entry = spaces.find(e => e.space.id === a.space_id)
        if (!entry?.transform) return a  // reference space — identity, no transform needed
        const { position: p, quaternion: q } = entry.transform
        const v = new THREE.Vector3(a.glb_position!.x, a.glb_position!.y, a.glb_position!.z)
        v.applyQuaternion(new THREE.Quaternion(q.x, q.y, q.z, q.w))
        v.add(new THREE.Vector3(p.x, p.y, p.z))
        return { ...a, glb_position: { x: v.x, y: v.y, z: v.z } }
      })
  }

  let recomputingCentroids = $state(false)
  let voxelSize = $state(0.5)
  let overlapPenalty = $state(1)
  let pointClouds: Array<{ points: import('./types').Position[]; color: number }> = $state([])

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

      // Colour each space's Voronoi region distinctly
      pointClouds = [...voronoiPoints.entries()].map(([spaceId, points], i) => ({
        points,
        color: SPACE_COLORS[i % SPACE_COLORS.length],
      }))

      await Promise.all([...centroids.entries()].map(([spaceId, pos]) =>
        upsertCentroidAnchor(spaceId, pos)
      ))
      await loadBuildingAnchors(builtSpaces)
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
      const loader = new GLTFLoader()
      const root = new THREE.Group()

      for (const entry of builtSpaces) {
        const gltf = await new Promise<any>((resolve, reject) =>
          loader.load(entry.glbUrl, resolve, undefined, reject)
        )
        const scene = gltf.scene as THREE.Group
        if (entry.transform) {
          const { position: p, quaternion: q } = entry.transform
          scene.position.set(p.x, p.y, p.z)
          scene.quaternion.set(q.x, q.y, q.z, q.w)
        }
        root.add(scene)
      }

      const exporter = new GLTFExporter()
      const buffer = await new Promise<ArrayBuffer>((resolve, reject) =>
        exporter.parse(root, resolve as any, reject, { binary: true })
      )
      const blob = new Blob([buffer], { type: 'model/gltf-binary' })
      const url = URL.createObjectURL(blob)
      const a = document.createElement('a')
      a.href = url
      a.download = `${buildingName || 'building'}.glb`
      a.click()
      URL.revokeObjectURL(url)
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
      draftBuildings = draftBuildings.filter(d => d.id !== activeBuildingId)
      completedBuildings = await fetchCompletedBuildings()
      phase = 'setup'
      builtSpaces = []
      orderedSpaceIds = []
      buildingName = ''
      activeBuildingId = null
    } catch (e) {
      error = (e as Error).message
    } finally {
      saving = false
    }
  }
</script>

<!-- sidebar -->
<aside>
  <div class="header">
    <button class="back-btn" onclick={() => onback?.()}>← Back</button>
    <span class="logo">Building Manager</span>
  </div>

  <!-- ── Setup ── -->
  {#if phase === 'setup'}
    {#if draftBuildings.length > 0}
      <section>
        <label class="section-label">Resume draft</label>
        <ul class="pool-list">
          {#each draftBuildings as draft (draft.id)}
            {@const stitched = draft.spaces.filter(s => s.building_index === 0 || s.offset_transformation !== null).length}
            {@const total = draft.spaces.length}
            <li class="draft-item">
              <div class="draft-info">
                <span class="draft-name">{draft.name || 'Unnamed'}</span>
                <span class="draft-progress">{stitched}/{total} spaces</span>
              </div>
              <div class="draft-actions">
                <button class="primary small" onclick={() => resumeBuilding(draft)}>Resume</button>
                <button class="discard-btn" onclick={() => discardDraft(draft)}>×</button>
              </div>
            </li>
          {/each}
        </ul>
      </section>
    {/if}

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

    {#if completedBuildings.length > 0}
      <section>
        <label class="section-label">Buildings</label>
        <ul class="pool-list">
          {#each completedBuildings as b (b.id)}
            <li class="pool-item">
              <span class="building-name" onclick={() => viewBuilding(b)}>{b.name || 'Unnamed'}</span>
              <span class="space-count">{b.spaces?.length ?? 0}</span>
              <button class="discard-btn" onclick={(e) => { e.stopPropagation(); deleteCompletedBuilding(b) }}>×</button>
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

  <!-- ── View ── -->
  {:else if phase === 'view'}
    <section>
      <label class="section-label">Viewing</label>
      <p class="hint space-name">{buildingName}</p>
    </section>
    <section>
      <label class="section-label">Spaces</label>
      <ul class="order-list">
        {#each builtSpaces as entry, i (entry.space.id)}
          <li class="order-item">
            {#if i === 0}<span class="ref-badge">ref</span>{/if}
            <span class="order-name">{entry.space.name || entry.space.id}</span>
          </li>
        {/each}
      </ul>
    </section>
    <section>
      <button class="primary" style="width:100%" onclick={downloadMergedGlb} disabled={downloading}>
        {downloading ? 'Exporting…' : '↓ Download GLB'}
      </button>
      <label class="section-label" style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
        Voxel size: {voxelSize.toFixed(2)}m
        <input type="range" min="0.1" max="2" step="0.05" bind:value={voxelSize} style="flex:1" />
      </label>
      <label class="section-label" style="display:flex;align-items:center;gap:8px;margin-bottom:4px">
        Overlap penalty:
        <input type="number" min="0" step="0.5" bind:value={overlapPenalty} style="width:70px" />
      </label>
      <button style="width:100%" onclick={recomputeCentroids} disabled={recomputingCentroids}>
        {recomputingCentroids ? 'Computing…' : '⟳ Recompute centroids'}
      </button>
      <button style="width:100%" onclick={resetBuilding}>← Back</button>
    </section>

  <!-- ── Picking ── -->
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

  <!-- ── Preview ── -->
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

  <!-- ── Complete ── -->
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
</aside>

<Scene
  stitchPhase={scenePhase}
  stitchSourceGlbUrl={currentSourceGlbUrl}
  {mergedSpaces}
  anchors={buildingAnchors}
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
  aside {
    width: 280px;
    min-width: 280px;
    background: var(--surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }

  .header {
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
    flex-shrink: 0;
  }

  .back-btn {
    padding: 3px 8px;
    font-size: 11px;
    border-radius: 4px;
    color: var(--text-muted);
    border-color: var(--border);
    flex-shrink: 0;
  }
  .back-btn:hover { color: var(--text); }

  .logo {
    font-size: 14px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.02em;
  }

  section {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
  }

  .row-section { flex-direction: row; }
  .row-section button { flex: 1; }

  .section-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
  }
  .muted { text-transform: none; letter-spacing: 0; font-size: 10px; }

  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }
  .hint.placed { color: var(--text); }
  .hint.space-name { font-weight: 600; color: var(--accent); font-size: 13px; }

  .src-label { color: #ff4444; }
  .tgt-label { color: #44ffcc; }

  /* Space pool */
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
  .space-count { font-size: 11px; color: var(--text-muted); flex-shrink: 0; }
  .building-name { flex: 1; cursor: pointer; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .building-name:hover { color: var(--accent); }

  /* Order list */
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

  /* Pairs dots */
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

  .draft-item {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 6px 4px;
    font-size: 13px;
    gap: 8px;
  }
  .draft-info { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
  .draft-name { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .draft-progress { font-size: 11px; color: var(--text-muted); }
  .draft-actions { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }
  button.small { padding: 3px 8px; font-size: 11px; }
  .discard-btn {
    padding: 1px 6px;
    font-size: 13px;
    color: var(--text-muted);
    border-color: transparent;
    background: transparent;
  }
  .discard-btn:hover { color: var(--danger); }

  .error-toast {
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: #ff444488;
    border: 1px solid var(--danger);
    border-radius: 8px;
    padding: 10px 16px;
    font-size: 13px;
    cursor: pointer;
    z-index: 200;
  }
</style>
