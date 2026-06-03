<script lang="ts">
  import type { Snippet } from 'svelte'

  interface Props {
    title?: string;
    onclose?: () => void;
    /** When false, clicking the backdrop and pressing Escape won't close (e.g. mid-operation). */
    dismissable?: boolean;
    children: Snippet;
    actions?: Snippet;
  }

  let { title, onclose, dismissable = true, children, actions }: Props = $props()

  function dismiss(): void {
    if (dismissable) onclose?.()
  }

  function handleKeydown(e: KeyboardEvent): void {
    if (e.key === 'Escape') {
      e.stopPropagation()
      dismiss()
    }
  }
</script>

<svelte:window onkeydown={handleKeydown} />

<!-- svelte-ignore a11y_click_events_have_key_events -->
<div class="overlay" role="presentation" onclick={(e) => { if (e.target === e.currentTarget) dismiss() }}>
  <div class="dialog" role="dialog" aria-modal="true">
    {#if title}<h3>{title}</h3>{/if}
    {@render children()}
    {#if actions}
      <div class="dialog-actions">{@render actions()}</div>
    {/if}
  </div>
</div>
