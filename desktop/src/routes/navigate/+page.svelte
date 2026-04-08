<script lang="ts">
  import { onMount } from 'svelte'
  import { goto } from '$app/navigation'
  import { fetchCompletedBuildings, fetchSpaces } from '$lib/supabase'
  import type { Building, BuildingSpace, Space } from '$lib/types'

  let buildings: (Building & { building_spaces: BuildingSpace[] })[] = []
  let spaces: Space[] = []
  let loading = true
  let error: string | null = null

  onMount(async () => {
    try {
      ;[buildings, spaces] = await Promise.all([fetchCompletedBuildings(), fetchSpaces()])
      spaces = spaces.filter(s => s.glb_path)
    } catch (e) {
      error = (e as Error).message
    } finally {
      loading = false
    }
  })
</script>

<div class="page">
  <div class="header">
    <button class="back-btn" on:click={() => goto('/')}>← Back</button>
    <span class="logo">Navigate</span>
  </div>

  <div class="content">
    {#if loading}
      <p class="hint">Loading…</p>
    {:else if error}
      <p class="hint danger">{error}</p>
    {:else}
      {#if buildings.length > 0}
        <label class="section-label">Buildings</label>
        <ul class="list">
          {#each buildings as b (b.id)}
            <li class="item" on:click={() => goto(`/navigate/${b.id}`)}>
              <span class="name">{b.name || 'Unnamed'}</span>
              <span class="meta">{b.building_spaces.length} spaces</span>
              <span class="arrow">→</span>
            </li>
          {/each}
        </ul>
      {/if}

      {#if spaces.length > 0}
        <label class="section-label">Individual spaces</label>
        <ul class="list">
          {#each spaces as s (s.id)}
            <li class="item" on:click={() => goto(`/navigate/space/${s.id}`)}>
              <span class="name">{s.name || 'Unnamed'}</span>
              <span class="meta">space</span>
              <span class="arrow">→</span>
            </li>
          {/each}
        </ul>
      {/if}

      {#if buildings.length === 0 && spaces.length === 0}
        <p class="hint">No navigable content yet.</p>
      {/if}
    {/if}
  </div>
</div>

<style>
  .page {
    width: 100vw;
    height: 100vh;
    background: var(--bg);
    display: flex;
    flex-direction: column;
  }

  .header {
    padding: 14px 24px;
    border-bottom: 1px solid var(--border);
    display: flex;
    align-items: center;
    gap: 12px;
  }

  .back-btn {
    padding: 3px 8px;
    font-size: 11px;
    color: var(--text-muted);
    border-color: var(--border);
  }

  .logo {
    font-size: 14px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.02em;
  }

  .content {
    padding: 32px;
    display: flex;
    flex-direction: column;
    gap: 16px;
    max-width: 480px;
  }

  .section-label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
  }

  .hint { font-size: 13px; color: var(--text-muted); }
  .hint.danger { color: var(--danger); }

  .list { list-style: none; display: flex; flex-direction: column; gap: 4px; }

  .item {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 16px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    cursor: pointer;
    transition: border-color 0.15s;
  }
  .item:hover { border-color: var(--accent); }

  .name { flex: 1; font-size: 14px; font-weight: 500; }
  .meta { font-size: 12px; color: var(--text-muted); }
  .arrow { color: var(--accent); font-size: 14px; }
</style>
