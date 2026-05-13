<script lang="ts">
  interface Props {
    checked: boolean
    label?: string
    onchange?: (checked: boolean) => void
  }

  let { checked = $bindable(), label, onchange }: Props = $props()
</script>

<label class="checkbox-label">
  <input
    type="checkbox"
    bind:checked
    onchange={() => onchange?.(checked)}
  />
  <span class="box">
    {#if checked}
      <svg width="10" height="10" viewBox="0 0 10 10" fill="none">
        <polyline points="1.5,5 4,7.5 8.5,2.5" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>
      </svg>
    {/if}
  </span>
  {#if label}
    <span class="text">{label}</span>
  {/if}
</label>

<style>
  .checkbox-label {
    display: inline-flex;
    align-items: center;
    gap: 8px;
    cursor: pointer;
    user-select: none;
  }

  input {
    display: none;
  }

  .box {
    width: 15px;
    height: 15px;
    border-radius: 3px;
    border: 1px solid var(--border);
    background: var(--surface);
    display: flex;
    align-items: center;
    justify-content: center;
    flex-shrink: 0;
    transition: border-color 0.15s, background 0.15s;
    color: #000;
  }

  input:checked ~ .box {
    background: var(--accent);
    border-color: var(--accent);
  }

  .checkbox-label:hover .box {
    border-color: var(--accent);
  }

  .text {
    font-size: 13px;
    color: var(--text);
  }
</style>
