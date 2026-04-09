<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte'
  import { Canvas } from '@threlte/core'
  import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
  import * as THREE from 'three'
  import { init as initRecast, NavMeshQuery, exportNavMesh, importNavMesh, type NavMesh } from 'recast-navigation'
  import { threeToSoloNavMesh, NavMeshHelper } from '@recast-navigation/three'
  import NavigateSceneInner from './NavigateSceneInner.svelte'
  import type { Position, RigidTransform } from './types'
  import { saveNavMesh } from './supabase'

  export let buildingId: string | null = null
  export let buildingName: string
  export let spaces: Array<{ url: string; transform: RigidTransform | null }>
  export let existingNavMesh: { url: string; buildSettings: Record<string, unknown> } | null = null

  const dispatch = createEventDispatcher<{ back: void }>()

  type Phase = 'loading' | 'pickStart' | 'pickEnd' | 'result' | 'error'
  let phase: Phase = 'loading'
  let loadingMsg = 'Loading models…'
  let error: string | null = null

  let navMesh: NavMesh | null = null
  let navQuery: NavMeshQuery | null = null
  let navMeshDebugMesh: THREE.Mesh | null = null
  let recastInputDebug: THREE.Group | null = null
  let startPos: Position | null = null
  let endPos: Position | null = null
  let pathGeometry: THREE.TubeGeometry | null = null
  let pathLength = 0
  let showNavMesh = true
  let showParams = true
  let saveState: 'idle' | 'saving' | 'saved' | 'error' = 'idle'
  let saveError: string | null = null

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

  // Navmesh generation parameters — all editable before building
  let params = {
    boundsYMax: 3,  // metres above detected floor — excludes roof geometry above this height
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
  }

  $: pickingEnabled = phase === 'pickStart' || phase === 'pickEnd'

  async function generateNavMesh(): Promise<void> {
    // Tear down any previous navmesh resources before rebuilding
    if (navQuery) { navQuery.destroy(); navQuery = null }
    if (navMesh) { navMesh.destroy(); navMesh = null }
    navMeshDebugMesh = null

    loadingMsg = 'Loading models…'
    const meshes = await loadMeshes()

    loadingMsg = 'Generating navigation mesh…'

    const inputBox = new THREE.Box3()
    let totalVerts = 0
    meshes.forEach(m => {
      inputBox.expandByObject(m)
      totalVerts += m.geometry.attributes.position.count
    })
    console.log('[NavMesh] input meshes:', meshes.length, 'verts:', totalVerts, 'bounds:', inputBox.min, inputBox.max)

    recastInputDebug = null

    // Strip triangles where every vertex is above boundsYMax metres above the floor.
    // Using bounds[] instead would clip walls and treat the cut edge as a new walkable surface.
    const { boundsYMax, ...recastParams } = params
    const yMax = inputBox.min.y + boundsYMax
    const clipped = meshes.map(m => {
      const pos = m.geometry.attributes.position
      const idx = m.geometry.index
      const outPos: number[] = []
      const outIdx: number[] = []
      const remap = new Int32Array(pos.count).fill(-1)
      const triCount = idx ? idx.count / 3 : pos.count / 3
      for (let t = 0; t < triCount; t++) {
        const ia = idx ? idx.getX(t * 3)     : t * 3
        const ib = idx ? idx.getX(t * 3 + 1) : t * 3 + 1
        const ic = idx ? idx.getX(t * 3 + 2) : t * 3 + 2
        // Keep triangle if any vertex is at or below yMax
        if (pos.getY(ia) > yMax && pos.getY(ib) > yMax && pos.getY(ic) > yMax) continue
        for (const vi of [ia, ib, ic]) {
          if (remap[vi] === -1) {
            remap[vi] = outPos.length / 3
            outPos.push(pos.getX(vi), pos.getY(vi), pos.getZ(vi))
          }
          outIdx.push(remap[vi])
        }
      }
      const g = new THREE.BufferGeometry()
      g.setAttribute('position', new THREE.Float32BufferAttribute(outPos, 3))
      g.setIndex(outIdx)
      return new THREE.Mesh(g, m.material)
    })

    const result = threeToSoloNavMesh(clipped, { ...recastParams })
    if (!result.success || !result.navMesh) {
      throw new Error('Failed to generate navigation mesh. The scan geometry may be too noisy.')
    }
    navMesh = result.navMesh

    navQuery = new NavMeshQuery(navMesh)
    navQuery.defaultQueryHalfExtents = { x: 2, y: 4, z: 2 }

    const cx = (inputBox.min.x + inputBox.max.x) / 2
    const cz = (inputBox.min.z + inputBox.max.z) / 2
    const floorProbe = navQuery.findClosestPoint({ x: cx, y: inputBox.min.y + 0.5, z: cz })
    console.log('[NavMesh] floor probe result:', floorProbe)

    const helper = new NavMeshHelper(navMesh, {
      navMeshMaterial: new THREE.MeshStandardMaterial({ color: '#00d4ff', opacity: 0.4, transparent: true, side: THREE.DoubleSide }),
    })
    navMeshDebugMesh = helper.mesh

    const navBox = new THREE.Box3().setFromObject(helper.mesh)
    const navPos = helper.mesh.geometry.attributes.position
    console.log('[NavMesh] nav poly verts:', navPos.count, 'bounds (world):', navBox.min, navBox.max)
  }

  async function buildNavMesh(): Promise<void> {
    phase = 'loading'
    error = null
    try {
      await generateNavMesh()
      phase = 'pickStart'
    } catch (e) {
      error = (e as Error).message
      phase = 'error'
    }
  }

  async function loadMeshes(): Promise<THREE.Mesh[]> {
    const loader = new GLTFLoader()
    const meshes: THREE.Mesh[] = []

    for (const [si, space] of spaces.entries()) {
      const gltf = await loader.loadAsync(space.url)

      console.log(`[NavMesh] space[${si}] gltf.scene pos:`, gltf.scene.position, 'quat:', gltf.scene.quaternion, 'transform:', space.transform)

      const group = new THREE.Group()
      if (space.transform) {
        const { position: p, quaternion: q } = space.transform
        group.position.set(p.x, p.y, p.z)
        group.quaternion.set(q.x, q.y, q.z, q.w)
      }
      group.add(gltf.scene)
      group.updateWorldMatrix(true, true)

      const spaceBox = new THREE.Box3()
      const beforeCount = meshes.length
      group.traverse(obj => {
        if ((obj as THREE.Mesh).isMesh) {
          const src = obj as THREE.Mesh
          const baked = src.geometry.clone().applyMatrix4(src.matrixWorld)
          spaceBox.expandByObject(new THREE.Mesh(baked))
          meshes.push(new THREE.Mesh(baked, src.material))
        }
      })
      console.log(`[NavMesh] space[${si}] bounds:`, spaceBox.min, spaceBox.max, `(${meshes.length - beforeCount} meshes)`)
    }

    return meshes
  }

  async function loadExistingNavMesh(): Promise<void> {
    if (!existingNavMesh) return
    phase = 'loading'
    loadingMsg = 'Loading saved navmesh…'
    try {
      const res = await fetch(existingNavMesh.url)
      if (!res.ok) throw new Error(`Failed to fetch navmesh: ${res.status}`)
      const buffer = await res.arrayBuffer()
      const result = importNavMesh(new Uint8Array(buffer))
      if (!result.navMesh) throw new Error('Failed to import navmesh')
      navMesh = result.navMesh

      // Restore build settings
      const bs = existingNavMesh.buildSettings
      for (const key of Object.keys(params) as (keyof typeof params)[]) {
        if (key in bs && typeof bs[key] === 'number') (params as Record<string, number>)[key] = bs[key] as number
      }

      navQuery = new NavMeshQuery(navMesh)
      navQuery.defaultQueryHalfExtents = { x: 2, y: 4, z: 2 }

      const helper = new NavMeshHelper(navMesh, {
        navMeshMaterial: new THREE.MeshStandardMaterial({ color: '#00d4ff', opacity: 0.4, transparent: true, side: THREE.DoubleSide }),
      })
      navMeshDebugMesh = helper.mesh

      phase = 'pickStart'
    } catch (e) {
      error = (e as Error).message
      phase = 'error'
    }
  }

  onMount(async () => {
    await initRecast()
    if (existingNavMesh) {
      await loadExistingNavMesh()
    } else {
      await buildNavMesh()
    }
  })

  function handlePlace({ detail: pos }: CustomEvent<Position>): void {
    if (phase === 'pickStart') {
      startPos = pos
      phase = 'pickEnd'
    } else if (phase === 'pickEnd') {
      endPos = pos
      computePath()
    }
  }

  function computePath(): void {
    if (!navQuery || !startPos || !endPos) return

    const { point: snappedStart, success: startOk } = navQuery.findClosestPoint(startPos)
    const { point: snappedEnd,   success: endOk   } = navQuery.findClosestPoint(endPos)

    if (!startOk || !endOk) {
      error = 'One or both points are too far from any walkable surface. Try clicking closer to the floor.'
      phase = 'error'
      return
    }

    const { path } = navQuery.computePath(snappedStart, snappedEnd)

    if (path.length < 2) {
      error = 'No path found — the two points may be in disconnected areas.'
      phase = 'error'
      return
    }

    const elevated = path.map(p => new THREE.Vector3(p.x, p.y + 0.05, p.z))
    const curve = new THREE.CatmullRomCurve3(elevated)
    pathGeometry = new THREE.TubeGeometry(curve, elevated.length * 4, 0.04, 8, false)

    pathLength = path.reduce((acc, pt, i) => {
      if (i === 0) return 0
      const prev = path[i - 1]
      return acc + Math.hypot(pt.x - prev.x, pt.z - prev.z)
    }, 0)

    phase = 'result'
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

<aside>
  <div class="header">
    <button class="back-btn" on:click={() => dispatch('back')}>← Back</button>
    <span class="logo">{buildingName}</span>
  </div>

  {#if phase === 'loading'}
    <section>
      <label class="section-label">Preparing</label>
      <p class="hint">{loadingMsg}</p>
      <div class="spinner" />
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
      <button style="width:100%" on:click={reset}>Reset</button>
    </section>

  {:else if phase === 'result'}
    <section>
      <label class="section-label">Route</label>
      <p class="distance">{pathLength.toFixed(1)}<span class="unit">m</span></p>
    </section>
    <section>
      <button class="primary" style="width:100%" on:click={reset}>New route</button>
    </section>

  {:else if phase === 'error'}
    <section>
      <label class="section-label">Error</label>
      <p class="hint danger">{error}</p>
      <button style="width:100%" on:click={reset}>Try again</button>
    </section>
  {/if}

  <!-- Navmesh params panel -->
  <section class="params-header" on:click={() => showParams = !showParams}>
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
      <button class="primary" style="width:100%;margin-top:4px" on:click={buildNavMesh}>Rebuild</button>
    </section>
  {/if}

  {#if buildingId && navMesh}
    <section>
      <button
        class="primary"
        style="width:100%"
        disabled={saveState === 'saving'}
        on:click={handleSaveNavMesh}
      >
        {saveState === 'saving' ? 'Saving…' : saveState === 'saved' ? 'Saved ✓' : 'Save navmesh'}
      </button>
      {#if saveState === 'error'}
        <p class="hint danger">{saveError}</p>
      {/if}
    </section>
  {/if}
</aside>

<div class="canvas-wrap">
  <Canvas>
    <NavigateSceneInner
      {spaces}
      {startPos}
      {endPos}
      {pathGeometry}
      {pickingEnabled}
      navMeshMesh={showNavMesh ? navMeshDebugMesh : null}
      {recastInputDebug}
      on:place={handlePlace}
    />
  </Canvas>
</div>

<style>
  aside {
    width: 260px;
    min-width: 260px;
    background: var(--surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }

  .canvas-wrap {
    flex: 1;
    height: 100vh;
    overflow: hidden;
  }

  .header {
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    align-items: center;
    gap: 12px;
    flex-shrink: 0;
  }

  .back-btn {
    padding: 3px 8px;
    font-size: 11px;
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
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
  }

  section {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
    flex-shrink: 0;
  }

  .section-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
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

  .params-body {
    gap: 6px;
  }

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
