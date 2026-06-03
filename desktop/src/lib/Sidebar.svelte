<script lang="ts">
  import type { Snippet } from 'svelte'
  import { onMount } from 'svelte'

  interface Props {
    title?: string;
    onback?: () => void;
    children?: Snippet;
  }

  let { title, onback, children }: Props = $props()

  const MIN = 200
  const MAX = 560
  const STORAGE_KEY = 'sidebar-width'

  let width = $state(280)
  let resizing = $state(false)

  onMount(() => {
    const saved = Number(localStorage.getItem(STORAGE_KEY))
    if (saved) width = Math.min(MAX, Math.max(MIN, saved))
  })

  function startResize(e: PointerEvent): void {
    e.preventDefault()
    resizing = true
    const startX = e.clientX
    const startW = width
    document.body.style.userSelect = 'none'
    document.body.style.cursor = 'col-resize'

    function onMove(ev: PointerEvent): void {
      width = Math.min(MAX, Math.max(MIN, startW + (ev.clientX - startX)))
    }
    function onUp(): void {
      resizing = false
      document.body.style.userSelect = ''
      document.body.style.cursor = ''
      localStorage.setItem(STORAGE_KEY, String(width))
      window.removeEventListener('pointermove', onMove)
      window.removeEventListener('pointerup', onUp)
    }
    window.addEventListener('pointermove', onMove)
    window.addEventListener('pointerup', onUp)
  }
</script>

<aside style="width: {width}px">
  {#if title}
    <div class="header">
      <button class="back-btn" onclick={() => onback?.()}>‹</button>
      <span class="title">{title}</span>
      <div class="header-spacer"></div>
    </div>
  {/if}
  <div class="content">
    {@render children?.()}
  </div>
  <!-- svelte-ignore a11y_no_static_element_interactions -->
  <div
    class="resizer"
    class:active={resizing}
    onpointerdown={startResize}
    ondblclick={() => { width = 280; localStorage.setItem(STORAGE_KEY, '280') }}
    title="Drag to resize"
  >
    <span class="grip">
      <i></i><i></i>
      <i></i><i></i>
      <i></i><i></i>
    </span>
  </div>
</aside>

<style>
  aside {
    background: var(--bg);
    border-right: 1px solid var(--border);
    display: flex;
    flex-direction: column;
    overflow: hidden;
    position: relative;
    flex-shrink: 0;
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
    padding: 12px 20px;
    display: flex;
    flex-direction: column;
    flex: 1;
    overflow-y: auto;
  }

  .resizer {
    position: absolute;
    top: 0;
    right: -8px;
    width: 16px;
    height: 100%;
    cursor: col-resize;
    z-index: 5;
    display: flex;
    align-items: center;
    justify-content: center;
  }
  /* Thin visible line, centered within the wider hit area. */
  .resizer::before {
    content: '';
    position: absolute;
    top: 0;
    bottom: 0;
    left: 50%;
    width: 2px;
    transform: translateX(-50%);
    background: transparent;
    transition: background 0.15s;
  }
  .resizer:hover::before,
  .resizer.active::before {
    background: var(--accent);
  }

  .grip {
    display: grid;
    grid-template-columns: repeat(2, 3px);
    gap: 3px;
    padding: 4px 2px;
    border-radius: 4px;
    background: var(--bg);
    border: 1px solid var(--border);
  }
  .grip i {
    width: 3px;
    height: 3px;
    border-radius: 50%;
    background: var(--text-muted);
    transition: background 0.15s;
  }
  .resizer:hover .grip i,
  .resizer.active .grip i {
    background: var(--text);
  }
</style>
