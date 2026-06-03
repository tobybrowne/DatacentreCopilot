<script lang="ts">
  import type { Snippet } from 'svelte'
  import { Box } from 'lucide-svelte'
  import { renderGlbThumbnail, renderGlbFrames, type ThumbnailPart } from './glbThumbnail'

  interface Props {
    title: string;
    subtitle?: string;
    /** Cache key for the rendered thumbnail (e.g. the space/building id). */
    thumbKey: string;
    /** Lazily resolves the GLB part(s) to render. Called once the tile is visible. */
    loadParts: () => Promise<ThumbnailPart[]>;
    onclick?: () => void;
    selected?: boolean;
    disabled?: boolean;
    badge?: Snippet;
    actions?: Snippet;
  }

  let { title, subtitle, thumbKey, loadParts, onclick, selected = false, disabled = false, badge, actions }: Props = $props()

  const FRAMES = 24
  const FRAME_MS = 140

  let status: 'idle' | 'loading' | 'ready' | 'empty' | 'error' = $state('idle')
  let stillSrc: string | null = $state(null)
  let el: HTMLElement

  let parts: ThumbnailPart[] = []
  let frames: string[] | null = null
  let frameIdx = $state(0)
  let hovering = $state(false)
  let spinTimer: ReturnType<typeof setInterval> | null = null

  // Show a spin frame while hovering (once frames are ready), else the still.
  let src = $derived(hovering && frames ? frames[frameIdx] : stillSrc)

  $effect(() => {
    const observer = new IntersectionObserver((entries) => {
      if (entries.some(e => e.isIntersecting) && status === 'idle') {
        observer.disconnect()
        loadThumb()
      }
    }, { rootMargin: '200px' })
    observer.observe(el)
    return () => { observer.disconnect(); stopSpin() }
  })

  async function loadThumb(): Promise<void> {
    status = 'loading'
    try {
      parts = await loadParts()
      if (parts.length === 0) { status = 'empty'; return }
      stillSrc = await renderGlbThumbnail(thumbKey, parts)
      status = 'ready'
    } catch (e) {
      console.error('thumbnail render failed', thumbKey, e)
      status = 'error'
    }
  }

  async function handleEnter(): Promise<void> {
    if (status !== 'ready') return
    hovering = true
    if (!frames) {
      try {
        frames = await renderGlbFrames(thumbKey, parts, FRAMES)
      } catch (e) {
        console.error('turntable render failed', thumbKey, e)
        return
      }
    }
    if (hovering) startSpin()
  }

  function handleLeave(): void {
    hovering = false
    stopSpin()
    frameIdx = 0
  }

  function startSpin(): void {
    stopSpin()
    spinTimer = setInterval(() => {
      frameIdx = (frameIdx + 1) % FRAMES
    }, FRAME_MS)
  }

  function stopSpin(): void {
    if (spinTimer) { clearInterval(spinTimer); spinTimer = null }
  }
</script>

<button
  bind:this={el}
  class="tile"
  class:selected
  class:disabled
  disabled={disabled}
  onclick={() => !disabled && onclick?.()}
  onpointerenter={handleEnter}
  onpointerleave={handleLeave}
>
  <div class="thumb">
    {#if status === 'ready' && src}
      <img {src} alt={title} />
    {:else if status === 'loading' || status === 'idle'}
      <div class="shimmer"></div>
    {:else}
      <div class="fallback"><Box size={32} /></div>
    {/if}
    {#if badge}
      <div class="badge-slot">{@render badge()}</div>
    {/if}
    {#if actions}
      <div class="action-slot">{@render actions()}</div>
    {/if}
  </div>
  <div class="meta">
    <span class="title">{title}</span>
    {#if subtitle}<span class="subtitle">{subtitle}</span>{/if}
  </div>
</button>

<style>
  .tile {
    display: flex;
    flex-direction: column;
    padding: 0;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
    overflow: hidden;
    text-align: left;
    cursor: pointer;
    transition: border-color 0.15s, transform 0.1s, background 0.15s;
  }
  .tile:hover:not(.disabled) {
    border-color: var(--accent);
    background: #1f1f1f;
    transform: translateY(-2px);
  }
  .tile.selected { border-color: var(--accent); background: var(--accent-dim); }
  .tile.disabled { opacity: 0.45; cursor: default; }

  .thumb {
    position: relative;
    aspect-ratio: 4 / 3;
    background: radial-gradient(circle at 50% 40%, #1c1c1c, #0e0e0e);
    display: flex;
    align-items: center;
    justify-content: center;
    overflow: hidden;
  }
  .thumb img { width: 100%; height: 100%; object-fit: contain; display: block; }

  .fallback { color: var(--text-muted); opacity: 0.4; }

  .shimmer {
    width: 100%;
    height: 100%;
    background: linear-gradient(100deg, #161616 30%, #222 50%, #161616 70%);
    background-size: 200% 100%;
    animation: shimmer 1.2s infinite linear;
  }
  @keyframes shimmer {
    0% { background-position: 100% 0; }
    100% { background-position: -100% 0; }
  }

  .badge-slot { position: absolute; top: 8px; left: 8px; }
  .action-slot { position: absolute; top: 8px; right: 8px; display: flex; gap: 4px; }

  .meta {
    display: flex;
    flex-direction: column;
    gap: 2px;
    padding: 10px 12px;
    min-width: 0;
  }
  .title {
    font-size: 13px;
    font-weight: 600;
    color: var(--text);
    white-space: nowrap;
    overflow: hidden;
    text-overflow: ellipsis;
  }
  .subtitle { font-size: 11px; color: var(--text-muted); }
</style>
