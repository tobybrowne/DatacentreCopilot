<script lang="ts" generics="T">
  import type { Snippet } from 'svelte'

  interface Props {
    title: string
    items: T[]
    item: Snippet<[T]>
    empty?: string
    onclick?: (it: T) => void
    selected?: (it: T) => boolean
  }

  let { title, items, item, empty = 'None.', onclick, selected }: Props = $props()
</script>

<section>
  <label class="label">
    {title}
    <span class="badge">{items.length}</span>
  </label>
  {#if items.length === 0}
    <p class="empty">{empty}</p>
  {:else}
    <ul>
      {#each items as it}
        <li
          class:clickable={!!onclick}
          class:selected={selected?.(it)}
          onclick={onclick ? () => onclick(it) : undefined}
        >
          {@render item(it)}
        </li>
      {/each}
    </ul>
  {/if}
</section>

<style>
  .label {
    font-size: 11px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
    display: flex;
    align-items: center;
    gap: 6px;
  }

  ul { list-style: none; }

  li {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 7px 4px;
    border-bottom: 1px solid var(--border);
    font-size: 13px;
    position: relative;
    transition: background 0.1s;
  }
  li:last-child { border-bottom: none; }
  li.clickable { cursor: pointer; }
  li.clickable:hover { background: #202020; }
  li.selected { background: var(--accent-dim); }

  .empty {
    font-size: 12px;
    color: var(--text-muted);
    font-style: italic;
  }
</style>
