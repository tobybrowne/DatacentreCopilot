<script lang="ts">
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { onMount } from 'svelte'
  import { fetchAnchors, fetchSpaceById, deleteAnchor, setGlbPosition, getSpaceGlbUrl } from '$lib/supabase'
  import Scene from '$lib/Scene.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import type { Anchor, BoundingBox, Position } from '$lib/types'

  const spaceId = $page.params.space_id!

  let glbUrl: string | null = $state(null)
  let boundingBox: BoundingBox | null = $state(null)
  let showBoundingBoxes = $state(false)
  let anchors: Anchor[] = $state([])
  let selectedId: string | null = $state(null)
  let mappingAnchor: Anchor | null = $state(null)
  let saving = $state(false)
  let error: string | null = $state(null)

  let unmappedRefs = $derived(anchors.filter(a => a.anchor_type === 'reference' && !a.glb_position))
  let mappedRefs   = $derived(anchors.filter(a => a.anchor_type === 'reference' && !!a.glb_position))
  let content      = $derived(anchors.filter(a => a.anchor_type !== 'reference'))

  onMount(async () => {
    try {
      const space = await fetchSpaceById(spaceId)
      if (!space.glb_path) { error = 'Space has no GLB export yet'; return }
      glbUrl = await getSpaceGlbUrl(space.glb_path)
      boundingBox = space.bounding_box
      await refresh()
    } catch (e) {
      error = (e as Error).message
    }
  })

  async function refresh(): Promise<void> {
    try {
      anchors = await fetchAnchors(spaceId)
    } catch (e) {
      error = (e as Error).message
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
      error = (e as Error).message
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
      error = (e as Error).message
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

<Sidebar title="Space Calibration" onback={() => goto('/calibration')}>
  {#if unmappedRefs.length > 0}
    <section class="unmapped-section">
      <label class="section-label warning">
        Unmapped reference anchors
        <span class="badge warning">{unmappedRefs.length}</span>
      </label>
      <p class="hint-text">These anchors exist on the headset but haven't been located in the mesh yet. Click "Map" then click their physical location in the 3D view.</p>
      <ul>
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
    </section>
  {/if}

  <section>
    <label class="section-label">
      Reference anchors
      <span class="badge">{mappedRefs.length}</span>
    </label>
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
              class="delete-btn danger"
              onclick={(e) => { e.stopPropagation(); handleDelete(anchor.id) }}
            >✕</button>
          </li>
        {/each}
      </ul>
    {/if}
  </section>

  <section>
    <label class="section-label">
      Content anchors
      <span class="badge">{content.length}</span>
    </label>
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
  </section>

  {#if boundingBox}
    <section>
      <button style="width:100%" onclick={() => showBoundingBoxes = !showBoundingBoxes}>
        {showBoundingBoxes ? 'Hide boxes' : 'Show boxes'}
      </button>
    </section>
  {/if}
</Sidebar>

<Scene
  {glbUrl}
  {anchors}
  {selectedId}
  {mappingAnchor}
  {boundingBox}
  {showBoundingBoxes}
  onplace={handleMeshClick}
  onselect={(id) => selectedId = id}
/>

{#if mappingAnchor}
  <div class="mapping-banner">
    <span class="dot"></span>
    Click the mesh to map: <strong>{mappingAnchor.name || 'Unnamed'}</strong>
    <button onclick={cancel}>Cancel</button>
  </div>
{/if}

{#if unmappedRefs.length > 0 && !mappingAnchor && glbUrl}
  <div class="unmapped-notice">
    {unmappedRefs.length} reference anchor{unmappedRefs.length > 1 ? 's' : ''} not yet mapped to the mesh.
  </div>
{/if}

{#if error}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="error-toast" onclick={() => error = null}>{error}</div>
{/if}

<style>
  .unmapped-section {
    background: #ffcc0009;
    border-bottom: 1px solid #ffcc0044 !important;
  }
  .unmapped-section ul { list-style: none; display: flex; flex-direction: column; gap: 4px; }

  .section-label.warning { color: var(--pending); }

  .badge {
    background: var(--accent-dim);
    color: var(--accent);
    border-radius: 10px;
    padding: 1px 7px;
    font-size: 11px;
  }
  .badge.warning { background: #ffcc0022; color: var(--pending); }

  .hint-text { font-size: 11px; color: var(--text-muted); line-height: 1.5; }

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

  .anchor-list { list-style: none; }

  li {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 8px 0;
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

  .mapping-banner {
    position: fixed;
    top: 16px;
    left: 50%;
    transform: translateX(-50%);
    background: var(--surface);
    border: 1px solid var(--accent);
    border-radius: 8px;
    padding: 10px 16px;
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    z-index: 50;
    box-shadow: 0 0 20px #00d4ff33;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    animation: pulse 1s infinite;
    flex-shrink: 0;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  .unmapped-notice {
    position: fixed;
    top: 16px;
    left: 50%;
    transform: translateX(-50%);
    background: #ffcc0022;
    border: 1px solid var(--pending);
    border-radius: 8px;
    padding: 8px 16px;
    font-size: 12px;
    color: var(--pending);
    z-index: 50;
  }
</style>
