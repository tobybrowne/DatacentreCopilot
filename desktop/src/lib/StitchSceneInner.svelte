<script lang="ts">
  import { T, useThrelte, useTask } from '@threlte/core'
  import { GLTF, OrbitControls } from '@threlte/extras'
  import { onDestroy } from 'svelte'
  import * as THREE from 'three'
  import { TransformControls } from 'three/addons/controls/TransformControls.js'

  interface Props {
    spaceAUrl: string | null
    spaceBUrl: string | null
    bX: number
    bZ: number
    bYRot: number
    mode: 'translate' | 'rotate'
    ontransform: (x: number, z: number, yRot: number) => void
  }

  let { spaceAUrl, spaceBUrl, bX, bZ, bYRot, mode, ontransform }: Props = $props()

  const { renderer, camera, scene, invalidate } = useThrelte()

  let bGroup: THREE.Group | undefined = $state()
  let orbitEnabled = $state(true)
  let dragging = $state(false)
  let tc: TransformControls | null = $state(null)

  $effect(() => {
    if (bGroup && !dragging) {
      bGroup.position.set(bX, 0, bZ)
      bGroup.rotation.set(0, bYRot, 0)
    }
  })

  $effect(() => {
    if (!tc) return
    tc.setMode(mode)
    tc.showX = mode === 'translate'
    tc.showY = mode === 'rotate'
    tc.showZ = mode === 'translate'
  })

  const onChange = () => {
    if (!bGroup) return
    ontransform(bGroup.position.x, bGroup.position.z, bGroup.rotation.y)
    invalidate()
  }

  const onDraggingChanged = (e: any) => {
    dragging = e.value
    orbitEnabled = !e.value
  }

  const { stop } = useTask(() => {
    if (tc || !bGroup) return
    const cam = camera.current
    if (!cam) return

    tc = new TransformControls(cam, renderer.domElement)
    tc.attach(bGroup)
    tc.size = 0.75
    scene.add(tc.getHelper())

    tc.addEventListener('change', onChange)
    tc.addEventListener('dragging-changed', onDraggingChanged)

    tc.setMode(mode)
    tc.showX = mode === 'translate'
    tc.showY = mode === 'rotate'
    tc.showZ = mode === 'translate'

    stop()
  })

  $effect(() => {
    if (tc && bGroup) tc.attach(bGroup)
  })

  onDestroy(() => {
    if (tc) {
      tc.removeEventListener('change', onChange)
      tc.removeEventListener('dragging-changed', onDraggingChanged)
      tc.detach()
      scene.remove(tc.getHelper())
      tc.dispose()
      tc = null
    }
  })
</script>

<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} />

<T.PerspectiveCamera makeDefault position={[0, 4, 8]} fov={60}>
  <OrbitControls enabled={orbitEnabled} minDistance={0.5} screenSpacePanning={true} />
</T.PerspectiveCamera>

{#if spaceAUrl}
  <GLTF url={spaceAUrl} />
{/if}

{#if spaceBUrl}
  <T.Group bind:ref={bGroup}>
    <GLTF url={spaceBUrl} />
  </T.Group>
{/if}
