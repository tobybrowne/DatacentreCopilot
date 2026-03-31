<script lang="ts">
  import { Canvas } from '@threlte/core'
  import SceneInner from './SceneInner.svelte'
  import type { Anchor, Position, RigidTransform } from './types'

  export let glbUrl: string | null = null
  export let anchors: Anchor[] = []
  export let selectedId: string | null = null
  export let pendingPosition: Position | null = null
  export let userPosition: Position | null = null

  // stitch mode
  export let stitchPhase: 'idle' | 'pickSource' | 'pickTarget' | 'preview' = 'idle'
  export let stitchSourceGlbUrl: string | null = null
  export let mergedSpaces: Array<{ url: string; transform: RigidTransform | null }> = []
  export let stitchSourcePoints: Position[] = []
  export let stitchTargetPoints: Position[] = []
  export let stitchTransform: RigidTransform | null = null
</script>

<div class="canvas-wrap">
  <Canvas>
    <SceneInner
      {glbUrl}
      {anchors}
      {selectedId}
      {pendingPosition}
      {userPosition}
      {stitchPhase}
      {stitchSourceGlbUrl}
      {mergedSpaces}
      {stitchSourcePoints}
      {stitchTargetPoints}
      {stitchTransform}
      on:place
      on:select
    />
  </Canvas>
</div>

<style>
  .canvas-wrap {
    flex: 1;
    height: 100vh;
    overflow: hidden;
  }
</style>
