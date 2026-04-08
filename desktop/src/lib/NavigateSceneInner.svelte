<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity } from '@threlte/extras'
  import { createEventDispatcher } from 'svelte'
  import * as THREE from 'three'
  import type { Position, RigidTransform } from './types'

  export let spaces: Array<{ url: string; transform: RigidTransform | null }>
  export let startPos: Position | null = null
  export let endPos: Position | null = null
  export let pathGeometry: THREE.TubeGeometry | null = null
  export let navMeshMesh: THREE.Mesh | null = null
  export let recastInputDebug: THREE.Group | null = null
  export let pickingEnabled = false

  const dispatch = createEventDispatcher<{ place: Position }>()

  interactivity()

  function handleClick(e: any): void {
    if (!pickingEnabled) return
    e.stopPropagation()
    const point: THREE.Vector3 = e.point ?? e.detail?.point
    if (!point) return
    dispatch('place', { x: point.x, y: point.y, z: point.z })
  }

  // Per-space group refs for applying quaternion transforms
  let groupRefs: (THREE.Group | undefined)[] = []

  $: spaces.forEach((space, i) => {
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
</script>

<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} />

<T.PerspectiveCamera makeDefault position={[0, 2, 5]} fov={60}>
  <OrbitControls minDistance={0.5} screenSpacePanning={true} />
</T.PerspectiveCamera>

{#each spaces as space, i (space.url)}
  <T.Group bind:ref={groupRefs[i]}>
    <GLTF url={space.url} on:click={handleClick} />
  </T.Group>
{/each}

{#if startPos}
  <T.Mesh position={[startPos.x, startPos.y + 0.1, startPos.z]}>
    <T.SphereGeometry args={[0.12, 16, 16]} />
    <T.MeshStandardMaterial color="#00ff88" emissive="#00ff88" emissiveIntensity={0.8} />
  </T.Mesh>
{/if}

{#if endPos}
  <T.Mesh position={[endPos.x, endPos.y + 0.1, endPos.z]}>
    <T.SphereGeometry args={[0.12, 16, 16]} />
    <T.MeshStandardMaterial color="#ff4444" emissive="#ff4444" emissiveIntensity={0.8} />
  </T.Mesh>
{/if}

{#if pathGeometry}
  <T.Mesh geometry={pathGeometry}>
    <T.MeshStandardMaterial color="#00d4ff" emissive="#00d4ff" emissiveIntensity={0.6} />
  </T.Mesh>
{/if}

{#if navMeshMesh}
  <T is={navMeshMesh} />
{/if}

{#if recastInputDebug}
  <T is={recastInputDebug} />
{/if}
