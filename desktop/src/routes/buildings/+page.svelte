<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import { fetchCompletedBuildings, fetchDraftBuildings, deleteBuilding } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import SidebarList from '$lib/SidebarList.svelte'
  import { toast } from '$lib/toast'
  import type { Building, Space } from '$lib/types'

  let completed: (Building & { spaces: Space[] })[] = $state([])
  let drafts: (Building & { spaces: Space[] })[] = $state([])

  onMount(async () => {
    try {
      ;[completed, drafts] = await Promise.all([fetchCompletedBuildings(), fetchDraftBuildings()])
    } catch (e) {
      toast((e as Error).message)
    }
  })

  async function discard(e: MouseEvent, id: string): Promise<void> {
    e.stopPropagation()
    try {
      await deleteBuilding(id)
      drafts = drafts.filter(d => d.id !== id)
    } catch (e) {
      toast((e as Error).message)
    }
  }

</script>

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
    onclick={(b) => goto(`/buildings/${b.id}`)}
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
</Sidebar>

<style>
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
</style>
