<script lang="ts">
  import { goto } from '$app/navigation'
  import { page } from '$app/stores'
  import { onMount } from 'svelte'
  import {
    fetchBuildingById,
    fetchAssetsWithAnchors,
    createAsset,
    deleteAsset,
    deleteAnchor,
    setAssetAnchor,
    insertAnchor,
    setGlbPosition,
    getSpaceGlbUrl,
  } from '$lib/supabase'
  import Scene from '$lib/Scene.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import DetailLayout from '$lib/DetailLayout.svelte'
  import Modal from '$lib/Modal.svelte'
  import Button from '$lib/Button.svelte'
  import ActionBanner from '$lib/ActionBanner.svelte'
  import type { AssetWithAnchor, Building, Position, RigidTransform, Space } from '$lib/types'
  import { ASSET_TYPES, ASSET_TYPE_LABELS } from '$lib/assetTypes'
  import { toast } from '$lib/toast'

  const buildingId = $page.params.id!

  let building: (Building & { spaces: Space[] }) | null = $state(null)
  let assets: AssetWithAnchor[] = $state([])
  let mergedSpaces: { url: string; transform: RigidTransform | null }[] = $state([])

  let selectedAssetId: string | null = $state(null)
  let placingAsset: AssetWithAnchor | null = $state(null)
  let buildingSpaces: Space[] = []

  let showNewDialog = $state(false)
  let assetToDelete: AssetWithAnchor | null = $state(null)
  let deleting = $state(false)
  let newName = $state('')
  let newType = $state('other')
  let saving = $state(false)

  let mergedSpacesClickable = $derived(!!placingAsset)
  let sceneAnchors = $derived(assets.filter(a => a.anchor?.glb_position).map(a => {
    const anchor = a.anchor!
    const space = buildingSpaces.find(s => s.id === anchor.space_id)
    const worldPosition = glbToWorld(anchor.glb_position!, space?.offset_transformation ?? null)
    return { ...anchor, glb_position: worldPosition }
  }))
  let selectedAnchorId = $derived(selectedAssetId
    ? (assets.find(a => a.id === selectedAssetId)?.anchor?.id ?? null)
    : null)

  onMount(async () => {
    try {
      const b = await fetchBuildingById(buildingId)
      building = b
      const sorted = [...b.spaces]
        .filter(s => s.glb_path)
        .sort((a, x) => (a.building_index ?? 0) - (x.building_index ?? 0))
      buildingSpaces = sorted
      mergedSpaces = await Promise.all(
        sorted.map(async s => ({
          url: await getSpaceGlbUrl(s.glb_path!),
          transform: s.offset_transformation as RigidTransform | null,
        }))
      )
      await loadAssets()
    } catch (e) {
      toast((e as Error).message)
    }
  })

  async function loadAssets(): Promise<void> {
    assets = await fetchAssetsWithAnchors(buildingId)
  }

  async function handleCreateAsset(): Promise<void> {
    if (!newName.trim() || saving) return
    saving = true
    try {
      await createAsset({ name: newName, assetType: newType, buildingId })
      await loadAssets()
      showNewDialog = false
      newName = ''
      newType = 'other'
    } catch (e) {
      toast((e as Error).message)
    } finally {
      saving = false
    }
  }

  async function confirmDelete(): Promise<void> {
    const asset = assetToDelete
    if (!asset || deleting) return
    deleting = true
    try {
      await deleteAsset(asset.id)
      if (asset.anchor_id) await deleteAnchor(asset.anchor_id)
      if (selectedAssetId === asset.id) selectedAssetId = null
      if (placingAsset?.id === asset.id) placingAsset = null
      await loadAssets()
      assetToDelete = null
    } catch (e) {
      toast((e as Error).message)
    } finally {
      deleting = false
    }
  }

  // e.point from TransformedGltf is in scene world space (offset_transformation applied).
  // Invert the space transform to recover raw GLB coordinates expected by the headset.
  function worldToGlb(position: Position, transform: RigidTransform | null): Position {
    if (!transform) return position
    const q = transform.quaternion
    const iq = { x: -q.x, y: -q.y, z: -q.z, w: q.w }
    const t = { x: position.x - transform.position.x, y: position.y - transform.position.y, z: position.z - transform.position.z }
    const rx = (1 - 2*(iq.y*iq.y + iq.z*iq.z))*t.x + 2*(iq.x*iq.y - iq.z*iq.w)*t.y + 2*(iq.x*iq.z + iq.y*iq.w)*t.z
    const ry = 2*(iq.x*iq.y + iq.z*iq.w)*t.x + (1 - 2*(iq.x*iq.x + iq.z*iq.z))*t.y + 2*(iq.y*iq.z - iq.x*iq.w)*t.z
    const rz = 2*(iq.x*iq.z - iq.y*iq.w)*t.x + 2*(iq.y*iq.z + iq.x*iq.w)*t.y + (1 - 2*(iq.x*iq.x + iq.y*iq.y))*t.z
    return { x: rx, y: ry, z: rz }
  }

  // Apply the space transform to a raw GLB position to get scene world-space position.
  function glbToWorld(position: Position, transform: RigidTransform | null): Position {
    if (!transform) return position
    const q = transform.quaternion
    const rx = (1 - 2*(q.y*q.y + q.z*q.z))*position.x + 2*(q.x*q.y - q.z*q.w)*position.y + 2*(q.x*q.z + q.y*q.w)*position.z
    const ry = 2*(q.x*q.y + q.z*q.w)*position.x + (1 - 2*(q.x*q.x + q.z*q.z))*position.y + 2*(q.y*q.z - q.x*q.w)*position.z
    const rz = 2*(q.x*q.z - q.y*q.w)*position.x + 2*(q.y*q.z + q.x*q.w)*position.y + (1 - 2*(q.x*q.x + q.y*q.y))*position.z
    return { x: rx + transform.position.x, y: ry + transform.position.y, z: rz + transform.position.z }
  }

  async function handlePlace(detail: { position: Position; spaceIndex: number | null }): Promise<void> {
    if (!placingAsset || saving) return
    saving = true
    try {
      const { position, spaceIndex } = detail
      const spaceIdx = spaceIndex ?? 0
      const space = buildingSpaces[spaceIdx]
      const glbPosition = worldToGlb(position, space?.offset_transformation ?? null)
      if (placingAsset.anchor_id) {
        await setGlbPosition(placingAsset.anchor_id, glbPosition)
      } else {
        const spaceId = space?.id
        if (!spaceId) throw new Error('No space found')
        const anchor = await insertAnchor({
          name: placingAsset.name ?? 'Asset',
          glbPosition,
          spaceId,
          anchorType: 'asset',
        })
        await setAssetAnchor(placingAsset.id, anchor.id)
      }
      await loadAssets()
      placingAsset = null
    } catch (e) {
      toast((e as Error).message)
    } finally {
      saving = false
    }
  }

  function startPlacing(asset: AssetWithAnchor): void {
    placingAsset = asset
    selectedAssetId = asset.id
  }

  function cancelPlacing(): void {
    placingAsset = null
  }

  function handleKeydown(e: KeyboardEvent): void {
    // Open modals handle their own Escape; only the placement banner needs this.
    if (e.key === 'Escape' && placingAsset && !showNewDialog && !assetToDelete) cancelPlacing()
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<DetailLayout title={building?.name ?? 'Assets'} onback={() => goto('/assets')}>
  <Sidebar>
    <div class="sidebar-actions">
      <Button variant="primary" style="width:100%" onclick={() => { showNewDialog = true }}>+ New Asset</Button>
    </div>

    <div class="asset-list">
      {#if assets.length === 0}
        <p class="empty-msg">No assets yet. Create one above.</p>
      {:else}
        {#each assets as asset (asset.id)}
          <div
            class="asset-item"
            class:selected={selectedAssetId === asset.id}
            class:placing={placingAsset?.id === asset.id}
            onclick={() => selectedAssetId = asset.id}
          >
            <div class="asset-main">
              <span class="asset-status" class:placed={!!asset.anchor?.glb_position} title={asset.anchor?.glb_position ? 'Placed on map' : 'Not placed'}>●</span>
              <div class="asset-info">
                <span class="asset-name">{asset.name ?? 'Unnamed'}</span>
                <span class="asset-type">{ASSET_TYPE_LABELS[asset.asset_type ?? ''] ?? asset.asset_type ?? '-'}</span>
                {#if asset.anchor?.space_id}
                  <span class="asset-space">{building?.spaces.find(s => s.id === asset.anchor!.space_id)?.name ?? '-'}</span>
                {/if}
              </div>
            </div>
            <div class="asset-actions">
              <button class="delete-btn danger" onclick={(e) => { e.stopPropagation(); assetToDelete = asset }}>✕</button>
              <button
                class="place-btn"
                class:active={placingAsset?.id === asset.id}
                onclick={(e) => { e.stopPropagation(); placingAsset?.id === asset.id ? cancelPlacing() : startPlacing(asset) }}
              >
                {placingAsset?.id === asset.id ? 'Cancel' : asset.anchor_id ? 'Re-place' : 'Place'}
              </button>
            </div>
          </div>
        {/each}
      {/if}
    </div>
  </Sidebar>

  <div class="scene-wrap">
    <Scene
      {mergedSpaces}
      {mergedSpacesClickable}
      anchors={sceneAnchors}
      selectedId={selectedAnchorId}
      onplace={handlePlace}
    />
  </div>
</DetailLayout>

{#if placingAsset}
  <ActionBanner prompt="Click the map to place:" name={placingAsset.name ?? 'Unnamed'} oncancel={cancelPlacing} />
{/if}

{#if showNewDialog}
  <Modal title="New Asset" onclose={() => showNewDialog = false}>
    <label>
      Name
      <input type="text" bind:value={newName} placeholder="e.g. UPS-01" autofocus />
    </label>
    <label>
      Type
      <select bind:value={newType}>
        {#each ASSET_TYPES as t}
          <option value={t}>{ASSET_TYPE_LABELS[t]}</option>
        {/each}
      </select>
    </label>
    {#snippet actions()}
      <Button onclick={() => showNewDialog = false}>Cancel</Button>
      <Button variant="primary" onclick={handleCreateAsset} disabled={saving || !newName.trim()}>
        {saving ? 'Saving…' : 'Create'}
      </Button>
    {/snippet}
  </Modal>
{/if}

{#if assetToDelete}
  <Modal title="Delete asset" dismissable={!deleting} onclose={() => assetToDelete = null}>
    <p class="confirm-text">Delete <strong>{assetToDelete.name ?? 'Unnamed'}</strong>? This cannot be undone.</p>
    {#snippet actions()}
      <Button onclick={() => assetToDelete = null} disabled={deleting}>Cancel</Button>
      <Button variant="danger" onclick={confirmDelete} disabled={deleting}>
        {deleting ? 'Deleting…' : 'Delete'}
      </Button>
    {/snippet}
  </Modal>
{/if}

<style>
  .sidebar-actions {
    padding: 12px 24px;
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .asset-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px 0;
  }

  .empty-msg {
    padding: 16px 24px;
    color: var(--text-muted);
    font-size: 12px;
    font-style: italic;
  }

  .asset-item {
    display: flex;
    flex-direction: row;
    align-items: stretch;
    gap: 8px;
    padding: 10px 24px;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    transition: background 0.1s;
  }
  .asset-item:hover { background: #1e1e1e; }
  .asset-item.selected { background: var(--accent-dim); }
  .asset-item.placing { background: #00d4ff11; outline: 1px solid var(--accent); }

  .asset-main {
    display: flex;
    align-items: center;
    gap: 10px;
    flex: 1;
    min-width: 0;
  }

  .asset-status {
    font-size: 10px;
    color: var(--text-muted);
    flex-shrink: 0;
  }
  .asset-status.placed { color: #44cc66; }

  .asset-info {
    display: flex;
    flex-direction: column;
    gap: 2px;
    flex: 1;
    min-width: 0;
  }

  .asset-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .asset-type {
    font-size: 11px;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.04em;
  }

  .asset-space {
    font-size: 11px;
    color: var(--text-muted);
    opacity: 0.7;
  }

  .asset-actions {
    display: flex;
    flex-direction: column;
    gap: 4px;
    align-items: flex-end;
    justify-content: center;
    flex-shrink: 0;
  }

  .place-btn {
    padding: 3px 10px;
    font-size: 11px;
    border-radius: 4px;
    border: 1px solid var(--accent);
    color: var(--accent);
    background: transparent;
    cursor: pointer;
    transition: background 0.15s, color 0.15s;
    flex-shrink: 0;
  }
  .place-btn:hover { background: var(--accent-dim); }
  .place-btn.active { background: var(--accent); color: #000; }

  .delete-btn {
    padding: 3px 7px;
    font-size: 11px;
    border-radius: 4px;
    flex-shrink: 0;
  }

  select {
    padding: 5px 8px;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--bg);
    color: var(--text);
    font-size: 12px;
    outline: none;
    width: 100%;
  }
  select:focus { border-color: var(--accent); }

  .scene-wrap {
    flex: 1;
    height: 100%;
    overflow: hidden;
  }

  .confirm-text {
    font-size: 13px;
    color: var(--text-muted);
    line-height: 1.5;
  }
  .confirm-text strong { color: var(--text); }
</style>
