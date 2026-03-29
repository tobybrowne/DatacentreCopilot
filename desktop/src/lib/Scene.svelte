<script lang="ts">
  import { Canvas } from '@threlte/core'
  import SceneInner from './SceneInner.svelte'
  import { createEventDispatcher } from 'svelte'
  import type { Anchor, Position } from './types'

  export let glbUrl: string | null = null
  export let anchors: Anchor[] = []
  export let selectedId: string | null = null
  export let pendingPosition: Position | null = null
  export let userPosition: Position | null = null

  const dispatch = createEventDispatcher<{
    place: Position
    select: string
  }>()
</script>

<div class="canvas-wrap">
  <Canvas>
    <SceneInner
      {glbUrl}
      {anchors}
      {selectedId}
      {pendingPosition}
      {userPosition}
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
