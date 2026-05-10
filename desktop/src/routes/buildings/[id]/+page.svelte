<script lang="ts">
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { onMount } from 'svelte'
  import { fetchBuildingById, getSpaceGlbUrl, deleteBuilding } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import { Canvas } from '@threlte/core'
  import NavigateSceneInner from '$lib/NavigateSceneInner.svelte'
  import { toast } from '$lib/toast'
  import type { Building, RigidTransform, Space } from '$lib/types'

  const buildingId = $page.params.id!

  let building: (Building & { spaces: Space[] }) | null = $state(null)
  let mergedSpaces: { url: string; transform: RigidTransform | null; boundingBox: Space['bounding_box']; locBoundingBox: Space['loc_bounding_box'] }[] = $state([])
  let showScanBounds = $state(false)
  let showLocBounds = $state(false)
  let loading = $state(true)

  let locBoundingBoxes = $derived(
    mergedSpaces.flatMap(s => s.locBoundingBox ? [s.locBoundingBox] : [])
  )

  onMount(async () => {
    try {
      building = await fetchBuildingById(buildingId)
      const sorted = [...building.spaces]
        .filter(s => s.glb_path)
        .sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0))
      mergedSpaces = await Promise.all(
        sorted.map(async s => ({
          url: await getSpaceGlbUrl(s.glb_path!),
          transform: s.offset_transformation as RigidTransform | null,
          boundingBox: s.bounding_box,
          locBoundingBox: s.loc_bounding_box,
        }))
      )
    } catch (e) {
      toast((e as Error).message)
    } finally {
      loading = false
    }
  })

  async function handleDelete(): Promise<void> {
    if (!building) return
    if (!confirm(`Delete "${building.name}"? This cannot be undone.`)) return
    try {
      await deleteBuilding(building.id)
      goto('/buildings')
    } catch (e) {
      toast((e as Error).message)
    }
  }
</script>

<div class="layout">
  <Sidebar title={building?.name || 'Building'} onback={() => goto('/buildings')}>
    {#if loading}
      <p class="muted">Loading…</p>
    {:else if building}
      <section>
        <label class="section-label">Spaces <span class="badge">{building.spaces.length}</span></label>
        <ul class="space-list">
          {#each [...building.spaces].sort((a, b) => (a.building_index ?? 0) - (b.building_index ?? 0)) as space (space.id)}
            <li>
              <span class="space-name">{space.name || 'Unnamed'}</span>
            </li>
          {/each}
        </ul>
      </section>

      <section>
        <button style="width:100%" onclick={() => goto(`/buildings/create?restitch=${building!.id}`)}>Re-stitch</button>
      </section>

      {#if mergedSpaces.length > 0}
        <section>
          <button style="width:100%;margin-bottom:4px" onclick={() => showScanBounds = !showScanBounds}>
            {showScanBounds ? 'Hide Scan Bounds' : 'Show Scan Bounds'}
          </button>
          <button style="width:100%" onclick={() => showLocBounds = !showLocBounds}>
            {showLocBounds ? 'Hide Location Bounds' : 'Show Location Bounds'}
          </button>
        </section>
      {/if}

      <section>
        <button class="danger" style="width:100%" onclick={handleDelete}>Delete building</button>
      </section>
    {/if}
  </Sidebar>

  <div class="scene-wrap">
    {#if loading}
      <div class="placeholder">Loading building…</div>
    {:else if mergedSpaces.length > 0}
      <Canvas>
        <NavigateSceneInner
          spaces={mergedSpaces}
          showBoundingBoxes={showScanBounds}
          collapsedBoxes={showLocBounds ? locBoundingBoxes : []}
        />
      </Canvas>
    {:else}
      <div class="placeholder">No stitched spaces yet.</div>
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

  .muted { color: var(--text-muted); font-size: 12px; font-style: italic; }

  .section-label {
    display: flex;
    align-items: center;
    gap: 6px;
    font-size: 11px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
    margin-bottom: 6px;
  }

  .badge {
    background: var(--accent-dim);
    color: var(--accent);
    border-radius: 10px;
    padding: 1px 7px;
    font-size: 11px;
  }

  .space-list {
    list-style: none;
    display: flex;
    flex-direction: column;
  }

  .space-list li {
    display: flex;
    align-items: center;
    justify-content: space-between;
    padding: 7px 0;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
  }

  .space-list li:last-child { border-bottom: none; }

  .space-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

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
</style>
