<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Search } from 'lucide-svelte'

  interface Props {
    title: string;
    onback?: () => void;
    searchable?: boolean;
    query?: string;
    placeholder?: string;
    badge?: Snippet;
    actions?: Snippet;
  }

  let {
    title,
    onback,
    searchable = false,
    query = $bindable(''),
    placeholder = 'Search…',
    badge,
    actions,
  }: Props = $props()
</script>

<header>
  {#if onback}
    <button class="back-btn" onclick={() => onback?.()}>‹</button>
  {/if}
  <h1>{title}</h1>
  {#if badge}{@render badge()}{/if}
  <div class="spacer"></div>
  {#if searchable}
    <div class="search">
      <Search size={14} />
      <input type="text" bind:value={query} {placeholder} />
    </div>
  {/if}
  {#if actions}{@render actions()}{/if}
</header>

<style>
  header {
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 16px 28px;
    border-bottom: 1px solid var(--border);
    flex-shrink: 0;
    background: var(--bg);
  }

  .back-btn {
    width: 32px;
    height: 32px;
    font-size: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    line-height: 1;
    padding: 0 0 3px;
    border-radius: 6px;
    color: var(--text-muted);
    border-color: var(--border);
    background: transparent;
    flex-shrink: 0;
    margin-right: 8px;
  }
  .back-btn:hover { color: var(--text); }

  h1 {
    font-size: 18px;
    font-weight: 600;
    color: var(--text);
    margin: 0;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .spacer { flex: 1; }

  .search {
    display: flex;
    align-items: center;
    gap: 6px;
    padding: 0 10px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 6px;
    color: var(--text-muted);
  }
  .search:focus-within { border-color: var(--accent); }
  .search input {
    background: transparent;
    border: none;
    outline: none;
    color: var(--text);
    font-size: 13px;
    padding: 7px 0;
    width: 200px;
  }
</style>
