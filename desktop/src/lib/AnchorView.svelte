<script lang="ts">
  import { onMount, onDestroy } from 'svelte'
  import { fetchAnchors, insertAnchor, deleteAnchor, setGlbPosition, fetchUserPosition, subscribeUserPosition, fetchSpaces, getSpaceGlbUrl } from './supabase'
  import Scene from './Scene.svelte'
  import Sidebar from './Sidebar.svelte'
  import type { Anchor, Position, Space } from './types'
  import { createEventDispatcher } from 'svelte'

  const dispatch = createEventDispatcher<{ back: void }>()

  const DEMO_USER_ID = '00000000-0000-0000-0000-000000000000'

  let glbUrl: string | null = null
  let anchors: Anchor[] = []
  let selectedId: string | null = null
  let pendingPosition: Position | null = null
  let mappingAnchor: Anchor | null = null
  let newAnchorName = ''
  let saving = false
  let error: string | null = null

  let monitoring = false
  let userPosition: Position | null = null
  let unsubscribeUser: (() => void) | null = null

  let spaces: Space[] = []
  let selectedSpaceId: string | null = null

  $: unmappedRefs = anchors.filter(a => a.is_reference && !a.glb_position)

  onMount(async () => {
    await Promise.all([refresh(), loadSpaces()])
  })

  onDestroy(() => {
    if (unsubscribeUser) unsubscribeUser()
  })

  async function refresh(): Promise<void> {
    try {
      anchors = await fetchAnchors(selectedSpaceId)
    } catch (e) {
      error = (e as Error).message
    }
  }

  async function loadSpaces(): Promise<void> {
    try {
      spaces = await fetchSpaces()
    } catch (e) {
      error = (e as Error).message
    }
  }

  async function selectSpace(space: Space): Promise<void> {
    selectedSpaceId = space.id
    glbUrl = null
    try {
      glbUrl = getSpaceGlbUrl(space.glb_path!)
      await refresh()
    } catch (e) {
      error = (e as Error).message
    }
  }

  async function startMonitoring(): Promise<void> {
    monitoring = true
    try {
      userPosition = await fetchUserPosition(DEMO_USER_ID)
    } catch (e) {
      error = (e as Error).message
    }
    unsubscribeUser = subscribeUserPosition(DEMO_USER_ID, (pos) => { userPosition = pos })
  }

  function stopMonitoring(): void {
    monitoring = false
    userPosition = null
    if (unsubscribeUser) { unsubscribeUser(); unsubscribeUser = null }
  }

  function handleMeshClick({ detail: position }: CustomEvent<Position>): void {
    if (mappingAnchor) {
      confirmMapping(position)
    } else {
      pendingPosition = position
      newAnchorName = ''
    }
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

  async function confirmPlacement(): Promise<void> {
    if (!pendingPosition || saving) return
    saving = true
    try {
      await insertAnchor({ name: newAnchorName, glbPosition: pendingPosition, spaceId: selectedSpaceId! })
      await refresh()
      pendingPosition = null
    } catch (e) {
      error = (e as Error).message
    } finally {
      saving = false
    }
  }

  async function handleDelete(e: CustomEvent<string>): Promise<void> {
    try {
      await deleteAnchor(e.detail)
      if (selectedId === e.detail) selectedId = null
      if (mappingAnchor?.id === e.detail) mappingAnchor = null
      await refresh()
    } catch (e) {
      error = (e as Error).message
    }
  }

  function cancel(): void {
    pendingPosition = null
    mappingAnchor = null
  }

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') cancel()
    if (e.key === 'Enter' && pendingPosition) confirmPlacement()
  }
</script>

<svelte:window on:keydown={handleKeydown} />

<Sidebar
  {anchors}
  {selectedId}
  {mappingAnchor}
  {monitoring}
  {spaces}
  {selectedSpaceId}
  on:back={() => dispatch('back')}
  on:selectspace={(e) => selectSpace(e.detail)}
  on:select={(e) => selectedId = e.detail}
  on:delete={handleDelete}
  on:startmapping={(e) => { mappingAnchor = e.detail; selectedId = e.detail.id }}
  on:cancelmapping={cancel}
  on:togglemonitor={() => monitoring ? stopMonitoring() : startMonitoring()}
/>

<Scene
  {glbUrl}
  {anchors}
  {selectedId}
  {pendingPosition}
  {mappingAnchor}
  {userPosition}
  on:place={handleMeshClick}
  on:select={(e) => selectedId = e.detail}
/>

{#if mappingAnchor}
  <div class="mapping-banner">
    <span class="dot" />
    Click the mesh to map: <strong>{mappingAnchor.name || 'Unnamed'}</strong>
    <button on:click={cancel}>Cancel</button>
  </div>
{/if}

{#if unmappedRefs.length > 0 && !mappingAnchor && glbUrl}
  <div class="unmapped-notice">
    {unmappedRefs.length} reference anchor{unmappedRefs.length > 1 ? 's' : ''} not yet mapped to the mesh.
  </div>
{/if}

{#if pendingPosition}
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <div class="overlay" on:click|self={cancel}>
    <div class="dialog">
      <h3>Place content anchor</h3>
      <p class="coords">
        x: {pendingPosition.x.toFixed(3)}
        y: {pendingPosition.y.toFixed(3)}
        z: {pendingPosition.z.toFixed(3)}
      </p>
      <input type="text" bind:value={newAnchorName} placeholder="Anchor name (optional)" autofocus />
      <div class="dialog-actions">
        <button on:click={cancel}>Cancel</button>
        <button class="primary" on:click={confirmPlacement} disabled={saving || !selectedSpaceId}>
          {saving ? 'Saving…' : 'Place'}
        </button>
        {#if !selectedSpaceId}<p class="warn">Select a space first</p>{/if}
      </div>
    </div>
  </div>
{/if}

{#if error}
  <div class="error-toast" on:click={() => error = null}>{error}</div>
{/if}

<style>
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

  .error-toast {
    position: fixed;
    bottom: 20px;
    right: 20px;
    background: #ff444488;
    border: 1px solid var(--danger);
    border-radius: 8px;
    padding: 10px 16px;
    font-size: 13px;
    cursor: pointer;
    z-index: 200;
    max-width: 360px;
  }
</style>
