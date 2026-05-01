<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import { fetchCompletedBuildings, fetchDraftBuildings, deleteBuilding, getSpaceGlbUrl } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import SidebarList from '$lib/SidebarList.svelte'
  import { Canvas } from '@threlte/core'
  import NavigateSceneInner from '$lib/NavigateSceneInner.svelte'
  import type { Building, RigidTransform, Space } from '$lib/types'

  let completed: (Building & { spaces: Space[] })[] = $state([])
  let drafts: (Building & { spaces: Space[] })[] = $state([])
  let selectedBuilding: (Building & { spaces: Space[] }) | null = $state(null)
  let mergedSpaces: { url: string; transform: RigidTransform | null }[] = $state([])
  let loadingScene = $state(false)
  let error: string | null = $state(null)

  onMount(async () => {
    try {
      ;[completed, drafts] = await Promise.all([fetchCompletedBuildings(), fetchDraftBuildings()])
    } catch (e) {
      error = (e as Error).message
    }
  })

  async function selectBuilding(b: Building & { spaces: Space[] }): Promise<void> {
    selectedBuilding = b
    loadingScene = true
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
      loadingScene = false
    }
  }

  async function discard(e: MouseEvent, id: string): Promise<void> {
    e.stopPropagation()
    try {
      await deleteBuilding(id)
      drafts = drafts.filter(d => d.id !== id)
    } catch (err) {
      error = (err as Error).message
    }
  }

  async function remove(e: MouseEvent, id: string): Promise<void> {
    e.stopPropagation()
    try {
      await deleteBuilding(id)
      completed = completed.filter(b => b.id !== id)
      if (selectedBuilding?.id === id) { selectedBuilding = null; mergedSpaces = [] }
    } catch (err) {
      error = (err as Error).message
    }
  }
</script>

<div class="layout">
  <Sidebar title="Building Manager" onback={() => goto('/')}>
    {#if drafts.length > 0}
      <SidebarList title="Drafts" items={drafts}>
        {#snippet item(draft)}
          {@const stitched = draft.spaces.filter(s => s.building_index === 0 || s.offset_transformation !== null).length}
          <div class="info">
            <span class="name">{draft.name || 'Unnamed'}</span>
            <span class="sub">{stitched}/{draft.spaces.length} spaces stitched</span>
          </div>
          <div class="actions">
            <button class="primary small" onclick={() => goto(`/buildings/create?draft=${draft.id}`)}>Resume</button>
            <button class="icon-btn" onclick={(e) => discard(e, draft.id)}>×</button>
          </div>
        {/snippet}
      </SidebarList>
    {/if}

    <SidebarList
      title="Buildings"
      items={completed}
      empty="No buildings yet."
      onclick={selectBuilding}
      selected={(b) => selectedBuilding?.id === b.id}
    >
      {#snippet item(b)}
        <div class="info">
          <span class="name">{b.name || 'Unnamed'}</span>
          <span class="sub">{b.spaces?.length ?? 0} spaces</span>
        </div>
      {/snippet}
    </SidebarList>

    <section>
      <button class="primary" style="width:100%" onclick={() => goto('/buildings/create')}>+ New building</button>
    </section>

    {#if error}
      <p class="err">{error}</p>
    {/if}
  </Sidebar>

  <div class="scene-wrap">
    {#if loadingScene}
      <div class="placeholder">Loading building…</div>
    {:else if mergedSpaces.length > 0}
      <Canvas>
        <NavigateSceneInner spaces={mergedSpaces} />
      </Canvas>
    {:else}
      <div class="placeholder">Select a building to view</div>
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

  .info { display: flex; flex-direction: column; gap: 2px; flex: 1; min-width: 0; }
  .name { font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .sub { font-size: 11px; color: var(--text-muted); }

  .actions { display: flex; align-items: center; gap: 4px; flex-shrink: 0; }

  button.small { padding: 3px 8px; font-size: 11px; }

  .icon-btn {
    padding: 1px 6px;
    font-size: 13px;
    color: var(--text-muted);
    border-color: transparent;
    background: transparent;
    flex-shrink: 0;
  }
  .icon-btn:hover { color: var(--danger); }

  .err { padding: 8px 16px; font-size: 12px; color: var(--danger); }

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
