<script lang="ts">
  import { goto } from '$app/navigation'
  import { onMount } from 'svelte'
  import { getLogBucketUrl } from '$lib/supabase'
  import { formatDate, getStepText } from '$lib/logUtils'
  import Sidebar from '$lib/Sidebar.svelte'
  import { toast } from '$lib/toast'
  import type { LogWithContext } from '$lib/types'
  import type { PageData } from './$types'

  interface Props { data: PageData }
  let { data }: Props = $props()

  const log: LogWithContext = data.log
  const buildingId: string = data.buildingId

  let videoUrl: string | null = $state(null)
  let videoLoading = $state(false)

  onMount(async () => {
    if (log.camera_recording_path) await loadVideo()
  })

  async function loadVideo(): Promise<void> {
    if (!log.camera_recording_path) return
    videoLoading = true
    try {
      videoUrl = await getLogBucketUrl(log.camera_recording_path)
    } catch (e) {
      toast((e as Error).message)
    } finally {
      videoLoading = false
    }
  }

  const hasGesture = !!log.geometry_recording_path
  const hasVideo   = !!log.camera_recording_path
  const stepText   = getStepText(log)
</script>

<div class="log-view">
  <Sidebar title="Log Viewer" onback={() => goto(`/log/${buildingId}`)}>

    <section>
      <div class="log-meta">
        <div class="meta-item">
          <span class="meta-key">Procedure</span>
          <span class="meta-val">{log.procedureRun?.procedure.title ?? '-'}</span>
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

  </Sidebar>

  <div class="main">
    {#if videoLoading}
      <div class="placeholder">Loading…</div>

    {:else if videoUrl}
      <div class="video-wrap">
        <!-- svelte-ignore a11y_media_has_caption -->
        <video src={videoUrl} controls class="video-player"></video>
      </div>

    {:else if hasVideo}
      <div class="placeholder">Failed to load video.</div>

    {:else}
      <div class="placeholder">No video recording for this log.</div>
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

  /* Video */
  .video-wrap {
    flex: 1;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--bg);
    padding: 32px;
  }
  .video-player {
    max-width: 100%;
    max-height: 100%;
    outline: none;
    border: 1px solid var(--accent);
    border-radius: 8px;
    box-shadow: 0 0 32px #00d4ff22;
  }
</style>
