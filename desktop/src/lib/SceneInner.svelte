<script lang="ts">
  import { T, useTask } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity } from '@threlte/extras'
  import { createEventDispatcher } from 'svelte'
  import * as THREE from 'three'
  import type { Anchor, Position, RigidTransform } from './types'

  export let glbUrl: string | null = null
  export let anchors: Anchor[] = []
  export let selectedId: string | null = null
  export let pendingPosition: Position | null = null
  export let mappingAnchor: Anchor | null = null
  export let userPosition: Position | null = null

  export let stitchPhase: 'idle' | 'pickSource' | 'pickTarget' | 'preview' = 'idle'
  export let stitchSourceGlbUrl: string | null = null
  export let stitchTargetGlbUrl: string | null = null
  export let stitchSourcePoints: Position[] = []
  export let stitchTargetPoints: Position[] = []
  export let stitchTransform: RigidTransform | null = null

  const dispatch = createEventDispatcher<{
    place: Position
    select: string
  }>()

  interactivity()

  // Group ref for applying the computed transform to source mesh in preview
  let sourceGroup: THREE.Group | undefined

  $: if (sourceGroup && stitchTransform && stitchPhase === 'preview') {
    const { position: p, quaternion: q } = stitchTransform
    sourceGroup.position.set(p.x, p.y, p.z)
    sourceGroup.quaternion.set(q.x, q.y, q.z, q.w)
  }

  // Source points transformed into target space for the preview overlay
  $: transformedSourcePoints = (stitchPhase === 'preview' && stitchTransform)
    ? stitchSourcePoints.map(p => {
        const v = new THREE.Vector3(p.x, p.y, p.z)
        const q = new THREE.Quaternion(
          stitchTransform!.quaternion.x, stitchTransform!.quaternion.y,
          stitchTransform!.quaternion.z, stitchTransform!.quaternion.w
        )
        v.applyQuaternion(q)
        v.x += stitchTransform!.position.x
        v.y += stitchTransform!.position.y
        v.z += stitchTransform!.position.z
        return v
      })
    : []

  function handleMeshClick(e: any): void {
    e.stopPropagation()
    const point = e.point ?? e.detail?.point
    if (!point) return
    dispatch('place', { x: point.x, y: point.y, z: point.z })
  }

  function handleAnchorClick(_e: unknown, id: string): void {
    dispatch('select', id)
  }

  function sphereColor(anchor: Anchor): string {
    if (mappingAnchor?.id === anchor.id) return '#ffffff'
    if (anchor.id === selectedId) return '#ff8800'
    if (anchor.is_reference) return '#ffcc00'
    return anchor.ml2_id ? '#88ff88' : '#00d4ff'
  }
</script>

<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} castShadow />

<T.PerspectiveCamera makeDefault position={[0, 2, 5]} fov={60}>
  <OrbitControls minDistance={0.5} />
</T.PerspectiveCamera>

<!-- World origin marker -->
<T.Mesh position={[0, 0, 0]}>
  <T.SphereGeometry args={[0.04, 12, 12]} />
  <T.MeshStandardMaterial color="#ff0066" emissive="#ff0066" emissiveIntensity={0.8} />
</T.Mesh>
<T.AxesHelper args={[0.4]} />

<!-- ── Normal viewing mode ── -->
{#if stitchPhase === 'idle'}
  {#if glbUrl}
    <GLTF url={glbUrl} on:dblclick={handleMeshClick} />
  {/if}

  {#each anchors.filter(a => a.glb_position) as anchor (anchor.id)}
    {@const pos = anchor.glb_position}
    <T.Mesh
      position={[pos.x, pos.y, pos.z]}
      on:click={(e) => handleAnchorClick(e, anchor.id)}
    >
      <T.SphereGeometry args={[0.06, 16, 16]} />
      <T.MeshStandardMaterial color={sphereColor(anchor)} emissiveIntensity={0.3} />
    </T.Mesh>
  {/each}

  {#if userPosition}
    {#key userPosition}
      <T.Mesh position={[userPosition.x, userPosition.y, userPosition.z]}>
        <T.SphereGeometry args={[0.08, 16, 16]} />
        <T.MeshStandardMaterial color="#ff4dff" emissive="#ff4dff" emissiveIntensity={0.6} />
      </T.Mesh>
    {/key}
  {/if}

  {#if pendingPosition}
    <T.Mesh position={[pendingPosition.x, pendingPosition.y, pendingPosition.z]}>
      <T.SphereGeometry args={[0.06, 16, 16]} />
      <T.MeshStandardMaterial color="#ffffff" transparent opacity={0.5} />
    </T.Mesh>
  {/if}
{/if}

<!-- ── Stitch: pick source points ── -->
{#if stitchPhase === 'pickSource' && stitchSourceGlbUrl}
  <GLTF url={stitchSourceGlbUrl} on:dblclick={handleMeshClick} />
  {#each stitchSourcePoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.05, 12, 12]} />
      <T.MeshStandardMaterial color="#ff4444" emissive="#ff4444" emissiveIntensity={0.6} />
    </T.Mesh>
  {/each}
{/if}

<!-- ── Stitch: pick target points ── -->
{#if stitchPhase === 'pickTarget' && stitchTargetGlbUrl}
  <GLTF url={stitchTargetGlbUrl} on:dblclick={handleMeshClick} />
  {#each stitchTargetPoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.05, 12, 12]} />
      <T.MeshStandardMaterial color="#44ffcc" emissive="#44ffcc" emissiveIntensity={0.6} />
    </T.Mesh>
  {/each}
{/if}

<!-- ── Stitch: preview (both meshes, source transformed) ── -->
{#if stitchPhase === 'preview'}
  <!-- Target at origin (reference) -->
  {#if stitchTargetGlbUrl}
    <GLTF url={stitchTargetGlbUrl} />
  {/if}
  <!-- Source with computed transform applied -->
  {#if stitchSourceGlbUrl}
    <T.Group bind:ref={sourceGroup}>
      <GLTF url={stitchSourceGlbUrl} />
    </T.Group>
  {/if}

  <!-- Target points (cyan) at original positions -->
  {#each stitchTargetPoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.06, 12, 12]} />
      <T.MeshStandardMaterial color="#44ffcc" emissive="#44ffcc" emissiveIntensity={0.8} />
    </T.Mesh>
  {/each}

  <!-- Source points transformed into target space — should overlap the cyan ones -->
  {#each transformedSourcePoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.06, 12, 12]} />
      <T.MeshStandardMaterial color="#ff4444" emissive="#ff4444" emissiveIntensity={0.8} />
    </T.Mesh>
  {/each}
{/if}
