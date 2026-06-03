<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import { fetchSpaces, fetchBuildingNames, getSpaceGlbUrl } from '$lib/supabase'
  import TileGrid from '$lib/TileGrid.svelte'
  import GlbTile from '$lib/GlbTile.svelte'
  import { toast } from '$lib/toast'
  import type { Space } from '$lib/types'

  let spaces: Space[] = $state([])
  let buildingNames: Map<string, string> = $state(new Map())
  let query = $state('')

  const UNASSIGNED = ' unassigned'

  let filtered = $derived(
    spaces.filter(s => (s.name ?? s.id).toLowerCase().includes(query.toLowerCase()))
  )

  // Spaces divided into sections by building.
  let sections = $derived.by(() => {
    const groups = new Map<string, Space[]>()
    for (const s of filtered) {
      const key = s.building_id ?? UNASSIGNED
      ;(groups.get(key) ?? groups.set(key, []).get(key)!).push(s)
    }
    return [...groups.entries()]
      .map(([key, items]) => ({
        key,
        label: key === UNASSIGNED ? 'Unassigned' : (buildingNames.get(key) ?? 'Unknown building'),
        items: items.sort((a, b) =>
          (a.building_index ?? 0) - (b.building_index ?? 0) ||
          (a.name ?? '').localeCompare(b.name ?? '')),
      }))
      .sort((a, b) => {
        if (a.key === UNASSIGNED) return 1
        if (b.key === UNASSIGNED) return -1
        return a.label.localeCompare(b.label)
      })
  })

  onMount(async () => {
    try {
      ;[spaces, buildingNames] = await Promise.all([fetchSpaces(), fetchBuildingNames()])
    } catch (e) {
      toast((e as Error).message)
    }
  })
</script>

<TileGrid title="Space Calibration" onback={() => goto('/')} searchable bind:query placeholder="Search spaces…">
  {#if filtered.length === 0}
    <p class="grid-empty">{spaces.length === 0 ? 'No spaces found.' : 'No spaces match your search.'}</p>
  {:else}
    {#each sections as section (section.key)}
      <p class="grid-section-label">{section.label} <span class="badge">{section.items.length}</span></p>
      <div class="tile-grid">
        {#each section.items as space (space.id)}
          <GlbTile
            title={space.name || space.id}
            subtitle={space.glb_path ? undefined : 'No GLB exported yet'}
            thumbKey={`space:${space.id}`}
            disabled={!space.glb_path}
            loadParts={async () => space.glb_path ? [{ url: await getSpaceGlbUrl(space.glb_path) }] : []}
            onclick={() => goto(`/calibration/${space.id}`)}
          />
        {/each}
      </div>
    {/each}
  {/if}
</TileGrid>
