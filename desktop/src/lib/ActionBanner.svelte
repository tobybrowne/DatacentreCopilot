<script lang="ts">
  import Button from './Button.svelte'

  interface Props {
    prompt: string
    name: string
    oncancel: () => void
  }

  let { prompt, name, oncancel }: Props = $props()
</script>

<div class="banner">
  <span class="dot"></span>
  <span class="text">{prompt} <strong>{name}</strong></span>
  <Button onclick={oncancel}>Cancel</Button>
</div>

<style>
  .banner {
    position: fixed;
    top: 16px;
    left: 50%;
    transform: translateX(-50%);
    background: var(--surface);
    border: 1px solid var(--accent);
    border-radius: 8px;
    padding: 10px 16px;
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 13px;
    z-index: 50;
    box-shadow: 0 0 20px #00d4ff33;
  }

  .dot {
    width: 8px;
    height: 8px;
    border-radius: 50%;
    background: var(--accent);
    flex-shrink: 0;
    animation: pulse 1s infinite;
  }

  @keyframes pulse {
    0%, 100% { opacity: 1; }
    50% { opacity: 0.3; }
  }
</style>
