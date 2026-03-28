<script>
  import { createEventDispatcher } from 'svelte'

  export let anchors = []
  export let selectedId = null
  export let mappingAnchor = null
  export let monitoring = false

  const dispatch = createEventDispatcher()

  $: unmappedRefs = anchors.filter(a => a.is_reference && !a.glb_position)
  $: mappedRefs   = anchors.filter(a => a.is_reference && a.glb_position)
  $: content      = anchors.filter(a => !a.is_reference)

  function handleFile(e) {
    const file = e.target.files[0]
    if (!file) return
    dispatch('fileload', URL.createObjectURL(file))
  }
</script>

<aside>
  <div class="logo">Entangl Desktop</div>

  <!-- File picker -->
  <section>
    <label class="section-label">Space mesh</label>
    <label class="file-btn">
      Load .glb file
      <input type="file" accept=".glb,.gltf" on:change={handleFile} hidden />
    </label>
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

  .file-btn {
    display: block;
    text-align: center;
    padding: 8px 12px;
    border: 1px dashed var(--border);
    border-radius: 6px;
    cursor: pointer;
    color: var(--text-muted);
    transition: border-color 0.15s, color 0.15s;
  }
  .file-btn:hover { border-color: var(--accent); color: var(--accent); }

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
</style>
