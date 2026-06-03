<script lang="ts">
  // Shared 3D viewport: the <Canvas>, an optional white-bg overlay toggle, and
  // an optional Export-PNG button. The scene content is passed as a snippet and
  // receives { whiteBackground, exportTrigger, onexportblob } to wire through to
  // its inner scene component.
  import { Canvas } from '@threlte/core'
  import ExportButton from './ExportButton.svelte'
  import type { Snippet } from 'svelte'

  interface Props {
    canExport?: boolean;
    showBgToggle?: boolean;
    whiteBackground?: boolean;
    exportName?: string;
    rendererParameters?: Record<string, unknown>;
    children: Snippet<[{ whiteBackground: boolean; exportTrigger: number; onexportblob: (blob: Blob) => void }]>;
  }

  let {
    canExport = false,
    showBgToggle = true,
    whiteBackground = $bindable(false),
    exportName = 'scene',
    rendererParameters,
    children,
  }: Props = $props()

  let exportTrigger = $state(0)

  function onexportblob(blob: Blob): void {
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${exportName}.png`
    a.click()
    URL.revokeObjectURL(url)
  }
</script>

<div class="canvas-wrap">
  <Canvas {rendererParameters}>
    {@render children({ whiteBackground, exportTrigger, onexportblob })}
  </Canvas>
  {#if showBgToggle}
    <button class="overlay-btn" onclick={() => (whiteBackground = !whiteBackground)}>
      {whiteBackground ? 'Dark' : 'White'} bg
    </button>
  {/if}
  {#if canExport}
    <ExportButton onclick={() => exportTrigger++} style={showBgToggle ? 'bottom: 44px' : ''} />
  {/if}
</div>

<style>
  .canvas-wrap {
    flex: 1;
    height: 100%;
    overflow: hidden;
    position: relative;
  }

  .overlay-btn {
    position: absolute;
    bottom: 12px;
    right: 12px;
    padding: 4px 10px;
    font-size: 12px;
    background: rgba(0, 0, 0, 0.4);
    color: white;
    border: 1px solid rgba(255, 255, 255, 0.2);
    border-radius: 4px;
    cursor: pointer;
  }
  .overlay-btn:hover {
    background: rgba(0, 0, 0, 0.6);
  }
</style>
