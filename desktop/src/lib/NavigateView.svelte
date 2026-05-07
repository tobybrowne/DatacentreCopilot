<script lang="ts">
  import { onMount } from 'svelte'
  import { Canvas } from '@threlte/core'
  import { exportNavMesh, NavMeshQuery, type NavMesh } from 'recast-navigation'
  import * as THREE from 'three'
  import NavigateSceneInner from './NavigateSceneInner.svelte'
  import Sidebar from './Sidebar.svelte'
  import type { Position, RigidTransform } from './types'
  import { saveNavMesh } from './supabase'
  import { buildNavMeshFromSpaces, loadNavMeshFromBuffer, computePath, type NavMeshParams } from './navmesh'

  interface Props {
    buildingId?: string | null;
    buildingName: string;
    spaces: Array<{ url: string; transform: RigidTransform | null }>;
    existingNavMesh?: { url: string; buildSettings: Record<string, unknown> } | null;
    onback?: () => void;
  }

  let {
    buildingId = null,
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
  let showParams = $state(true)
  let saveState: 'idle' | 'saving' | 'saved' | 'error' = $state('idle')
  let saveError: string | null = $state(null)

  let params: NavMeshParams = $state({
    boundsYMax: 3,
    cs: 0.1,
    ch: 0.1,
    walkableSlopeAngle: 35,
    walkableHeight: 20,
    walkableClimb: 3,
    walkableRadius: 0.1,
    maxEdgeLen: 40,
    maxSimplificationError: 1.3,
    minRegionArea: 8,
    mergeRegionArea: 20,
    maxVertsPerPoly: 6,
    detailSampleDist: 6,
    detailSampleMaxError: 1,
  })

  let pickingEnabled = $derived(phase === 'pickStart' || phase === 'pickEnd')

  async function handleSaveNavMesh(): Promise<void> {
    if (!navMesh || !buildingId) return
    saveState = 'saving'
    saveError = null
    try {
      const data = exportNavMesh(navMesh)
      await saveNavMesh(buildingId, data, { ...params } as unknown as Record<string, unknown>)
      saveState = 'saved'
    } catch (e) {
      saveError = (e as Error).message
      saveState = 'error'
    }
  }

  async function buildNavMesh(): Promise<void> {
    if (navQuery) { navQuery.destroy(); navQuery = null }
    if (navMesh) { navMesh.destroy(); navMesh = null }
    navMeshDebugMesh = null
    phase = 'loading'
    loadingMsg = 'Building navigation mesh…'
    error = null
    try {
      const result = await buildNavMeshFromSpaces(spaces, params)
      navMesh = result.navMesh
      navQuery = result.navQuery
      navMeshDebugMesh = result.debugMesh
      phase = 'pickStart'
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
      const result = await loadNavMeshFromBuffer(new Uint8Array(buffer))
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
  {#if phase === 'loading'}
    <section>
      <label class="section-label">Preparing</label>
      <p class="hint">{loadingMsg}</p>
      <div class="spinner"></div>
    </section>

  {:else if phase === 'pickStart'}
    <section>
      <label class="section-label">Start</label>
      <p class="hint">Click anywhere on the map to place your <strong class="green">start</strong> point.</p>
    </section>
    <section>
      <label class="toggle-row">
        <input type="checkbox" bind:checked={showNavMesh} />
        <span>Show walkable area</span>
      </label>
    </section>

  {:else if phase === 'pickEnd'}
    <section>
      <label class="section-label">Destination</label>
      <p class="hint">Now click your <strong class="red">destination</strong>.</p>
    </section>
    <section>
      <button style="width:100%" onclick={reset}>Reset</button>
    </section>

  {:else if phase === 'result'}
    <section>
      <label class="section-label">Route</label>
      <p class="distance">{pathLength.toFixed(1)}<span class="unit">m</span></p>
    </section>
    <section>
      <button class="primary" style="width:100%" onclick={reset}>New route</button>
    </section>

  {:else if phase === 'error'}
    <section>
      <label class="section-label">Error</label>
      <p class="hint danger">{error}</p>
      <button style="width:100%" onclick={reset}>Try again</button>
    </section>
  {/if}

  <section class="params-header" onclick={() => showParams = !showParams}>
    <label class="section-label" style="cursor:pointer;flex:1">Navmesh Params</label>
    <span class="chevron" class:open={showParams}>›</span>
  </section>
  {#if showParams}
    <section class="params-body">
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
        <label>Walkable height<span class="param-hint">voxels</span></label>
        <input type="number" step="1" min="1" bind:value={params.walkableHeight} />
      </div>
      <div class="param-row">
        <label>Walkable climb<span class="param-hint">voxels</span></label>
        <input type="number" step="1" min="0" bind:value={params.walkableClimb} />
      </div>
      <div class="param-row">
        <label>Walkable radius<span class="param-hint">voxels</span></label>
        <input type="number" step="1" min="0" bind:value={params.walkableRadius} />
      </div>
      <div class="param-row">
        <label>Max edge len<span class="param-hint">voxels</span></label>
        <input type="number" step="1" min="0" bind:value={params.maxEdgeLen} />
      </div>
      <div class="param-row">
        <label>Max simplification err<span class="param-hint">voxels</span></label>
        <input type="number" step="0.1" min="0" bind:value={params.maxSimplificationError} />
      </div>
      <div class="param-row">
        <label>Min region area<span class="param-hint">voxels²</span></label>
        <input type="number" step="1" min="0" bind:value={params.minRegionArea} />
      </div>
      <div class="param-row">
        <label>Merge region area<span class="param-hint">voxels²</span></label>
        <input type="number" step="1" min="0" bind:value={params.mergeRegionArea} />
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
      <button class="primary" style="width:100%;margin-top:4px" onclick={buildNavMesh}>Rebuild</button>
    </section>
  {/if}

  {#if buildingId && navMesh}
    <section>
      <button
        class="primary"
        style="width:100%"
        disabled={saveState === 'saving'}
        onclick={handleSaveNavMesh}
      >
        {saveState === 'saving' ? 'Saving…' : saveState === 'saved' ? 'Saved' : 'Save navmesh'}
      </button>
      {#if saveState === 'error'}
        <p class="hint danger">{saveError}</p>
      {/if}
    </section>
  {/if}
</Sidebar>

<div class="canvas-wrap">
  <Canvas>
    <NavigateSceneInner
      {spaces}
      {startPos}
      {endPos}
      {pathGeometry}
      {pickingEnabled}
      navMeshMesh={showNavMesh ? navMeshDebugMesh : null}
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

  .toggle-row {
    display: flex;
    align-items: center;
    gap: 8px;
    font-size: 12px;
    color: var(--text-muted);
    cursor: pointer;
  }

  .spinner {
    width: 20px;
    height: 20px;
    border: 2px solid var(--border);
    border-top-color: var(--accent);
    border-radius: 50%;
    animation: spin 0.8s linear infinite;
  }
  @keyframes spin { to { transform: rotate(360deg); } }

  .params-header {
    flex-direction: row;
    align-items: center;
    cursor: pointer;
    user-select: none;
  }
  .params-header:hover .section-label { color: var(--text); }

  .chevron {
    font-size: 16px;
    color: var(--text-muted);
    transition: transform 0.15s;
    transform: rotate(0deg);
  }
  .chevron.open { transform: rotate(90deg); }

  .params-body { gap: 6px; }

  .param-row {
    display: flex;
    align-items: center;
    justify-content: space-between;
    gap: 6px;
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
