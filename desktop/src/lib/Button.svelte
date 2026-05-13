<script lang="ts">
  import type { Snippet } from 'svelte'

  interface Props {
    variant?: 'default' | 'primary' | 'danger'
    size?: 'sm' | 'md'
    type?: 'button' | 'submit' | 'reset'
    disabled?: boolean
    onclick?: (e: MouseEvent) => void
    style?: string
    children: Snippet
  }

  let { variant = 'default', size = 'md', type = 'button', disabled = false, onclick, style, children }: Props = $props()
</script>

<button
  class={[variant !== 'default' ? variant : '', size === 'sm' ? 'sm' : ''].filter(Boolean).join(' ')}
  {type}
  {disabled}
  {onclick}
  {style}
>
  {@render children()}
</button>

<style>
  .sm {
    padding: 3px 8px;
    font-size: 11px;
  }

  .primary {
    background: var(--accent);
    color: #000;
    border-color: var(--accent);
  }
  .primary:hover {
    background: #00b8d9;
  }

  .danger {
    border-color: var(--danger);
    color: var(--danger);
  }
  .danger:hover {
    background: #ff444422;
  }
</style>
