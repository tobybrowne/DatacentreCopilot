<script lang="ts">
  import type { Snippet } from 'svelte'
  import TopBar from './TopBar.svelte'

  interface Props {
    title: string;
    onback?: () => void;
    searchable?: boolean;
    query?: string;
    placeholder?: string;
    actions?: Snippet;
    children?: Snippet;
  }

  let {
    title,
    onback,
    searchable = false,
    query = $bindable(''),
    placeholder = 'Search…',
    actions,
    children,
  }: Props = $props()
</script>

<div class="page">
  <TopBar {title} {onback} {searchable} bind:query {placeholder} {actions} />
  <div class="scroll">
    {@render children?.()}
  </div>
</div>

<style>
  .page {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    background: var(--bg);
    overflow: hidden;
  }

  .scroll {
    flex: 1;
    overflow-y: auto;
    padding: 24px 28px 48px;
  }
</style>
