<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import { fetchSpaces } from '$lib/supabase'
  import Sidebar from '$lib/Sidebar.svelte'
  import { toast } from '$lib/toast'
  import type { Space } from '$lib/types'

  let spaces: Space[] = $state([])

  onMount(async () => {
    try {
      spaces = await fetchSpaces()
    } catch (e) {
      toast((e as Error).message)
    }
  })
</script>

<Sidebar title="Space Calibration" onback={() => goto('/')}>
  <section>
    <label class="section-label">
      Spaces
      <span class="badge">{spaces.length}</span>
    </label>
    {#if spaces.length === 0}
      <p class="hint">No spaces found.</p>
    {:else}
      <ul class="spaces-list">
        {#each spaces as space (space.id)}
          <li
            class:no-glb={!space.glb_path}
            onclick={() => space.glb_path && goto(`/calibration/${space.id}`)}
            title={space.glb_path ? space.name : `${space.name} — no GLB exported yet`}
          >
            <span class="space-name">{space.name || space.id}</span>
          </li>
        {/each}
      </ul>
    {/if}
  </section>
</Sidebar>

<div class="empty-scene">
  <p>Select a space to begin.</p>
</div>

<style>
  .badge {
    background: var(--accent-dim);
    color: var(--accent);
    border-radius: 10px;
    padding: 1px 7px;
    font-size: 11px;
  }

  .hint { font-size: 12px; color: var(--text-muted); line-height: 1.5; margin: 0; }

  .spaces-list { list-style: none; }

  li {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 7px 4px;
    border-bottom: 1px solid var(--border);
    cursor: pointer;
    transition: background 0.1s;
    font-size: 13px;
  }
  li:last-child { border-bottom: none; }
  li:hover:not(.no-glb) { background: #202020; }
  li.no-glb { opacity: 0.45; cursor: default; }

  .space-name { flex: 1; font-weight: 500; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }

.empty-scene {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
    font-size: 13px;
  }
</style>
