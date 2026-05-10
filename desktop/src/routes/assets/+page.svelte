<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import {
    fetchCompletedBuildings,
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
  import type { AssetWithAnchor, Building, Position, RigidTransform, Space } from '$lib/types'
  import { ASSET_TYPES, ASSET_TYPE_LABELS } from '$lib/assetTypes'
  import { toast } from '$lib/toast'

  type Phase = 'buildings' | 'assets'

  let phase: Phase = $state('buildings')
  let buildings: (Building & { spaces: Space[] })[] = $state([])
  let selectedBuilding: (Building & { spaces: Space[] }) | null = $state(null)
  let assets: AssetWithAnchor[] = $state([])
  let mergedSpaces: { url: string; transform: RigidTransform | null }[] = $state([])

  let selectedAssetId: string | null = $state(null)
  let placingAsset: AssetWithAnchor | null = $state(null)
  let buildingSpaces: Space[] = []

  let showNewDialog = $state(false)
  let newName = $state('')
  let newType = $state('other')
  let saving = $state(false)
  let loadingBuilding = $state(false)

  let mergedSpacesClickable = $derived(!!placingAsset)
  let sceneAnchors = $derived(assets.filter(a => a.anchor?.glb_position).map(a => a.anchor!))
  let selectedAnchorId = $derived(selectedAssetId
    ? (assets.find(a => a.id === selectedAssetId)?.anchor?.id ?? null)
    : null)

  onMount(async () => {
    try {
      buildings = await fetchCompletedBuildings()
    } catch (e) {
      toast((e as Error).message)
    }
  })

  async function selectBuilding(b: Building & { spaces: Space[] }): Promise<void> {
    selectedBuilding = b
    loadingBuilding = true
    try {
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
      phase = 'assets'
    } catch (e) {
      toast((e as Error).message)
    } finally {
      loadingBuilding = false
    }
  }

  async function loadAssets(): Promise<void> {
    if (!selectedBuilding) return
    assets = await fetchAssetsWithAnchors(selectedBuilding.id)
  }

  async function handleCreateAsset(): Promise<void> {
    if (!newName.trim() || !selectedBuilding || saving) return
    saving = true
    try {
      await createAsset({ name: newName, assetType: newType, buildingId: selectedBuilding.id })
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

  async function handleDelete(asset: AssetWithAnchor): Promise<void> {
    if (!confirm(`Delete "${asset.name ?? 'Unnamed'}"? This cannot be undone.`)) return
    try {
      await deleteAsset(asset.id)
      if (asset.anchor_id) await deleteAnchor(asset.anchor_id)
      if (selectedAssetId === asset.id) selectedAssetId = null
      if (placingAsset?.id === asset.id) placingAsset = null
      await loadAssets()
    } catch (e) {
      toast((e as Error).message)
    }
  }

  async function handlePlace(detail: { position: Position; spaceIndex: number | null }): Promise<void> {
    if (!placingAsset || saving) return
    saving = true
    try {
      const { position, spaceIndex } = detail
      if (placingAsset.anchor_id) {
        await setGlbPosition(placingAsset.anchor_id, position)
      } else {
        const spaceId = spaceIndex !== null ? buildingSpaces[spaceIndex]?.id : buildingSpaces[0]?.id
        if (!spaceId) throw new Error('No space found')
        const anchor = await insertAnchor({
          name: placingAsset.name ?? 'Asset',
          glbPosition: position,
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

  function goBack(): void {
    if (phase === 'assets') {
      phase = 'buildings'
      selectedBuilding = null
      assets = []
      mergedSpaces = []
      placingAsset = null
      selectedAssetId = null
    } else {
      goto('/')
    }
  }

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
      if (placingAsset) cancelPlacing()
      else if (showNewDialog) showNewDialog = false
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

{#if phase === 'buildings'}
  <div class="asset-view">
    <Sidebar title="Asset Manager" onback={() => goto('/')}>
      <div class="asset-list">
        {#if loadingBuilding}
          <p class="empty-msg">Loading…</p>
        {:else if buildings.length === 0}
          <p class="empty-msg">No completed buildings found.</p>
        {:else}
          {#each buildings as b (b.id)}
            <button class="building-card" onclick={() => selectBuilding(b)}>
              <span class="building-name">{b.name ?? 'Unnamed Building'}</span>
              <span class="building-meta">{b.spaces.length} space{b.spaces.length !== 1 ? 's' : ''}</span>
            </button>
          {/each}
        {/if}
      </div>
    </Sidebar>
    <div class="scene-wrap empty-scene"></div>
  </div>

{:else}
  <div class="asset-view">
    <Sidebar title={selectedBuilding?.name ?? 'Assets'} onback={goBack}>
      <div class="sidebar-actions">
        <button class="primary new-btn" onclick={() => { showNewDialog = true }}>+ New Asset</button>
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
                  <span class="asset-type">{ASSET_TYPE_LABELS[asset.asset_type ?? ''] ?? asset.asset_type ?? '—'}</span>
                </div>
              </div>
              <div class="asset-actions">
                <button class="delete-btn danger" onclick={(e) => { e.stopPropagation(); handleDelete(asset) }}>✕</button>
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
  </div>

  {#if placingAsset}
    <div class="placement-banner">
      <span class="pulse-dot"></span>
      Click the map to place: <strong>{placingAsset.name ?? 'Unnamed'}</strong>
      <button onclick={cancelPlacing}>Cancel</button>
    </div>
  {/if}
{/if}

{#if showNewDialog}
  <!-- svelte-ignore a11y_click_events_have_key_events -->
  <div class="overlay" onclick={(e) => { if (e.target === e.currentTarget) showNewDialog = false }}>
    <div class="dialog">
      <h3>New Asset</h3>
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
      <div class="dialog-actions">
        <button onclick={() => showNewDialog = false}>Cancel</button>
        <button class="primary" onclick={handleCreateAsset} disabled={saving || !newName.trim()}>
          {saving ? 'Saving…' : 'Create'}
        </button>
      </div>
    </div>
  </div>
{/if}

<style>
  .building-card {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 3px;
    padding: 10px 16px;
    width: 100%;
    border-bottom: 1px solid var(--border);
    background: transparent;
    border-radius: 0;
    border-left: none;
    border-right: none;
    border-top: none;
    cursor: pointer;
    text-align: left;
    transition: background 0.1s;
  }
  .building-card:last-child { border-bottom: none; }
  .building-card:hover { background: #1e1e1e; }

  .building-name {
    font-size: 13px;
    font-weight: 500;
    color: var(--text);
  }

  .building-meta {
    font-size: 11px;
    color: var(--text-muted);
  }

  .empty-scene {
    background: var(--bg);
  }

  .asset-view {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .sidebar-actions {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
  }

  .new-btn {
    width: 100%;
    padding: 8px;
    font-size: 13px;
  }

  .asset-list {
    flex: 1;
    overflow-y: auto;
    padding: 8px 0;
  }

  .empty-msg {
    padding: 16px;
    color: var(--text-muted);
    font-size: 12px;
    font-style: italic;
  }

  .asset-item {
    display: flex;
    flex-direction: row;
    align-items: stretch;
    gap: 8px;
    padding: 10px 16px;
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
    height: 100vh;
    overflow: hidden;
  }

  .placement-banner {
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

  .pulse-dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    flex-shrink: 0;
    animation: pulse 1s infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  .dialog h3 {
    font-size: 15px;
    font-weight: 600;
    margin-bottom: 4px;
    color: var(--text);
  }

  .dialog label {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 11px;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }
</style>
