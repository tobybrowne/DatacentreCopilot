<script lang="ts">
  import { Canvas } from '@threlte/core'
  import SceneInner from './SceneInner.svelte'
  import type { Anchor, BoundingBox, Position, RigidTransform } from './types'

  let whiteBackground = $state(false)

  interface Props {
    glbUrl?: string | null;
    anchors?: Anchor[];
    selectedId?: string | null;
    pendingPosition?: Position | null;
    mappingAnchor?: Anchor | null;
    userPosition?: Position | null;
    boundingBox?: BoundingBox | null;
    showBoundingBoxes?: boolean;
    // stitch mode
    stitchPhase?: 'idle' | 'pickSource' | 'pickTarget' | 'preview';
    stitchSourceGlbUrl?: string | null;
    mergedSpaces?: Array<{ url: string; transform: RigidTransform | null }>;
    stitchSourcePoints?: Position[];
    stitchTargetPoints?: Position[];
    stitchTransform?: RigidTransform | null;
    pointClouds?: Array<{ points: Position[]; color: number }>;
    mergedSpacesClickable?: boolean;
    showDensity?: boolean;
    draggableAnchorId?: string | null;
    canExport?: boolean;
    exportName?: string;
    onplace?: (detail: { position: Position; spaceIndex: number | null }) => void;
    onselect?: (id: string) => void;
    ondraganchor?: (id: string, pos: Position) => void;
  }

  let {
    glbUrl = null,
    anchors = [],
    selectedId = null,
    pendingPosition = null,
    mappingAnchor = null,
    userPosition = null,
    boundingBox = null,
    showBoundingBoxes = false,
    stitchPhase = 'idle',
    stitchSourceGlbUrl = null,
    mergedSpaces = [],
    stitchSourcePoints = [],
    stitchTargetPoints = [],
    stitchTransform = null,
    pointClouds = [],
    mergedSpacesClickable = false,
    showDensity = false,
    draggableAnchorId = null,
    canExport = false,
    exportName = 'space',
    onplace,
    onselect,
    ondraganchor
  }: Props = $props();

  let exportTrigger = $state(0)

  function exportPng(): void {
    exportTrigger++
  }

  function handleExportBlob(blob: Blob): void {
    const url = URL.createObjectURL(blob)
    const a = document.createElement('a')
    a.href = url
    a.download = `${exportName}.png`
    a.click()
    URL.revokeObjectURL(url)
  }
</script>

<div class="canvas-wrap">
  <Canvas>
    <SceneInner
      {glbUrl}
      {anchors}
      {selectedId}
      {pendingPosition}
      {mappingAnchor}
      {userPosition}
      {boundingBox}
      {showBoundingBoxes}
      {stitchPhase}
      {stitchSourceGlbUrl}
      {mergedSpaces}
      {stitchSourcePoints}
      {stitchTargetPoints}
      {stitchTransform}
      {pointClouds}
      {mergedSpacesClickable}
      {showDensity}
      {whiteBackground}
      {draggableAnchorId}
      {exportTrigger}
      exportScale={2}
      {onplace}
      {onselect}
      {ondraganchor}
      onexportblob={handleExportBlob}
    />
  </Canvas>
  <button class="bg-toggle" onclick={() => whiteBackground = !whiteBackground}>
    {whiteBackground ? 'Dark' : 'White'} bg
  </button>
  {#if canExport}
    <button class="bg-toggle" style="bottom: 44px" onclick={exportPng}>
      Export PNG
    </button>
  {/if}
</div>

<style>
  .canvas-wrap {
    flex: 1;
    height: 100%;
    overflow: hidden;
    position: relative;
  }

  .bg-toggle {
    position: absolute;
    bottom: 12px;
    right: 12px;
    padding: 4px 10px;
    font-size: 12px;
    background: rgba(0,0,0,0.4);
    color: white;
    border: 1px solid rgba(255,255,255,0.2);
    border-radius: 4px;
    cursor: pointer;
  }

  .bg-toggle:hover {
    background: rgba(0,0,0,0.6);
  }
</style>
