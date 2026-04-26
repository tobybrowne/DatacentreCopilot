<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity } from '@threlte/extras'
  import { createEventDispatcher } from 'svelte'
  import * as THREE from 'three'
  import TransformedGltf from './TransformedGltf.svelte'
  import type { Anchor, Position, RigidTransform } from './types'

  export let glbUrl: string | null = null
  export let anchors: Anchor[] = []
  export let selectedId: string | null = null
  export let pendingPosition: Position | null = null
  export let mappingAnchor: Anchor | null = null
  export let userPosition: Position | null = null

  export let stitchPhase: 'idle' | 'pickSource' | 'pickTarget' | 'preview' = 'idle'
  export let stitchSourceGlbUrl: string | null = null
  // All spaces already stitched into the building (shown as the "target" model)
  export let mergedSpaces: Array<{ url: string; transform: RigidTransform | null }> = []
  export let stitchSourcePoints: Position[] = []
  export let stitchTargetPoints: Position[] = []
  export let stitchTransform: RigidTransform | null = null
  export let pointClouds: Array<{ points: Position[]; color: string }> = []
  export let mergedSpacesClickable = false

  // allows for this component to emit events to the parent
  // parents can use on:place and on:select to listen for these events
  // so the anchor specific or stitching specific logic can be handled in the parent component instead of here
  const dispatch = createEventDispatcher<{ place: { position: Position; spaceIndex: number | null }; select: string }>()

  interactivity()

  // Source group ref for applying transform in preview
  let sourceGroup: THREE.Group | undefined

  $: if (sourceGroup && stitchTransform && stitchPhase === 'preview') {
    const { position: p, quaternion: q } = stitchTransform
    sourceGroup.position.set(p.x, p.y, p.z)
    sourceGroup.quaternion.set(q.x, q.y, q.z, q.w)
  }

  // Source points transformed into target space for preview overlap check
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

  function handleMeshClick(e: any, spaceIndex: number | null = null): void {
    console.log('[SceneInner] handleMeshClick called, spaceIndex:', spaceIndex, 'e:', e)
    e.stopPropagation()
    const point = e.point ?? e.detail?.point
    console.log('[SceneInner] point:', point)
    if (!point) return
    dispatch('place', { position: { x: point.x, y: point.y, z: point.z }, spaceIndex })
  }

  function handleAnchorClick(_e: unknown, id: string): void {
    dispatch('select', id)
  }

  function sphereColor(anchor: Anchor): string {
    if (mappingAnchor?.id === anchor.id) return '#ffffff'
    if (anchor.id === selectedId) return '#ff8800'
    if (anchor.anchor_type === 'reference') return '#ffcc00'
    return anchor.ml2_id ? '#88ff88' : '#00d4ff'
  }
</script>


<!-- generic scene setting, define lighting and add axis helper at 0,0,0 -->
<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} castShadow />

<T.PerspectiveCamera makeDefault position={[0, 2, 5]} fov={60}>
  <OrbitControls minDistance={0.5} screenSpacePanning={true} />
</T.PerspectiveCamera>

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

  {#each mergedSpaces as space, i (space.url)}
    <TransformedGltf
      url={space.url}
      transform={space.transform}
      clickable={mergedSpacesClickable}
      on:click={(e) => handleMeshClick(e, i)}
    />
  {/each}

  {#each anchors.filter(a => a.glb_position) as anchor (anchor.id)}
    {@const pos = anchor.glb_position}
    <T.Mesh position={[pos.x, pos.y, pos.z]} on:click={(e) => handleAnchorClick(e, anchor.id)}>
      <T.SphereGeometry args={[0.06, 16, 16]} />
      <T.MeshStandardMaterial color={sphereColor(anchor)} emissiveIntensity={0.3} />
    </T.Mesh>
  {/each}

  {#each pointClouds as cloud}
    {@const geo = new THREE.BufferGeometry()}
    {@const _ = geo.setAttribute('position', new THREE.Float32BufferAttribute(cloud.points.flatMap(p => [p.x, p.y, p.z]), 3))}
    <T.Points geometry={geo}>
      <T.PointsMaterial color={cloud.color} size={0.03} sizeAttenuation={true} />
    </T.Points>
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

<!-- ── Stitch: pick source points (show new space only) ── -->
  {#if stitchPhase === 'pickSource' && stitchSourceGlbUrl}
    <!-- display GLB, use handleMeshClick to allow for adding stitch points -->
    <GLTF url={stitchSourceGlbUrl} on:dblclick={handleMeshClick} />

    <!-- display the stitch sphere -->
    {#each stitchSourcePoints as pt}
      <T.Mesh position={[pt.x, pt.y, pt.z]}>
        <T.SphereGeometry args={[0.05, 12, 12]} />
        <T.MeshStandardMaterial color="#ff4444" emissive="#ff4444" emissiveIntensity={0.6} />
      </T.Mesh>
    {/each}
{/if}

<!-- ── Stitch: pick target points (show full merged model so far) ── -->
{#if stitchPhase === 'pickTarget'}
  {#each mergedSpaces as space, i (space.url)}
    <TransformedGltf url={space.url} transform={space.transform} clickable={true} on:dblclick={(e) => handleMeshClick(e, i)} />
  {/each}
  {#each stitchTargetPoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.05, 12, 12]} />
      <T.MeshStandardMaterial color="#44ffcc" emissive="#44ffcc" emissiveIntensity={0.6} />
    </T.Mesh>
  {/each}
{/if}

<!-- ── Stitch: preview (merged model + new space with computed transform) ── -->
{#if stitchPhase === 'preview'}
  {#each mergedSpaces as space (space.url)}
    <TransformedGltf url={space.url} transform={space.transform} />
  {/each}

  {#if stitchSourceGlbUrl}
    <T.Group bind:ref={sourceGroup}>
      <GLTF url={stitchSourceGlbUrl} />
    </T.Group>
  {/if}

  <!-- Target points (cyan) -->
  {#each stitchTargetPoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.06, 12, 12]} />
      <T.MeshStandardMaterial color="#44ffcc" emissive="#44ffcc" emissiveIntensity={0.8} />
    </T.Mesh>
  {/each}

  <!-- Source points transformed into target space (should overlap cyan) -->
  {#each transformedSourcePoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.06, 12, 12]} />
      <T.MeshStandardMaterial color="#ff4444" emissive="#ff4444" emissiveIntensity={0.8} />
    </T.Mesh>
  {/each}
{/if}
