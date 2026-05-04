<script lang="ts">
  import { goto } from '$app/navigation'
  import { onDestroy } from 'svelte'
  import { fetchCompletedBuildings, getSpaceGlbUrl, fetchUserPosition, subscribeUserPosition } from '$lib/supabase'
  import { Canvas } from '@threlte/core'
  import NavigateSceneInner from '$lib/NavigateSceneInner.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import SidebarList from '$lib/SidebarList.svelte'
  import type { Building, Position, RigidTransform, Space } from '$lib/types'

  const DEMO_USER_ID = '00000000-0000-0000-0000-000000000000'

  let buildings: (Building & { spaces: Space[] })[] = $state([])
  let selectedBuilding: (Building & { spaces: Space[] }) | null = $state(null)
  let mergedSpaces: { url: string; transform: RigidTransform | null; boundingBox: Space['bounding_box'] }[] = $state([])
  let showBoundingBoxes = $state(false)
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
          boundingBox: s.bounding_box,
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
  <Sidebar title="Live View" onback={() => goto('/')}>
    <SidebarList
      title="Buildings"
      items={buildings}
      empty="No completed buildings found."
      onclick={selectBuilding}
      selected={(b) => selectedBuilding?.id === b.id}
    >
      {#snippet item(b)}
        <div class="building-info">
          <span class="building-name">{b.name ?? 'Unnamed Building'}</span>
          <span class="building-meta">{b.spaces.length} space{b.spaces.length !== 1 ? 's' : ''}</span>
        </div>
      {/snippet}
    </SidebarList>

    {#if selectedBuilding}
      {#if mergedSpaces.length > 0}
        <section>
          <button style="width:100%" onclick={() => showBoundingBoxes = !showBoundingBoxes}>
            {showBoundingBoxes ? 'Hide boxes' : 'Show boxes'}
          </button>
        </section>
      {/if}

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
  </Sidebar>

  <div class="scene-wrap">
    {#if loading}
      <div class="placeholder">Loading building…</div>
    {:else if mergedSpaces.length > 0}
      <Canvas>
        <NavigateSceneInner spaces={mergedSpaces} startPos={userPosition} {showBoundingBoxes} />
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

  .building-info { display: flex; flex-direction: column; gap: 2px; }
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

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
</style>
