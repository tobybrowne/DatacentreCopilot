<script lang="ts">
  import { onMount } from 'svelte'
  import { goto } from '$app/navigation'
  import { fetchCompletedBuildings } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import SidebarList from '$lib/SidebarList.svelte'
  import { toast } from '$lib/toast'
  import type { Building, Space } from '$lib/types'

  let buildings: (Building & { spaces: Space[] })[] = $state([])

  onMount(async () => {
    try {
      buildings = await fetchCompletedBuildings()
    } catch (e) {
      toast((e as Error).message)
    }
  })
</script>

<Sidebar title="Navigate" onback={() => goto('/')}>
  <SidebarList
    title="Buildings"
    items={buildings}
    empty="No navigable buildings yet."
    onclick={(b) => goto(`/navigate/${b.id}`)}
  >
    {#snippet item(b)}
      <span class="name">{b.name || 'Unnamed'}</span>
      <span class="meta">{b.spaces?.length ?? 0} spaces</span>
    {/snippet}
  </SidebarList>

</Sidebar>

<div class="empty-scene">
  <p>Select a building to navigate.</p>
</div>

<style>
  .name { flex: 1; font-size: 13px; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
  .meta { font-size: 11px; color: var(--text-muted); flex-shrink: 0; }

  .empty-scene {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
    font-size: 13px;
  }
</style>
