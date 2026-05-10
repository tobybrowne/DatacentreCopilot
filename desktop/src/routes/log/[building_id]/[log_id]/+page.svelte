<script lang="ts">
  import { goto } from '$app/navigation'
  import { onDestroy, onMount } from 'svelte'
  import { getLogBucketUrl } from '$lib/supabase'
  import { Canvas } from '@threlte/core'
  import NavigateSceneInner from '$lib/NavigateSceneInner.svelte'
  import GesturePlayer from '$lib/GesturePlayer.svelte'
  import Sidebar from '$lib/Sidebar.svelte'
  import { toast } from '$lib/toast'
  import type { GestureRecording, LogWithContext, RigidTransform } from '$lib/types'
  import type { PageData } from './$types'

  interface Props { data: PageData }
  let { data }: Props = $props()

  const log: LogWithContext = data.log
  const spaces: { url: string; transform: RigidTransform | null; boundingBox: unknown }[] = data.spaces
  const buildingId: string = data.buildingId

  type View = 'gesture' | 'video'
  let view: View = $state(log.geometry_recording_path ? 'gesture' : 'video')

  let gestureRecording: GestureRecording | null = $state(null)
  let gestureLoading = $state(false)
  let videoUrl: string | null = $state(null)
  let videoLoading = $state(false)

  let playbackTime = $state(0)
  let playing = $state(false)
  let playbackSpeed = $state(1)
  let rafId: number | null = null

  let duration = $derived(
    gestureRecording?.frames.length
      ? gestureRecording.frames[gestureRecording.frames.length - 1][0] -
        gestureRecording.frames[0][0]
      : 0
  )

  onMount(async () => {
    if (log.geometry_recording_path) {
      await loadGesture()
    } else if (log.camera_recording_path) {
      await loadVideo()
    }
  })

  async function loadGesture(): Promise<void> {
    gestureLoading = true
    try {
      const url = await getLogBucketUrl(log.geometry_recording_path!)
      const resp = await fetch(url)
      if (!resp.ok) throw new Error(`Gesture fetch failed: ${resp.statusText}`)
      gestureRecording = (await resp.json()) as GestureRecording
      playbackTime = 0
      view = 'gesture'
    } catch (e) {
      toast((e as Error).message)
    } finally {
      gestureLoading = false
    }
  }

  async function loadVideo(): Promise<void> {
    if (!log.camera_recording_path) return
    videoLoading = true
    try {
      videoUrl = await getLogBucketUrl(log.camera_recording_path)
      view = 'video'
    } catch (e) {
      toast((e as Error).message)
    } finally {
      videoLoading = false
    }
  }

  async function switchToVideo(): Promise<void> {
    pause()
    if (!videoUrl) await loadVideo()
    else view = 'video'
  }

  async function switchToGesture(): Promise<void> {
    if (!gestureRecording) await loadGesture()
    else view = 'gesture'
  }

  function play(): void {
    if (playing || !gestureRecording || duration === 0) return
    if (playbackTime >= duration) playbackTime = 0
    playing = true
    let last = performance.now()

    function tick(): void {
      if (!playing) return
      const now = performance.now()
      playbackTime = Math.min(playbackTime + (now - last) * playbackSpeed, duration)
      last = now
      if (playbackTime >= duration) { playing = false; return }
      rafId = requestAnimationFrame(tick)
    }
    rafId = requestAnimationFrame(tick)
  }

  function pause(): void {
    playing = false
    if (rafId !== null) { cancelAnimationFrame(rafId); rafId = null }
  }

  function toggle(): void { if (playing) pause(); else play() }

  function onScrub(e: Event): void {
    playbackTime = (parseFloat((e.target as HTMLInputElement).value) / 100) * duration
  }

  function fmtMs(ms: number): string {
    const s = Math.floor(ms / 1000)
    return `${Math.floor(s / 60)}:${(s % 60).toString().padStart(2, '0')}`
  }

  function getStepText(): string {
    if (!log.step_id || !log.procedureRun?.procedure.steps) return ''
    const step = (log.procedureRun.procedure.steps as { id: string; text: string }[])
      .find(s => s.id === log.step_id)
    return step?.text ?? ''
  }

  function formatDate(iso: string): string {
    return new Date(iso).toLocaleString(undefined, {
      month: 'short', day: 'numeric',
      hour: '2-digit', minute: '2-digit',
    })
  }

  const hasGesture = !!log.geometry_recording_path
  const hasVideo   = !!log.camera_recording_path
  const stepText   = getStepText()

  onDestroy(() => { if (rafId !== null) cancelAnimationFrame(rafId) })
</script>

<div class="log-view">
  <Sidebar title="Log" onback={() => goto(`/log/${buildingId}`)}>

    <section>
      <div class="log-meta">
        <div class="meta-item">
          <span class="meta-key">Procedure</span>
          <span class="meta-val">{log.procedureRun?.procedure.title ?? '—'}</span>
        </div>
        {#if stepText}
          <div class="meta-item">
            <span class="meta-key">Step</span>
            <span class="meta-val italic">{stepText}</span>
          </div>
        {/if}
        <div class="meta-item">
          <span class="meta-key">Time</span>
          <span class="meta-val">{formatDate(log.created_at)}</span>
        </div>
        <div class="meta-item">
          <span class="meta-key">User</span>
          <span class="meta-val">{log.userEmail ?? log.user_id.slice(0, 8)}</span>
        </div>
        <div class="meta-item">
          <span class="meta-key">Type</span>
          <div class="badges">
            {#if hasGesture}<span class="badge b-gesture">Gesture</span>{/if}
            {#if hasVideo}<span class="badge b-video">Video</span>{/if}
          </div>
        </div>
      </div>
    </section>

    {#if hasGesture && hasVideo}
      <section class="view-switch">
        <button class:active={view === 'gesture'} onclick={switchToGesture}>Gesture</button>
        <button class:active={view === 'video'} onclick={switchToVideo}>Video</button>
      </section>
    {/if}

    {#if view === 'gesture' && gestureRecording}
      <section class="playback">
        <label class="section-label">Playback</label>
        <div class="playback-row">
          <button class="play-btn" onclick={toggle}>
            {playing ? '⏸' : '▶'}
          </button>
          <select bind:value={playbackSpeed} class="speed-sel">
            <option value={0.25}>0.25×</option>
            <option value={0.5}>0.5×</option>
            <option value={1}>1×</option>
            <option value={2}>2×</option>
          </select>
        </div>
        <input
          type="range" min="0" max="100" step="0.1"
          value={duration > 0 ? (playbackTime / duration) * 100 : 0}
          oninput={onScrub}
          class="scrubber"
        />
        <div class="time-row">
          <span>{fmtMs(playbackTime)}</span>
          <span class="time-sep">/</span>
          <span>{fmtMs(duration)}</span>
        </div>
      </section>
    {/if}

  </Sidebar>

  <div class="main">
    {#if gestureLoading || videoLoading}
      <div class="placeholder">Loading…</div>

    {:else if view === 'gesture' && gestureRecording}
      <Canvas>
        <NavigateSceneInner spaces={spaces} />
        <GesturePlayer recording={gestureRecording} playbackMs={playbackTime} />
      </Canvas>

    {:else if view === 'video' && videoUrl}
      <div class="video-wrap">
        <!-- svelte-ignore a11y_media_has_caption -->
        <video src={videoUrl} controls class="video-player"></video>
      </div>

    {:else if view === 'gesture' && !gestureRecording && !gestureLoading}
      <div class="placeholder">Failed to load gesture recording.</div>

    {:else if view === 'video' && !videoUrl && !videoLoading}
      <div class="placeholder">Failed to load video.</div>
    {/if}
  </div>
</div>

<style>
  .log-view {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .main {
    flex: 1;
    height: 100vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    background: var(--bg);
  }

  .placeholder {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    color: var(--text-muted);
    font-size: 13px;
  }

  /* Meta */
  .log-meta { display: flex; flex-direction: column; gap: 8px; }
  .meta-item { display: flex; flex-direction: column; gap: 2px; }
  .meta-key {
    font-size: 10px;
    text-transform: uppercase;
    letter-spacing: 0.08em;
    color: var(--text-muted);
  }
  .meta-val { font-size: 12px; color: var(--text); }
  .meta-val.italic { font-style: italic; }

  .badges { display: flex; gap: 5px; flex-wrap: wrap; margin-top: 2px; }
  .badge {
    font-size: 10px;
    padding: 2px 8px;
    border-radius: 10px;
    font-weight: 600;
    letter-spacing: 0.04em;
    border: 1px solid;
  }
  .b-gesture { background: #00d4ff18; color: var(--accent); border-color: #00d4ff44; }
  .b-video   { background: #ff884418; color: #ff8844;       border-color: #ff884444; }

  /* View switch */
  .view-switch {
    display: flex !important;
    flex-direction: row !important;
    gap: 6px !important;
  }
  .view-switch button {
    flex: 1;
    font-size: 12px;
    padding: 5px 0;
    color: var(--text-muted);
    border-color: var(--border);
    background: transparent;
  }
  .view-switch button.active {
    color: var(--accent);
    border-color: var(--accent);
    background: var(--accent-dim);
  }
  .view-switch button:hover:not(.active) { color: var(--text); }

  /* Playback */
  .playback { gap: 8px !important; }
  .playback-row { display: flex; align-items: center; gap: 8px; }
  .play-btn {
    font-size: 15px;
    width: 34px;
    height: 34px;
    padding: 0;
    display: flex;
    align-items: center;
    justify-content: center;
    border-radius: 50%;
    border: 1px solid var(--border);
    background: transparent;
    color: var(--accent);
    flex-shrink: 0;
  }
  .play-btn:hover { background: var(--accent-dim); }
  .speed-sel {
    flex: 1;
    background: var(--bg);
    border: 1px solid var(--border);
    color: var(--text-muted);
    border-radius: 4px;
    padding: 4px 6px;
    font-size: 11px;
    outline: none;
    min-width: 0;
  }
  .scrubber { width: 100%; accent-color: var(--accent); cursor: pointer; }
  .time-row {
    display: flex;
    gap: 4px;
    font-family: monospace;
    font-size: 11px;
    color: var(--text-muted);
  }
  .time-sep { color: var(--border); }

  /* Video */
  .video-wrap {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    background: #000;
  }
  .video-player { max-width: 100%; max-height: 100%; outline: none; }
</style>
