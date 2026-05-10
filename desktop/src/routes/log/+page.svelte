<script lang="ts">
  import { goto } from '$app/navigation'
  import { fetchCompletedBuildings } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import SidebarList from '$lib/SidebarList.svelte'
  import { toast } from '$lib/toast'
  import type { Building, Space } from '$lib/types'

  let buildings: (Building & { spaces: Space[] })[] = $state([])

  loadBuildings()

  async function loadBuildings(): Promise<void> {
    try {
      buildings = await fetchCompletedBuildings()
    } catch (e) {
      toast((e as Error).message)
    }
  }
</script>

<div class="log-browser">
  <Sidebar title="Log Viewer" onback={() => goto('/')}>
    <SidebarList
      title="Buildings"
      items={buildings}
      empty="No completed buildings found."
      onclick={(b) => goto(`/log/${b.id}`)}
    >
      {#snippet item(b)}
        <div class="building-info">
          <span class="building-name">{b.name ?? 'Unnamed'}</span>
          <span class="building-meta">{b.spaces.length} space{b.spaces.length !== 1 ? 's' : ''}</span>
        </div>
      {/snippet}
    </SidebarList>
  </Sidebar>

  <div class="main">
    <div class="placeholder">Select a building to explore logs</div>
  </div>
</div>

<style>
  .log-browser {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .main {
    flex: 1;
    height: 100vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    background: var(--bg);
  }

  .placeholder {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
    font-size: 13px;
  }

  .building-info { display: flex; flex-direction: column; gap: 2px; }
  .building-name { font-size: 13px; font-weight: 500; color: var(--text); }
  .building-meta { font-size: 11px; color: var(--text-muted); }
</style>
