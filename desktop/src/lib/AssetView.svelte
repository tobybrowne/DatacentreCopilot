<script lang="ts">
  import { onMount, createEventDispatcher } from 'svelte'
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
  } from './supabase'
  import Scene from './Scene.svelte'
  import type { AssetWithAnchor, Building, Position, RigidTransform, Space } from './types'

  const dispatch = createEventDispatcher<{ back: void }>()

  const ASSET_TYPES = [
    'humidifier', 'ats', 'ups', 'pdu', 'generator', 'sts', 'switchgear',
    'ahu', 'acch', 'crah', 'rpp', 'condensate_pump', 'duct_heater', 'heat_trace',
    'msb', 'transformer', 'exhaust_fan', 'vesda', 'breaker', 'switchboard',
    'dehumidifier', 'panelboard', 'pump', 'battery_string', 'fire_system',
    'vfd', 'fuel_tank', 'battery_charger', 'dry_cooler', 'heat_exchanger',
    'cooling_tower', 'mts', 'other',
  ]

  const ASSET_TYPE_LABELS: Record<string, string> = {
    humidifier: 'Humidifier', ats: 'ATS', ups: 'UPS', pdu: 'PDU',
    generator: 'Generator', sts: 'STS', switchgear: 'Switchgear', ahu: 'AHU',
    acch: 'ACCH', crah: 'CRAH', rpp: 'RPP', condensate_pump: 'Condensate Pump',
    duct_heater: 'Duct Heater', heat_trace: 'Heat Trace', msb: 'MSB',
    transformer: 'Transformer', exhaust_fan: 'Exhaust Fan', vesda: 'VESDA',
    breaker: 'Breaker', switchboard: 'Switchboard', dehumidifier: 'Dehumidifier',
    panelboard: 'Panelboard', pump: 'Pump', battery_string: 'Battery String',
    fire_system: 'Fire System', vfd: 'VFD', fuel_tank: 'Fuel Tank',
    battery_charger: 'Battery Charger', dry_cooler: 'Dry Cooler',
    heat_exchanger: 'Heat Exchanger', cooling_tower: 'Cooling Tower',
    mts: 'MTS', other: 'Other',
  }

  type Phase = 'buildings' | 'assets'

  let phase: Phase = 'buildings'
  let buildings: (Building & { spaces: Space[] })[] = []
  let selectedBuilding: (Building & { spaces: Space[] }) | null = null
  let assets: AssetWithAnchor[] = []
  let mergedSpaces: { url: string; transform: RigidTransform | null }[] = []

  let selectedAssetId: string | null = null
  let placingAsset: AssetWithAnchor | null = null
  let buildingSpaces: Space[] = []

  let showNewDialog = false
  let newName = ''
  let newType = 'other'
  let saving = false
  let error: string | null = null
  let loadingBuilding = false

  $: mergedSpacesClickable = !!placingAsset
  $: console.log('[AssetView] mergedSpacesClickable:', mergedSpacesClickable, 'placingAsset:', placingAsset?.name)
  $: sceneAnchors = assets.filter(a => a.anchor?.glb_position).map(a => a.anchor!)
  $: selectedAnchorId = selectedAssetId
    ? (assets.find(a => a.id === selectedAssetId)?.anchor?.id ?? null)
    : null

  onMount(async () => {
    try {
      buildings = await fetchCompletedBuildings()
    } catch (e) {
      error = (e as Error).message
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
      error = (e as Error).message
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
      error = (e as Error).message
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
      error = (e as Error).message
    }
  }

  async function handlePlace({ detail }: CustomEvent<{ position: Position; spaceIndex: number | null }>): Promise<void> {
    console.log('[AssetView] handlePlace called, detail:', detail, 'placingAsset:', placingAsset)
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
      error = (e as Error).message
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
      dispatch('back')
    }
  }

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
      if (placingAsset) cancelPlacing()
      else if (showNewDialog) showNewDialog = false
    }
  }
</script>

<svelte:window on:keydown={handleKeydown} />

{#if phase === 'buildings'}
  <div class="building-picker">
    <div class="picker-header">
      <button class="back-btn" on:click={() => dispatch('back')}>← Back</button>
      <h1 class="picker-title">Asset Manager</h1>
    </div>
    <p class="picker-sub">Select a building to manage assets</p>
    {#if loadingBuilding}
      <p class="loading">Loading…</p>
    {:else if buildings.length === 0}
      <p class="empty">No completed buildings found.</p>
    {:else}
      <div class="building-list">
        {#each buildings as b (b.id)}
          <button class="building-card" on:click={() => selectBuilding(b)}>
            <span class="building-name">{b.name ?? 'Unnamed Building'}</span>
            <span class="building-meta">{b.spaces.length} space{b.spaces.length !== 1 ? 's' : ''}</span>
          </button>
        {/each}
      </div>
    {/if}
  </div>

{:else}
  <div class="asset-view">
    <!-- Sidebar -->
    <aside class="sidebar">
      <div class="sidebar-header">
        <button class="back-btn" on:click={goBack}>← Back</button>
        <span class="sidebar-title">{selectedBuilding?.name ?? 'Assets'}</span>
      </div>

      <div class="sidebar-actions">
        <button class="primary new-btn" on:click={() => { showNewDialog = true }}>+ New Asset</button>
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
              on:click={() => selectedAssetId = asset.id}
            >
              <div class="asset-main">
                <span class="asset-status" class:placed={!!asset.anchor?.glb_position} title={asset.anchor?.glb_position ? 'Placed on map' : 'Not placed'}>●</span>
                <div class="asset-info">
                  <span class="asset-name">{asset.name ?? 'Unnamed'}</span>
                  <span class="asset-type">{ASSET_TYPE_LABELS[asset.asset_type ?? ''] ?? asset.asset_type ?? '—'}</span>
                </div>
              </div>
              <div class="asset-actions">
                <button
                  class="place-btn"
                  class:active={placingAsset?.id === asset.id}
                  on:click|stopPropagation={() => placingAsset?.id === asset.id ? cancelPlacing() : startPlacing(asset)}
                >
                  {placingAsset?.id === asset.id ? 'Cancel' : asset.anchor_id ? 'Re-place' : 'Place'}
                </button>
                <button class="delete-btn danger" on:click|stopPropagation={() => handleDelete(asset)}>✕</button>
              </div>
            </div>
          {/each}
        {/if}
      </div>

    </aside>

    <!-- 3D Scene -->
    <div class="scene-wrap">
      <Scene
        {mergedSpaces}
        {mergedSpacesClickable}
        anchors={sceneAnchors}
        selectedId={selectedAnchorId}
        on:place={handlePlace}
      />
    </div>
  </div>

  {#if placingAsset}
    <div class="placement-banner">
      <span class="pulse-dot" />
      Click the map to place: <strong>{placingAsset.name ?? 'Unnamed'}</strong>
      <button on:click={cancelPlacing}>Cancel</button>
    </div>
  {/if}
{/if}

{#if showNewDialog}
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <div class="overlay" on:click|self={() => showNewDialog = false}>
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
        <button on:click={() => showNewDialog = false}>Cancel</button>
        <button class="primary" on:click={handleCreateAsset} disabled={saving || !newName.trim()}>
          {saving ? 'Saving…' : 'Create'}
        </button>
      </div>
    </div>
  </div>
{/if}

{#if error}
  <!-- svelte-ignore a11y-click-events-have-key-events -->
  <div class="error-toast" on:click={() => error = null}>{error}</div>
{/if}

<style>
  /* ── Building picker ── */
  .building-picker {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    align-items: center;
    justify-content: center;
    gap: 16px;
    background: var(--bg);
  }

  .picker-header {
    display: flex;
    align-items: center;
    gap: 16px;
  }

  .picker-title {
    font-size: 22px;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.02em;
  }

  .picker-sub {
    color: var(--text-muted);
    font-size: 13px;
    margin-top: -8px;
  }

  .building-list {
    display: flex;
    flex-direction: column;
    gap: 8px;
    min-width: 320px;
    max-width: 480px;
    width: 100%;
  }

  .building-card {
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 4px;
    padding: 16px 20px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    cursor: pointer;
    text-align: left;
    transition: border-color 0.15s, background 0.15s;
  }
  .building-card:hover {
    border-color: var(--accent);
    background: #1f1f1f;
  }

  .building-name {
    font-size: 14px;
    font-weight: 600;
    color: var(--text);
  }

  .building-meta {
    font-size: 12px;
    color: var(--text-muted);
  }

  .loading, .empty {
    color: var(--text-muted);
    font-size: 13px;
    font-style: italic;
  }

  /* ── Asset view ── */
  .asset-view {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .sidebar {
    width: 300px;
    min-width: 300px;
    background: var(--surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .sidebar-header {
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    align-items: center;
    gap: 12px;
    flex-shrink: 0;
  }

  .sidebar-title {
    font-size: 14px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.02em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
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
    flex-direction: column;
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
    gap: 6px;
    align-items: center;
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
    opacity: 0.5;
    transition: opacity 0.15s;
    flex-shrink: 0;
  }
  .asset-item:hover .delete-btn { opacity: 1; }

  .space-picker {
    padding: 12px 16px;
    border-top: 1px solid var(--border);
    flex-shrink: 0;
  }

  .section-label {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.06em;
    color: var(--text-muted);
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

  /* ── Placement banner ── */
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

  /* ── Dialog ── */
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

  /* ── Shared ── */
  .back-btn {
    padding: 3px 8px;
    font-size: 11px;
    border-radius: 4px;
    color: var(--text-muted);
    border: 1px solid var(--border);
    background: transparent;
    cursor: pointer;
    transition: color 0.15s;
    flex-shrink: 0;
  }
  .back-btn:hover { color: var(--text); }

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
