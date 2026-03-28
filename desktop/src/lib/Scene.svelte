<script>
  import { Canvas } from '@threlte/core'
  import SceneInner from './SceneInner.svelte'
  import { createEventDispatcher } from 'svelte'

  export let glbUrl
  export let anchors = []
  export let selectedId = null
  export let pendingPosition = null
  export let userPosition = null

  const dispatch = createEventDispatcher()
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
