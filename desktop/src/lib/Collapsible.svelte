<script lang="ts">
  import type { Snippet } from 'svelte'

  interface Props {
    title: string;
    count?: number;
    /** Whether the body is expanded (bindable). */
    open?: boolean;
    /** Extra class on the label, e.g. "warning". */
    labelClass?: string;
    /** Extra class on the count badge, e.g. "warning". */
    badgeClass?: string;
    children: Snippet;
  }

  let { title, count, open = $bindable(true), labelClass = '', badgeClass = '', children }: Props = $props()
</script>

<section class="collapsible-header" onclick={() => open = !open}>
  <label class="section-label {labelClass}">
    {title}
    {#if count !== undefined}<span class="badge {badgeClass}">{count}</span>{/if}
  </label>
  <span class="chevron" class:open>›</span>
</section>
{#if open}
  <section class="collapsible-body">
    {@render children()}
  </section>
{/if}

<style>
  .collapsible-header {
    flex-direction: row;
    align-items: center;
    cursor: pointer;
    user-select: none;
  }
  .section-label { flex: 1; cursor: pointer; }
  .collapsible-header:hover .section-label { color: var(--text); }

  .chevron {
    font-size: 16px;
    color: var(--text-muted);
    transition: transform 0.15s;
    transform: rotate(0deg);
  }
  .chevron.open { transform: rotate(90deg); }

  .collapsible-body { gap: 6px; }

  /* Warning variant (e.g. unmapped reference anchors). */
  .section-label.warning { color: var(--pending); }
  .badge.warning { background: #ffcc0022; color: var(--pending); }
</style>
