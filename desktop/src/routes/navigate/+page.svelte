<script lang="ts">
  import { onMount } from 'svelte'
  import { goto } from '$app/navigation'
  import { fetchCompletedBuildings, fetchSpaces } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import SidebarList from '$lib/SidebarList.svelte'
  import { toast } from '$lib/toast'
  import type { Building, Space } from '$lib/types'

  let buildings: (Building & { spaces: Space[] })[] = $state([])
  let spaces: Space[] = $state([])

  onMount(async () => {
    try {
      ;[buildings, spaces] = await Promise.all([fetchCompletedBuildings(), fetchSpaces()])
      spaces = spaces.filter(s => s.glb_path)
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

  <SidebarList
    title="Individual Spaces"
    items={spaces}
    empty="No navigable spaces yet."
    onclick={(s) => goto(`/navigate/space/${s.id}`)}
  >
    {#snippet item(s)}
      <span class="name">{s.name || 'Unnamed'}</span>
      <span class="meta">space</span>
    {/snippet}
  </SidebarList>

</Sidebar>

<div class="empty-scene">
  <p>Select a building or space to navigate.</p>
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
