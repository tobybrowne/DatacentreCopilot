<script lang="ts">
  import type { Snippet } from 'svelte'

  interface Props {
    title: string;
    onback?: () => void;
    children?: Snippet;
  }

  let { title, onback, children }: Props = $props()
</script>

<aside>
  <div class="header">
    <button class="back-btn" onclick={() => onback?.()}>← Back</button>
    <span class="title">{title}</span>
  </div>
  {@render children?.()}
</aside>

<style>
  aside {
    width: 280px;
    /* min-width: 280px; */
    background: var(--surface);
    /* background-color: red; */
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow-y: auto;
  }

  .header {
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 8px;
    flex-shrink: 0;
  }

  .back-btn {
    padding: 3px 8px;
    font-size: 11px;
    border-radius: 4px;
    color: var(--text-muted);
    border-color: var(--border);
    background: transparent;
    flex-shrink: 0;
  }
  .back-btn:hover { color: var(--text); }

  .title {
    font-size: 14px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.02em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
</style>
