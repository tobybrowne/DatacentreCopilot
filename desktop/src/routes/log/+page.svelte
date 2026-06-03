<script lang="ts">
  import { goto } from '$app/navigation'
  import { fetchCompletedBuildings, getSpaceGlbUrl } from '$lib/supabase'
  import TileGrid from '$lib/TileGrid.svelte'
  import GlbTile from '$lib/GlbTile.svelte'
  import { toast } from '$lib/toast'
  import type { Building, RigidTransform, Space } from '$lib/types'

  let buildings: (Building & { spaces: Space[] })[] = $state([])
  let query = $state('')

  let filtered = $derived(
    buildings.filter(b => (b.name ?? 'Unnamed').toLowerCase().includes(query.toLowerCase()))
  )

  loadBuildings()

  async function loadBuildings(): Promise<void> {
    try {
      buildings = await fetchCompletedBuildings()
    } catch (e) {
      toast((e as Error).message)
    }
  }

  async function stitchedParts(b: Building & { spaces: Space[] }) {
    const sorted = [...b.spaces]
      .filter(s => s.glb_path)
      .sort((a, x) => (a.building_index ?? 0) - (x.building_index ?? 0))
    return Promise.all(sorted.map(async s => ({
      url: await getSpaceGlbUrl(s.glb_path!),
      transform: s.offset_transformation as RigidTransform | null,
    })))
  }
</script>

<TileGrid title="Log Viewer" onback={() => goto('/')} searchable bind:query placeholder="Search buildings…">
  {#if filtered.length === 0}
    <p class="grid-empty">{buildings.length === 0 ? 'No completed buildings found.' : 'No buildings match your search.'}</p>
  {:else}
    <div class="tile-grid">
      {#each filtered as b (b.id)}
        <GlbTile
          title={b.name ?? 'Unnamed'}
          subtitle={`${b.spaces.length} spaces`}
          thumbKey={`building:${b.id}`}
          loadParts={() => stitchedParts(b)}
          onclick={() => goto(`/log/${b.id}`)}
        />
      {/each}
    </div>
  {/if}
</TileGrid>
