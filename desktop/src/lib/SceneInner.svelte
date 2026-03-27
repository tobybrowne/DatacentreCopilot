<script>
  import { T } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity } from '@threlte/extras'
  import { createEventDispatcher } from 'svelte'

  export let glbUrl
  export let anchors = []
  export let selectedId = null
  export let pendingPosition = null
  export let mappingAnchor = null

  const dispatch = createEventDispatcher()

  interactivity()

  function handleMeshClick(e) {
    const point = e.point ?? e.detail?.point
    if (!point) return
    dispatch('place', { x: point.x, y: point.y, z: point.z })
  }

  function handleAnchorClick(e, id) {
    dispatch('select', id)
  }

  function sphereColor(anchor) {
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

{#if glbUrl}
  <GLTF url={glbUrl} on:dblclick={handleMeshClick} />
{/if}

<!-- World origin marker: pink sphere + RGB axis lines (X=red, Y=green, Z=blue) -->
<T.Mesh position={[0, 0, 0]}>
  <T.SphereGeometry args={[0.04, 12, 12]} />
  <T.MeshStandardMaterial color="#ff0066" emissive="#ff0066" emissiveIntensity={0.8} />
</T.Mesh>
<T.AxesHelper args={[0.4]} />

<!-- Anchors with a known glb_position -->
{#each anchors.filter(a => a.glb_position) as anchor (anchor.id)}
  {@const pos = anchor.glb_position}
  <T.Mesh
    position={[pos.x, pos.y, pos.z]}
    on:click={(e) => handleAnchorClick(e, anchor.id)}
  >
    <T.SphereGeometry args={[0.06, 16, 16]} />
    <T.MeshStandardMaterial
      color={sphereColor(anchor)}
      emissiveIntensity={0.3}
    />
  </T.Mesh>
{/each}

<!-- Ghost sphere while placing a new content anchor -->
{#if pendingPosition}
  <T.Mesh position={[pendingPosition.x, pendingPosition.y, pendingPosition.z]}>
    <T.SphereGeometry args={[0.06, 16, 16]} />
    <T.MeshStandardMaterial color="#ffffff" transparent opacity={0.5} />
  </T.Mesh>
{/if}
