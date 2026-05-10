<script lang="ts">
  import { toasts, dismiss } from './toast'
</script>

{#if $toasts.length > 0}
  <div class="toast-stack">
    {#each $toasts as t (t.id)}
      <div class="toast {t.type}" onclick={() => dismiss(t.id)} role="alert">
        {t.message}
      </div>
    {/each}
  </div>
{/if}

<style>
  .toast-stack {
    position: fixed;
    bottom: 20px;
    right: 20px;
    display: flex;
    flex-direction: column;
    gap: 8px;
    z-index: 9999;
    max-width: 360px;
  }

  .toast {
    padding: 10px 16px;
    border-radius: 8px;
    font-size: 13px;
    cursor: pointer;
    animation: slide-in 0.15s ease-out;
    line-height: 1.4;
  }

  .toast.error {
    background: #ff444422;
    border: 1px solid var(--danger);
    color: var(--text);
  }

  .toast.success {
    background: #44cc6622;
    border: 1px solid #44cc66;
    color: var(--text);
  }

  .toast.info {
    background: #00d4ff22;
    border: 1px solid var(--accent);
    color: var(--text);
  }

  @keyframes slide-in {
    from { opacity: 0; transform: translateY(8px); }
    to   { opacity: 1; transform: translateY(0); }
  }
</style>
