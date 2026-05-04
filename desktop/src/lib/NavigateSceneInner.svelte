<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity, type IntersectionEvent } from '@threlte/extras'
  import * as THREE from 'three'
  import BoundingBoxMesh from './BoundingBoxMesh.svelte'
  import type { BoundingBox, Position, RigidTransform } from './types'

  interface Props {
    spaces: Array<{ url: string; transform: RigidTransform | null; boundingBox?: BoundingBox | null }>;
    showBoundingBoxes?: boolean;
    startPos?: Position | null;
    endPos?: Position | null;
    pathGeometry?: THREE.TubeGeometry | null;
    navMeshMesh?: THREE.Mesh | null;
    recastInputDebug?: THREE.Group | null;
    pickingEnabled?: boolean;
    onplace?: (pos: Position) => void;
  }

  let {
    spaces,
    showBoundingBoxes = false,
    startPos = null,
    endPos = null,
    pathGeometry = null,
    navMeshMesh = null,
    recastInputDebug = null,
    pickingEnabled = false,
    onplace
  }: Props = $props();

  interactivity()

  function handleClick(e: IntersectionEvent<MouseEvent>): void {
    if (!pickingEnabled) return
    e.stopPropagation()
    const point: THREE.Vector3 = e.point
    if (!point) return
    onplace?.({ x: point.x, y: point.y, z: point.z })
  }

  // Per-space group refs for applying quaternion transforms
  let groupRefs: (THREE.Group | undefined)[] = $state([])

  $effect(() => {
    spaces.forEach((space, i) => {
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
  })
</script>

<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} />

<T.PerspectiveCamera makeDefault position={[0, 2, 5]} fov={60}>
  <OrbitControls minDistance={0.5} screenSpacePanning={true} />
</T.PerspectiveCamera>

{#each spaces as space, i (space.url)}
  <T.Group bind:ref={groupRefs[i]}>
    <GLTF url={space.url} onclick={handleClick} />
    {#if showBoundingBoxes && space.boundingBox}
      <BoundingBoxMesh boundingBox={space.boundingBox} />
    {/if}
  </T.Group>
{/each}

{#if startPos}
  <T.Mesh position={[startPos.x, startPos.y + 0.1, startPos.z]}>
    <T.SphereGeometry args={[0.12, 16, 16]} />
    <T.MeshStandardMaterial color={0x00ff88} emissive={0x00ff88} emissiveIntensity={0.8} />
  </T.Mesh>
{/if}

{#if endPos}
  <T.Mesh position={[endPos.x, endPos.y + 0.1, endPos.z]}>
    <T.SphereGeometry args={[0.12, 16, 16]} />
    <T.MeshStandardMaterial color={0xff4444} emissive={0xff4444} emissiveIntensity={0.8} />
  </T.Mesh>
{/if}

{#if pathGeometry}
  <T.Mesh geometry={pathGeometry}>
    <T.MeshStandardMaterial color={0x00d4ff} emissive={0x00d4ff} emissiveIntensity={0.6} />
  </T.Mesh>
{/if}

{#if navMeshMesh}
  <T is={navMeshMesh} />
{/if}

{#if recastInputDebug}
  <T is={recastInputDebug} />
{/if}
