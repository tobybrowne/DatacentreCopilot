<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import { fetchCompletedBuildings, fetchDraftBuildings, deleteBuilding, getSpaceGlbUrl } from '$lib/supabase'
  import TileGrid from '$lib/TileGrid.svelte'
  import GlbTile from '$lib/GlbTile.svelte'
  import Button from '$lib/Button.svelte'
  import { toast } from '$lib/toast'
  import type { Building, RigidTransform, Space } from '$lib/types'

  let completed: (Building & { spaces: Space[] })[] = $state([])
  let drafts: (Building & { spaces: Space[] })[] = $state([])
  let query = $state('')

  let filteredCompleted = $derived(byQuery(completed))
  let filteredDrafts = $derived(byQuery(drafts))

  function byQuery(list: (Building & { spaces: Space[] })[]) {
    return list.filter(b => (b.name ?? 'Unnamed').toLowerCase().includes(query.toLowerCase()))
  }

  onMount(async () => {
    try {
      ;[completed, drafts] = await Promise.all([fetchCompletedBuildings(), fetchDraftBuildings()])
    } catch (e) {
      toast((e as Error).message)
    }
  })

  // Stitched spaces (with transforms) for a completed building preview.
  async function stitchedParts(b: Building & { spaces: Space[] }) {
    const sorted = [...b.spaces]
      .filter(s => s.glb_path)
      .sort((a, x) => (a.building_index ?? 0) - (x.building_index ?? 0))
    return Promise.all(sorted.map(async s => ({
      url: await getSpaceGlbUrl(s.glb_path!),
      transform: s.offset_transformation as RigidTransform | null,
    })))
  }

  // Drafts aren't fully stitched yet — just preview the first scanned space.
  async function draftParts(b: Building & { spaces: Space[] }) {
    const first = b.spaces.find(s => s.glb_path)
    return first ? [{ url: await getSpaceGlbUrl(first.glb_path!) }] : []
  }

  async function discard(id: string): Promise<void> {
    if (!confirm('Discard this draft building? This cannot be undone.')) return
    try {
      await deleteBuilding(id)
      drafts = drafts.filter(d => d.id !== id)
    } catch (e) {
      toast((e as Error).message)
    }
  }
</script>

<TileGrid title="Building Manager" onback={() => goto('/')} searchable bind:query placeholder="Search buildings…">
  {#snippet actions()}
    <Button variant="primary" onclick={() => goto('/buildings/create')}>+ New building</Button>
  {/snippet}

  {#if filteredDrafts.length > 0}
    <p class="grid-section-label">Drafts <span class="badge">{filteredDrafts.length}</span></p>
    <div class="tile-grid">
      {#each filteredDrafts as draft (draft.id)}
        {@const stitched = draft.spaces.filter(s => s.building_index === 0 || s.offset_transformation !== null).length}
        <GlbTile
          title={draft.name || 'Unnamed'}
          subtitle={`${stitched}/${draft.spaces.length} spaces stitched`}
          thumbKey={`draft:${draft.id}`}
          loadParts={() => draftParts(draft)}
          onclick={() => goto(`/buildings/create?draft=${draft.id}`)}
        >
          {#snippet badge()}<span class="pill draft">Draft</span>{/snippet}
          {#snippet actions()}
            <button class="icon-btn" title="Discard draft" onclick={(e) => { e.stopPropagation(); discard(draft.id) }}>×</button>
          {/snippet}
        </GlbTile>
      {/each}
    </div>
  {/if}

  {#if completed.length > 0}
    <p class="grid-section-label">Buildings <span class="badge">{filteredCompleted.length}</span></p>
  {/if}
  {#if filteredCompleted.length === 0 && filteredDrafts.length === 0}
    <p class="grid-empty">{completed.length === 0 && drafts.length === 0 ? 'No buildings yet.' : 'No buildings match your search.'}</p>
  {:else if filteredCompleted.length > 0}
    <div class="tile-grid">
      {#each filteredCompleted as b (b.id)}
        <GlbTile
          title={b.name || 'Unnamed'}
          subtitle={`${b.spaces?.length ?? 0} spaces`}
          thumbKey={`building:${b.id}`}
          loadParts={() => stitchedParts(b)}
          onclick={() => goto(`/buildings/${b.id}`)}
        />
      {/each}
    </div>
  {/if}
</TileGrid>

<style>
  .pill {
    font-size: 10px;
    font-weight: 600;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    padding: 2px 8px;
    border-radius: 6px;
  }
  .pill.draft { background: var(--pending); color: #000; }

  .icon-btn {
    width: 24px;
    height: 24px;
    padding: 0;
    font-size: 16px;
    line-height: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 6px;
    color: #fff;
    background: rgba(0,0,0,0.5);
    border: 1px solid rgba(255,255,255,0.15);
  }
  .icon-btn:hover { background: var(--danger); border-color: var(--danger); }
</style>
