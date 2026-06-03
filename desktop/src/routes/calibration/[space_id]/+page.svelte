<script lang="ts">
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { onMount } from 'svelte'
  import { fetchAnchors, fetchSpaceById, deleteAnchor, unmapAnchor, setGlbPosition, getSpaceGlbUrl, getAnchorImageUrl, computeBoundingBox } from '$lib/supabase'
  import Scene from '$lib/Scene.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import DetailLayout from '$lib/DetailLayout.svelte'
  import Collapsible from '$lib/Collapsible.svelte'
  import Button from '$lib/Button.svelte'
  import ActionBanner from '$lib/ActionBanner.svelte'
  import { toast } from '$lib/toast'
  import type { Anchor, BoundingBox, Position } from '$lib/types'

  const spaceId = $page.params.space_id!

  let glbUrl: string | null = $state(null)
  let glbPath: string | null = $state(null)
  let spaceName = $state('')
  let boundingBox: BoundingBox | null = $state(null)
  let showBoundingBoxes = $state(false)
  let showDensity = $state(false)
  let anchors: Anchor[] = $state([])
  let selectedId: string | null = $state(null)
  let mappingAnchor: Anchor | null = $state(null)
  let mappingImgUrl: string | null = $state(null)
  let saving = $state(false)

  let showUnmapped = $state(true)
  let showRefs = $state(true)
  let showContent = $state(true)

  // Fetch the reference photo (if any) for the anchor currently being mapped.
  $effect(() => {
    const a = mappingAnchor
    mappingImgUrl = null
    if (a?.img_path) {
      getAnchorImageUrl(a.img_path)
        .then(url => { if (mappingAnchor?.id === a.id) mappingImgUrl = url })
        .catch(() => {})
    }
  })
  let recomputingBbox = $state(false)

  let unmappedRefs = $derived(anchors.filter(a => a.anchor_type === 'reference' && !a.glb_position))
  let mappedRefs   = $derived(anchors.filter(a => a.anchor_type === 'reference' && !!a.glb_position))
  let content      = $derived(anchors.filter(a => a.anchor_type !== 'reference'))
  let draggableAnchorId = $derived(
    (!mappingAnchor && selectedId && anchors.find(a => a.id === selectedId)?.glb_position)
      ? selectedId
      : null
  )

  onMount(async () => {
    try {
      const space = await fetchSpaceById(spaceId)
      spaceName = space.name || spaceId
      if (!space.glb_path) { toast('Space has no GLB export yet', 'info'); return }
      glbPath = space.glb_path
      glbUrl = await getSpaceGlbUrl(space.glb_path)
      boundingBox = space.bounding_box
      await refresh()
    } catch (e) {
      toast((e as Error).message)
    }
  })

  async function refresh(): Promise<void> {
    try {
      anchors = await fetchAnchors(spaceId)
    } catch (e) {
      toast((e as Error).message)
    }
  }

  function handleMeshClick(detail: { position: Position; spaceIndex: number | null }): void {
    if (mappingAnchor) confirmMapping(detail.position)
  }

  async function confirmMapping(position: Position): Promise<void> {
    if (!mappingAnchor || saving) return
    saving = true
    try {
      await setGlbPosition(mappingAnchor.id, position)
      await refresh()
      mappingAnchor = null
    } catch (e) {
      toast((e as Error).message)
    } finally {
      saving = false
    }
  }

  async function handleDelete(id: string): Promise<void> {
    try {
      await deleteAnchor(id)
      if (selectedId === id) selectedId = null
      if (mappingAnchor?.id === id) mappingAnchor = null
      await refresh()
    } catch (e) {
      toast((e as Error).message)
    }
  }

  async function handleUnmap(id: string): Promise<void> {
    try {
      await unmapAnchor(id)
      if (selectedId === id) selectedId = null
      if (mappingAnchor?.id === id) mappingAnchor = null
      await refresh()
    } catch (e) {
      toast((e as Error).message)
    }
  }

  let dragSaveTimer: ReturnType<typeof setTimeout> | null = null

  function handleDragAnchor(id: string, pos: Position): void {
    anchors = anchors.map(a => a.id === id ? { ...a, glb_position: pos } : a)
    if (dragSaveTimer) clearTimeout(dragSaveTimer)
    dragSaveTimer = setTimeout(async () => {
      try {
        await setGlbPosition(id, pos)
      } catch (e) {
        toast((e as Error).message)
      }
    }, 600)
  }

  async function handleRecomputeBbox(): Promise<void> {
    if (recomputingBbox) return
    recomputingBbox = true
    try {
      await computeBoundingBox(spaceId)
      toast('Bounding box recompute started', 'success')
    } catch (e) {
      toast((e as Error).message)
    } finally {
      recomputingBbox = false
    }
  }

  function cancel(): void {
    mappingAnchor = null
  }

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') cancel()
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<DetailLayout title={spaceName || 'Space Calibration'} onback={() => goto('/calibration')}>
<Sidebar>
  <section>
    {#if boundingBox}
      <Button style="width:100%;margin-bottom:6px" onclick={() => showBoundingBoxes = !showBoundingBoxes}>
        {showBoundingBoxes ? 'Hide boxes' : 'Show boxes'}
      </Button>
    {/if}
    <Button style="width:100%;margin-bottom:6px" onclick={handleRecomputeBbox} disabled={recomputingBbox}>
      {recomputingBbox ? 'Starting…' : 'Recompute bounding box'}
    </Button>
    {#if glbUrl}
      <Button style="width:100%" onclick={() => showDensity = !showDensity}>
        {showDensity ? 'Hide density map' : 'Show density map'}
      </Button>
    {/if}
  </section>

  {#if unmappedRefs.length > 0}
    <Collapsible title="Unmapped ref anchors" count={unmappedRefs.length} bind:open={showUnmapped} labelClass="warning" badgeClass="warning">
      <ul class="unmapped-list">
        {#each unmappedRefs as anchor (anchor.id)}
          <li class:mapping={mappingAnchor?.id === anchor.id}>
            <span class="anchor-name">{anchor.name || 'Unnamed'}</span>
            {#if mappingAnchor?.id === anchor.id}
              <button class="map-btn active" onclick={cancel}>Cancel</button>
            {:else}
              <button class="map-btn" onclick={() => { mappingAnchor = anchor; selectedId = anchor.id }}>Map</button>
            {/if}
          </li>
        {/each}
      </ul>
    </Collapsible>
  {/if}

  <Collapsible title="Reference anchors" count={mappedRefs.length} bind:open={showRefs}>
    {#if mappedRefs.length === 0}
      <p class="empty-msg">None mapped yet.</p>
    {:else}
      <ul class="anchor-list">
        {#each mappedRefs as anchor (anchor.id)}
          <li
            class:selected={anchor.id === selectedId}
            onclick={() => selectedId = anchor.id}
          >
            <div class="anchor-row">
              <span class="anchor-name">{anchor.name || 'Unnamed'}</span>
              <span class="tag ref">ref</span>
            </div>
            {#if anchor.glb_position}
              <span class="coords">
                {anchor.glb_position.x.toFixed(2)},
                {anchor.glb_position.y.toFixed(2)},
                {anchor.glb_position.z.toFixed(2)}
              </span>
            {/if}
            <button
              class="delete-btn"
              onclick={(e) => { e.stopPropagation(); handleUnmap(anchor.id) }}
            >Unmap</button>
          </li>
        {/each}
      </ul>
    {/if}
  </Collapsible>

  <Collapsible title="Content anchors" count={content.length} bind:open={showContent}>
    {#if content.length === 0}
      <p class="empty-msg">None placed.</p>
    {:else}
      <ul class="anchor-list">
        {#each content as anchor (anchor.id)}
          <li
            class:selected={anchor.id === selectedId}
            class:no-position={!anchor.glb_position}
            onclick={() => selectedId = anchor.id}
          >
            <div class="anchor-row">
              <span class="anchor-name">{anchor.name || 'Unnamed'}</span>
              <span class="tag {anchor.ml2_id ? 'headset' : 'desktop'}">{anchor.ml2_id ? 'headset' : 'desktop'}</span>
            </div>
            {#if anchor.glb_position}
              <span class="coords">
                {anchor.glb_position.x.toFixed(2)},
                {anchor.glb_position.y.toFixed(2)},
                {anchor.glb_position.z.toFixed(2)}
              </span>
            {:else}
              <span class="coords muted">no glb position</span>
            {/if}
            <button
              class="delete-btn danger"
              onclick={(e) => { e.stopPropagation(); handleDelete(anchor.id) }}
            >✕</button>
          </li>
        {/each}
      </ul>
    {/if}
  </Collapsible>
</Sidebar>

<Scene
  {glbUrl}
  {anchors}
  {selectedId}
  {mappingAnchor}
  {boundingBox}
  {showBoundingBoxes}
  {showDensity}
  {draggableAnchorId}
  canExport
  exportName={`${spaceName || spaceId}-calibration`}
  onplace={handleMeshClick}
  onselect={(id) => selectedId = id}
  ondraganchor={handleDragAnchor}
/>
</DetailLayout>

{#if mappingAnchor}
  <ActionBanner prompt="Click the mesh to map:" name={mappingAnchor.name || 'Unnamed'} oncancel={cancel} />
  {#if mappingImgUrl}
    <div class="map-photo">
      <img src={mappingImgUrl} alt="Reference photo for {mappingAnchor.name || 'anchor'}" />
    </div>
  {/if}
{/if}

<style>
  .map-photo {
    position: fixed;
    right: 16px;
    top: 16px;
    width: 400px;
    background: var(--panel, #1a1a1a);
    border: 1px solid var(--accent, #00d4ff);
    border-radius: 6px;
    padding: 6px;
    box-shadow: 0 4px 16px rgba(0, 0, 0, 0.4);
    z-index: 20;
  }
  .map-photo img {
    width: 100%;
    height: auto;
    border-radius: 4px;
    display: block;
  }

  .unmapped-list { list-style: none; display: flex; flex-direction: column; gap: 4px; margin: 0 -24px; }


  .tag {
    font-size: 10px;
    padding: 1px 5px;
    border-radius: 3px;
    text-transform: uppercase;
    letter-spacing: 0.05em;
    background: var(--border);
    color: var(--text-muted);
  }
  .tag.ref { background: #00d4ff22; color: var(--accent); }
  .tag.desktop { background: #88ff8822; color: #88ff88; }

  .anchor-list { list-style: none; margin: 0 -24px; }

  li {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px 24px;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    position: relative;
    transition: background 0.1s;
  }
  li:last-child { border-bottom: none; }
  li:hover { background: #202020; }
  li.selected { background: var(--accent-dim); }
  li.no-position { opacity: 0.5; }
  li.mapping { background: #00d4ff11; outline: 1px solid var(--accent); border-radius: 4px; }

  .anchor-row {
    display: flex;
    align-items: center;
    gap: 6px;
    padding-right: 24px;
  }

  .anchor-name { font-weight: 500; font-size: 13px; }

  .coords { font-family: monospace; font-size: 11px; color: var(--text-muted); }
  .coords.muted { font-style: italic; }

  .delete-btn {
    position: absolute;
    right: 0;
    top: 50%;
    transform: translateY(-50%);
    padding: 2px 6px;
    font-size: 11px;
    border-radius: 4px;
    opacity: 0;
    transition: opacity 0.15s;
    border-color: var(--text-muted);
    color: var(--text-muted);
  }
  li:hover .delete-btn { opacity: 1; }

  .map-btn {
    padding: 3px 10px;
    font-size: 11px;
    border-radius: 4px;
    border-color: var(--accent);
    color: var(--accent);
    align-self: flex-start;
  }
  .map-btn.active { background: var(--accent); color: #000; }

  .empty-msg { color: var(--text-muted); font-size: 12px; font-style: italic; }
</style>
