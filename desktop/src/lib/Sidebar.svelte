<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  import type { Anchor, Position, Space } from './types'

  export let anchors: Anchor[] = []
  export let selectedId: string | null = null
  export let mappingAnchor: Anchor | null = null
  export let monitoring = false
  export let spaces: Space[] = []
  export let selectedSpaceId: string | null = null
  export let stitchPhase: 'idle' | 'pickSource' | 'pickTarget' | 'preview' = 'idle'
  export let stitchSourcePoints: Position[] = []
  export let stitchTargetPoints: Position[] = []
  export let stitchPointPlaced = false

  let stitchSourceId: string | null = null
  let stitchTargetId: string | null = null
  let buildingName = 'Building 1'

  function startStitch(): void {
    if (stitchSourceId && stitchTargetId)
      dispatch('startStitch', { sourceId: stitchSourceId, targetId: stitchTargetId })
  }

  const dispatch = createEventDispatcher<{
    selectspace: Space
    select: string
    delete: string
    startmapping: Anchor
    cancelmapping: void
    togglemonitor: void
    startStitch: { sourceId: string; targetId: string }
    cancelStitch: void
    undoStitchPoint: 'source' | 'target'
    continueStitch: void
    saveStitch: string
  }>()

  $: unmappedRefs = anchors.filter(a => a.is_reference && !a.glb_position)
  $: mappedRefs   = anchors.filter(a => a.is_reference && a.glb_position)
  $: content      = anchors.filter(a => !a.is_reference)
</script>

<aside>
  <div class="logo">Entangl Desktop</div>

  <!-- Spaces list -->
  <section class="spaces-section">
    <label class="section-label">
      Spaces
      <span class="badge">{spaces.length}</span>
    </label>
    {#if spaces.length === 0}
      <p class="empty-msg">No spaces in database.</p>
    {:else}
      <ul class="spaces-list">
        {#each spaces as space (space.id)}
          <li
            class="space-item"
            class:selected={space.id === selectedSpaceId}
            class:no-glb={!space.glb_path}
            on:click={() => space.glb_path && dispatch('selectspace', space)}
            title={space.glb_path ? space.name : `${space.name} — no GLB exported yet`}
          >
            <span class="space-name">{space.name || space.id}</span>
            {#if space.glb_path}
              <span class="tag glb">GLB</span>
            {:else}
              <span class="tag no-mesh">no mesh</span>
            {/if}
          </li>
        {/each}
      </ul>
    {/if}
  </section>

  <!-- Monitor mode -->
  <section>
    <label class="section-label">Monitoring</label>
    <button
      class="monitor-btn {monitoring ? 'active' : ''}"
      on:click={() => dispatch('togglemonitor')}
    >
      <span class="dot" class:live={monitoring} />
      {monitoring ? 'Stop monitoring' : 'Start monitoring'}
    </button>
  </section>

  <!-- Unmapped reference anchors — shown prominently -->
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
              <button class="map-btn active" on:click={() => dispatch('cancelmapping')}>Cancel</button>
            {:else}
              <button class="map-btn" on:click={() => dispatch('startmapping', anchor)}>Map</button>
            {/if}
          </li>
        {/each}
      </ul>
    </section>
  {/if}

  <!-- Mapped reference anchors -->
  <section class="list-section">
    <label class="section-label">
      Reference anchors
      <span class="badge">{mappedRefs.length}</span>
    </label>
    {#if mappedRefs.length === 0}
      <p class="empty-msg">None mapped yet.</p>
    {:else}
      <ul>
        {#each mappedRefs as anchor (anchor.id)}
          <li
            class:selected={anchor.id === selectedId}
            on:click={() => dispatch('select', anchor.id)}
          >
            <div class="anchor-row">
              <span class="anchor-name">{anchor.name || 'Unnamed'}</span>
              <span class="tag ref">ref</span>
            </div>
            <span class="coords">
              {anchor.glb_position.x.toFixed(2)},
              {anchor.glb_position.y.toFixed(2)},
              {anchor.glb_position.z.toFixed(2)}
            </span>
            <button
              class="delete-btn danger"
              on:click|stopPropagation={() => dispatch('delete', anchor.id)}
            >✕</button>
          </li>
        {/each}
      </ul>
    {/if}
  </section>

  <!-- Content anchors -->
  <section class="list-section flex1">
    <label class="section-label">
      Content anchors
      <span class="badge">{content.length}</span>
    </label>
    {#if content.length === 0}
      <p class="empty-msg">Click the mesh to place one.</p>
    {:else}
      <ul>
        {#each content as anchor (anchor.id)}
          <li
            class:selected={anchor.id === selectedId}
            class:no-position={!anchor.glb_position}
            on:click={() => dispatch('select', anchor.id)}
          >
            <div class="anchor-row">
              <span class="anchor-name">{anchor.name || 'Unnamed'}</span>
              <span class="tag {anchor.ml2_id ? "headset" : "desktop"}">{anchor.ml2_id ? "headset" : "desktop"}</span>
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
              on:click|stopPropagation={() => dispatch('delete', anchor.id)}
            >✕</button>
          </li>
        {/each}
      </ul>
    {/if}
  </section>
  <!-- Stitch section -->
  <section class="stitch-section">
    <label class="section-label">Stitch Spaces</label>

    {#if stitchPhase === 'idle'}
      <select bind:value={stitchSourceId}>
        <option value={null}>Source space…</option>
        {#each spaces.filter(s => s.glb_path) as s (s.id)}
          <option value={s.id}>{s.name || s.id}</option>
        {/each}
      </select>
      <select bind:value={stitchTargetId}>
        <option value={null}>Target (reference) space…</option>
        {#each spaces.filter(s => s.glb_path && s.id !== stitchSourceId) as s (s.id)}
          <option value={s.id}>{s.name || s.id}</option>
        {/each}
      </select>
      <button
        class="stitch-btn"
        disabled={!stitchSourceId || !stitchTargetId}
        on:click={startStitch}
      >
        Start picking points
      </button>

    {:else if stitchPhase === 'pickSource' || stitchPhase === 'pickTarget'}
      {@const pairsDone = stitchTargetPoints.length}
      {@const pickingSource = stitchPhase === 'pickSource'}
      {#if stitchPointPlaced}
        <p class="stitch-hint placed">
          Point placed on <strong class:src-label={pickingSource} class:tgt-label={!pickingSource}>{pickingSource ? 'source' : 'target'}</strong>.
          Continue when happy with it.
        </p>
      {:else}
        <p class="stitch-hint">
          Pair {pairsDone + 1}/3 — double-click a point on the
          <strong class:src-label={pickingSource} class:tgt-label={!pickingSource}>
            {pickingSource ? 'source' : 'target'}
          </strong> mesh
        </p>
      {/if}
      <div class="pairs-grid">
        {#each [0, 1, 2] as i}
          <span class="pair-dot src" class:filled={i < stitchSourcePoints.length} />
          <span class="pair-dot tgt" class:filled={i < stitchTargetPoints.length} />
        {/each}
      </div>
      <div class="stitch-actions">
        <button
          on:click={() => dispatch('undoStitchPoint', 'source')}
          disabled={stitchSourcePoints.length === 0 && stitchTargetPoints.length === 0}
        >Undo</button>
        <button on:click={() => dispatch('cancelStitch')}>Cancel</button>
      </div>
      {#if stitchPointPlaced}
        <button class="continue-btn" on:click={() => dispatch('continueStitch')}>Continue →</button>
      {/if}

    {:else if stitchPhase === 'preview'}
      <p class="stitch-hint stitch-ok">Preview ready — check the alignment in the viewport.</p>
      <input class="building-input" type="text" bind:value={buildingName} placeholder="Building name" />
      <div class="stitch-actions">
        <button on:click={() => dispatch('cancelStitch')}>Reset</button>
        <button class="primary" on:click={() => dispatch('saveStitch', buildingName)}>Save stitch</button>
      </div>
    {/if}
  </section>
</aside>

<style>
  aside {
    width: 280px;
    min-width: 280px;
    background: var(--surface);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow: hidden;
  }

  .logo {
    padding: 18px 16px 14px;
    font-size: 15px;
    font-weight: 600;
    letter-spacing: 0.02em;
    border-bottom: 1px solid var(--border);
    color: var(--accent);
  }

  section {
    padding: 12px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    gap: 8px;
  }

  .list-section { overflow: hidden; }
  .flex1 { flex: 1; }
  .list-section ul { overflow-y: auto; max-height: 200px; list-style: none; }
  .flex1 ul { max-height: none; flex: 1; }

  .unmapped-section {
    background: #ffcc0009;
    border-bottom: 1px solid #ffcc0044;
  }
  .unmapped-section ul { list-style: none; display: flex; flex-direction: column; gap: 4px; }

  .section-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
    display: flex;
    align-items: center;
    gap: 6px;
  }
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

  .spaces-section { overflow: hidden; max-height: 260px; }
  .spaces-list { list-style: none; overflow-y: auto; max-height: 200px; display: flex; flex-direction: column; gap: 2px; }

  .space-item {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 7px 4px;
    border-radius: 4px;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    transition: background 0.1s;
  }
  .space-item:last-child { border-bottom: none; }
  .space-item:hover:not(.no-glb) { background: #202020; }
  .space-item.selected { background: var(--accent-dim); }
  .space-item.no-glb { opacity: 0.45; cursor: default; }

  .space-name { font-size: 13px; font-weight: 500; flex: 1; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

  .tag.glb { background: #00d4ff22; color: var(--accent); }
  .tag.no-mesh { background: var(--border); color: var(--text-muted); }

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

  .coords {
    font-family: monospace;
    font-size: 11px;
    color: var(--text-muted);
  }
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

  .empty-msg {
    color: var(--text-muted);
    font-size: 12px;
    font-style: italic;
  }

  .monitor-btn {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px 12px;
    border-radius: 6px;
    border: 1px solid var(--border);
    color: var(--text-muted);
    font-size: 12px;
    cursor: pointer;
    transition: border-color 0.15s, color 0.15s, background 0.15s;
    width: 100%;
  }
  .monitor-btn:hover { border-color: var(--accent); color: var(--accent); }
  .monitor-btn.active { border-color: #ff4dff; color: #ff4dff; background: #ff4dff11; }

  .dot {
    width: 7px;
    height: 7px;
    border-radius: 50%;
    background: var(--text-muted);
    flex-shrink: 0;
  }
  .dot.live {
    background: #ff4dff;
    animation: pulse 1s infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }

  .stitch-section {
    padding: 12px 16px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    border-top: 1px solid var(--border);
  }

  .stitch-section select {
    width: 100%;
    background: #1a1a1a;
    border: 1px solid var(--border);
    color: var(--text, #eee);
    border-radius: 4px;
    padding: 5px 8px;
    font-size: 12px;
  }

  .stitch-btn {
    width: 100%;
    padding: 7px 0;
    border-radius: 4px;
    border: 1px solid var(--accent);
    color: var(--accent);
    font-size: 12px;
    cursor: pointer;
    transition: background 0.15s;
  }
  .stitch-btn:hover:not(:disabled) { background: var(--accent-dim); }
  .stitch-btn:disabled { opacity: 0.4; cursor: default; }

  .stitch-hint {
    font-size: 12px;
    color: var(--text-muted);
    line-height: 1.4;
    margin: 0;
  }
  .stitch-ok { color: #88ff88; }

  .pairs-grid {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    grid-template-rows: auto auto;
    gap: 6px 12px;
  }
  .pair-dot {
    width: 12px;
    height: 12px;
    border-radius: 50%;
    border: 2px solid var(--border);
    background: transparent;
    transition: background 0.15s, border-color 0.15s;
    justify-self: center;
  }
  .pair-dot.src.filled { background: #ff4444; border-color: #ff4444; }
  .pair-dot.tgt.filled { background: #44ffcc; border-color: #44ffcc; }
  .src-label { color: #ff4444; }
  .tgt-label { color: #44ffcc; }
  .stitch-hint.placed { color: var(--text, #eee); }

  .continue-btn {
    width: 100%;
    padding: 8px 0;
    border-radius: 4px;
    border: 1px solid var(--accent);
    color: var(--accent);
    font-size: 13px;
    font-weight: 600;
    cursor: pointer;
    transition: background 0.15s;
  }
  .continue-btn:hover { background: var(--accent-dim); }

  .stitch-actions {
    display: flex;
    gap: 6px;
  }
  .stitch-actions button {
    flex: 1;
    padding: 6px 0;
    border-radius: 4px;
    font-size: 12px;
    cursor: pointer;
    border: 1px solid var(--border);
    color: var(--text-muted);
  }
  .stitch-actions button:disabled { opacity: 0.4; cursor: default; }
  .stitch-actions button.primary {
    border-color: var(--accent);
    color: var(--accent);
  }
  .stitch-actions button.primary:hover { background: var(--accent-dim); }

  .building-input {
    width: 100%;
    box-sizing: border-box;
    background: #1a1a1a;
    border: 1px solid var(--border);
    color: var(--text, #eee);
    border-radius: 4px;
    padding: 5px 8px;
    font-size: 12px;
  }
</style>
