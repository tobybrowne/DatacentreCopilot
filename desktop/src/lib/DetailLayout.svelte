<script lang="ts">
  import type { Snippet } from 'svelte'
  import TopBar from './TopBar.svelte'

  interface Props {
    title: string;
    onback?: () => void;
    badge?: Snippet;
    actions?: Snippet;
    /** Body content — typically a <Sidebar> followed by a scene/main area. */
    children: Snippet;
  }

  let { title, onback, badge, actions, children }: Props = $props()
</script>

<div class="shell">
  <TopBar {title} {onback} {badge} {actions} />
  <div class="body">
    {@render children()}
  </div>
</div>

<style>
  .shell {
    width: 100vw;
    height: 100vh;
    display: flex;
    flex-direction: column;
    overflow: hidden;
    background: var(--bg);
  }

  .body {
    flex: 1;
    display: flex;
    min-height: 0;
    overflow: hidden;
  }
</style>
