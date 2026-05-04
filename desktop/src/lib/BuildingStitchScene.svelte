<script lang="ts">
  import { T, useThrelte, useTask } from '@threlte/core'
  import { GLTF, OrbitControls } from '@threlte/extras'
  import { onDestroy, untrack } from 'svelte'
  import * as THREE from 'three'
  import { TransformControls } from 'three/addons/controls/TransformControls.js'
  import BoundingBoxMesh from './BoundingBoxMesh.svelte'
  import type { BoundingBox, RigidTransform } from './types'

  interface Props {
    builtSpaces: Array<{ url: string; transform: RigidTransform | null; boundingBox?: BoundingBox | null }>
    newSpaceUrl: string
    newX: number
    newZ: number
    newYRot: number
    newBoundingBox?: BoundingBox | null
    mode: 'translate' | 'rotate'
    showBoundingBoxes?: boolean
    bestReferenceIndex?: number | null
    ontransform: (x: number, z: number, yRot: number) => void
  }

  let { builtSpaces, newSpaceUrl, newX, newZ, newYRot, newBoundingBox = null, mode, showBoundingBoxes = false, bestReferenceIndex = null, ontransform }: Props = $props()

  const { renderer, camera, scene, invalidate } = useThrelte()

  let newGroup: THREE.Group | undefined = $state()
  let orbitEnabled = $state(true)
  let dragging = $state(false)
  let tc: TransformControls | null = $state(null)

  let groupRefs: (THREE.Group | undefined)[] = $state([])

  $effect(() => {
    builtSpaces.forEach((space, i) => {
      const g = groupRefs[i]
      if (!g) return
      if (space.transform) {
        const { position: p, quaternion: q } = space.transform
        g.position.set(p.x, p.y, p.z)
        g.quaternion.set(q.x, q.y, q.z, q.w)
      } else {
        g.position.set(0, 0, 0)
        g.quaternion.identity()
      }
    })
    invalidate()
  })

  $effect(() => {
    const x = newX, z = newZ, yRot = newYRot, group = newGroup
    if (!group || untrack(() => dragging)) return
    group.position.set(x, 0, z)
    group.rotation.set(0, yRot, 0)
    invalidate()
  })

  $effect(() => {
    if (!tc) return
    tc.setMode(mode)
    tc.showX = mode === 'translate'
    tc.showY = mode === 'rotate'
    tc.showZ = mode === 'translate'
  })

  // Extract yaw from a (pure-Y) quaternion. We can't use newGroup.rotation.y:
  // Three.js's XYZ Euler decomposition hits a singularity past ±90° and
  // re-expresses the rotation as (π, π−θ, π), so rotation.y silently lies.
  const getYaw = (q: THREE.Quaternion): number =>
    Math.atan2(2 * (q.w * q.y + q.x * q.z), 1 - 2 * (q.y * q.y + q.z * q.z))

  const onChange = () => {
    if (!newGroup) return
    ontransform(newGroup.position.x, newGroup.position.z, getYaw(newGroup.quaternion))
    invalidate()
  }

  const onDraggingChanged = (e: any) => {
    dragging = e.value
    orbitEnabled = !e.value
    if (!e.value && newGroup) {
      ontransform(newGroup.position.x, newGroup.position.z, getYaw(newGroup.quaternion))
    }
  }

  // Tint the best reference space mesh orange; runs every frame to catch async GLTF loads.
  let lastTintedIdx: number | null | undefined = undefined
  useTask(() => {
    const refIdx = bestReferenceIndex
    if (refIdx === lastTintedIdx) return
    let applied = false
    groupRefs.forEach((group, i) => {
      if (!group) return
      const want = i === refIdx
      group.traverse(obj => {
        if (!(obj instanceof THREE.Mesh) || !obj.material) return
        applied = true
        const mats: THREE.Material[] = Array.isArray(obj.material) ? obj.material : [obj.material]
        for (const mat of mats) {
          if ('emissive' in mat) {
            const m = mat as THREE.MeshStandardMaterial
            m.emissive.set(want ? 0xff8800 : 0x000000)
            m.emissiveIntensity = want ? 0.18 : 0
          } else {
            // MeshBasicMaterial — tint via color
            const m = mat as THREE.MeshBasicMaterial
            m.color.set(want ? 0xffaa55 : 0xffffff)
          }
        }
      })
    })
    if (applied) { lastTintedIdx = refIdx; invalidate() }
  })

  const { stop } = useTask(() => {
    if (tc || !newGroup) return
    const cam = camera.current
    if (!cam) return

    tc = new TransformControls(cam, renderer.domElement)
    tc.attach(newGroup)
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
    if (tc && newGroup) tc.attach(newGroup)
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

{#each builtSpaces as space, i (space.url)}
  <T.Group bind:ref={groupRefs[i]}>
    <GLTF url={space.url} />
    {#if showBoundingBoxes && space.boundingBox}
      <BoundingBoxMesh boundingBox={space.boundingBox} />
    {/if}
  </T.Group>
{/each}

<T.Group bind:ref={newGroup}>
  <GLTF url={newSpaceUrl} />
  {#if showBoundingBoxes && newBoundingBox}
    <BoundingBoxMesh boundingBox={newBoundingBox} color={0xffaa00} />
  {/if}
</T.Group>
