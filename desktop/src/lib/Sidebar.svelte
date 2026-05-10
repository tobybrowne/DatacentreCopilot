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
    <button class="back-btn" onclick={() => onback?.()}>‹</button>
    <span class="title">{title}</span>
    <div class="header-spacer"></div>
  </div>
  <div class="content">
    {@render children?.()}
  </div>
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
    overflow: hidden;
  }

  .header {
    padding: 14px 16px;
    border-bottom: 1px solid var(--border);
    display: flex;
    flex-direction: row;
    align-items: center;
    flex-shrink: 0;
  }

  .back-btn {
    padding: 0;
    width: 32px;
    height: 32px;
    font-size: 22px;
    display: flex;
    align-items: center;
    justify-content: center;
    line-height: 1;
    padding-bottom: 3px;
    border-radius: 4px;
    color: var(--text-muted);
    border-color: var(--border);
    background: transparent;
    flex-shrink: 0;
  }
  .back-btn:hover { color: var(--text); }

  .title {
    flex: 1;
    text-align: center;
    font-size: 14px;
    font-weight: 600;
    color: var(--accent);
    letter-spacing: 0.02em;
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }

  .header-spacer {
    width: 32px;
    flex-shrink: 0;
  }

  .content {
    padding: 0 30px;
    display: flex;
    flex-direction: column;
    flex: 1;
    overflow-y: auto;
  }
</style>
