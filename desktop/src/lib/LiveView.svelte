<script lang="ts">
  import { onDestroy } from 'svelte'
  import { fetchCompletedBuildings, getSpaceGlbUrl, fetchUserPosition, subscribeUserPosition } from './supabase'
  import { Canvas } from '@threlte/core'
  import NavigateSceneInner from './NavigateSceneInner.svelte'
  import type { Building, Position, RigidTransform, Space } from './types'

  interface Props {
    onback?: () => void;
  }

  let { onback }: Props = $props()

  const DEMO_USER_ID = '00000000-0000-0000-0000-000000000000'

  let buildings: (Building & { spaces: Space[] })[] = $state([])
  let selectedBuilding: (Building & { spaces: Space[] }) | null = $state(null)
  let mergedSpaces: { url: string; transform: RigidTransform | null }[] = $state([])
  let userPosition: Position | null = $state(null)
  let monitoring = $state(false)
  let unsubscribeUser: (() => void) | null = null
  let loading = $state(false)
  let error: string | null = $state(null)

  loadBuildings()

  async function loadBuildings(): Promise<void> {
    try {
      buildings = await fetchCompletedBuildings()
    } catch (e) {
      error = (e as Error).message
    }
  }

  async function selectBuilding(b: Building & { spaces: Space[] }): Promise<void> {
    stopMonitoring()
    selectedBuilding = b
    loading = true
    mergedSpaces = []
    try {
      const sorted = [...b.spaces]
        .filter(s => s.glb_path)
        .sort((a, x) => (a.building_index ?? 0) - (x.building_index ?? 0))
      mergedSpaces = await Promise.all(
        sorted.map(async s => ({
          url: await getSpaceGlbUrl(s.glb_path!),
          transform: s.offset_transformation as RigidTransform | null,
        }))
      )
    } catch (e) {
      error = (e as Error).message
    } finally {
      loading = false
    }
  }

  async function startMonitoring(): Promise<void> {
    monitoring = true
    try {
      userPosition = await fetchUserPosition(DEMO_USER_ID)
    } catch (e) {
      error = (e as Error).message
    }
    unsubscribeUser = subscribeUserPosition(DEMO_USER_ID, (pos) => { userPosition = pos })
  }

  function stopMonitoring(): void {
    monitoring = false
    userPosition = null
    if (unsubscribeUser) { unsubscribeUser(); unsubscribeUser = null }
  }

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser()
  })
</script>

<div class="live-view">
  <aside class="sidebar">
    <div class="sidebar-header">
      <button class="back-btn" onclick={() => onback?.()}>← Back</button>
      <span class="sidebar-title">Live View</span>
    </div>

    <section>
      <label class="section-label">
        Buildings
        <span class="badge">{buildings.length}</span>
      </label>
      {#if buildings.length === 0}
        <p class="empty-msg">No completed buildings found.</p>
      {:else}
        <ul class="building-list">
          {#each buildings as b (b.id)}
            <li
              class="building-item"
              class:selected={selectedBuilding?.id === b.id}
              onclick={() => selectBuilding(b)}
            >
              <span class="building-name">{b.name ?? 'Unnamed Building'}</span>
              <span class="building-meta">{b.spaces.length} space{b.spaces.length !== 1 ? 's' : ''}</span>
            </li>
          {/each}
        </ul>
      {/if}
    </section>

    {#if selectedBuilding}
      <section>
        <label class="section-label">User Tracking</label>
        <button
          class="monitor-btn"
          class:active={monitoring}
          onclick={() => monitoring ? stopMonitoring() : startMonitoring()}
          disabled={loading}
        >
          <span class="dot" class:live={monitoring}></span>
          {monitoring ? 'Stop monitoring' : 'Start monitoring'}
        </button>
        {#if userPosition}
          <p class="position-readout">
            x {userPosition.x.toFixed(2)}&nbsp;
            y {userPosition.y.toFixed(2)}&nbsp;
            z {userPosition.z.toFixed(2)}
          </p>
        {:else if monitoring}
          <p class="empty-msg">Waiting for position…</p>
        {/if}
      </section>
    {/if}
  </aside>

  <div class="scene-wrap">
    {#if loading}
      <div class="placeholder">Loading building…</div>
    {:else if mergedSpaces.length > 0}
      <Canvas>
        <NavigateSceneInner spaces={mergedSpaces} startPos={userPosition} />
      </Canvas>
    {:else}
      <div class="placeholder">Select a building to view</div>
    {/if}
  </div>
</div>

{#if error}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="error-toast" onclick={() => error = null}>{error}</div>
{/if}

<style>
  .live-view {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .sidebar {
    width: 280px;
    min-width: 280px;
    background: var(--surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }

  .sidebar-header {
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
    flex-shrink: 0;
  }

  .sidebar-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.02em;
  }

  .back-btn {
    padding: 3px 8px;
    font-size: 11px;
    border-radius: 4px;
    color: var(--text-muted);
    border: 1px solid var(--border);
    background: transparent;
    cursor: pointer;
    transition: color 0.15s;
  }
  .back-btn:hover { color: var(--text); }

  section {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .section-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
    display: flex;
    align-items: center;
    gap: 6px;
  }

  .badge {
    background: var(--accent-dim);
    color: var(--accent);
    border-radius: 10px;
    padding: 1px 7px;
    font-size: 11px;
  }

  .building-list { list-style: none; display: flex; flex-direction: column; }

  .building-item {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 9px 4px;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    border-radius: 4px;
    transition: background 0.1s;
  }
  .building-item:last-child { border-bottom: none; }
  .building-item:hover { background: #202020; }
  .building-item.selected { background: var(--accent-dim); }

  .building-name { font-size: 13px; font-weight: 500; color: var(--text); }
  .building-meta { font-size: 11px; color: var(--text-muted); }

  .monitor-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    border-radius: 6px;
    border: 1px solid var(--border);
    color: var(--text-muted);
    font-size: 12px;
    cursor: pointer;
    background: transparent;
    transition: border-color 0.15s, color 0.15s, background 0.15s;
    width: 100%;
  }
  .monitor-btn:hover:not(:disabled) { border-color: var(--accent); color: var(--accent); }
  .monitor-btn.active { border-color: #ff4dff; color: #ff4dff; background: #ff4dff11; }
  .monitor-btn:disabled { opacity: 0.4; cursor: default; }

  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--text-muted);
    flex-shrink: 0;
  }
  .dot.live {
    background: #ff4dff;
    animation: pulse 1s infinite;
  }

  .position-readout {
    font-family: monospace;
    font-size: 11px;
    color: var(--text-muted);
  }

  .empty-msg {
    color: var(--text-muted);
    font-size: 12px;
    font-style: italic;
  }

  .scene-wrap {
    flex: 1;
    height: 100vh;
    overflow: hidden;
  }

  .placeholder {
    width: 100%;
    height: 100%;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
    font-size: 13px;
    background: var(--bg);
  }

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

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
</style>
