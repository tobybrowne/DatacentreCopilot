<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF, OrbitControls, interactivity, type IntersectionEvent } from '@threlte/extras'
  import * as THREE from 'three'
  import TransformedGltf from './TransformedGltf.svelte'
  import BoundingBoxMesh from './BoundingBoxMesh.svelte'
  import DensityHeatmap from './DensityHeatmap.svelte'
  import type { Anchor, BoundingBox, Position, RigidTransform } from './types'



  interface Props {
    glbUrl?: string | null;
    anchors?: Anchor[];
    selectedId?: string | null;
    pendingPosition?: Position | null;
    mappingAnchor?: Anchor | null;
    userPosition?: Position | null;
    boundingBox?: BoundingBox | null;
    showBoundingBoxes?: boolean;
    stitchPhase?: 'idle' | 'pickSource' | 'pickTarget' | 'preview';
    stitchSourceGlbUrl?: string | null;
    // All spaces already stitched into the building (shown as the "target" model)
    mergedSpaces?: Array<{ url: string; transform: RigidTransform | null }>;
    stitchSourcePoints?: Position[];
    stitchTargetPoints?: Position[];
    stitchTransform?: RigidTransform | null;
    pointClouds?: Array<{ points: Position[]; color: number }>;
    mergedSpacesClickable?: boolean;
    showDensity?: boolean;
    onplace?: (detail: { position: Position; spaceIndex: number | null }) => void;
    onselect?: (id: string) => void;
  }

  let {
    glbUrl = null,
    anchors = [],
    selectedId = null,
    pendingPosition = null,
    mappingAnchor = null,
    userPosition = null,
    boundingBox = null,
    showBoundingBoxes = false,
    stitchPhase = 'idle',
    stitchSourceGlbUrl = null,
    mergedSpaces = [],
    stitchSourcePoints = [],
    stitchTargetPoints = [],
    stitchTransform = null,
    pointClouds = [],
    mergedSpacesClickable = false,
    showDensity = false,
    onplace,
    onselect
  }: Props = $props();

  interactivity()

  // Source group ref for applying transform in preview
  let sourceGroup: THREE.Group | undefined = $state()

  $effect(() => {
    if (sourceGroup && stitchTransform && stitchPhase === 'preview') {
      const { position: p, quaternion: q } = stitchTransform
      sourceGroup.position.set(p.x, p.y, p.z)
      sourceGroup.quaternion.set(q.x, q.y, q.z, q.w)
    }
  })

  // Source points transformed into target space for preview overlap check
  let transformedSourcePoints = $derived((stitchPhase === 'preview' && stitchTransform)
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
    : [])

  function handleMeshClick(point: THREE.Vector3, spaceIndex: number | null = null): void {
    onplace?.({ position: { x: point.x, y: point.y, z: point.z }, spaceIndex })
  }

  function handleAnchorClick(id: string): void {
    onselect?.(id)
  }

  function sphereColor(anchor: Anchor): number {
    if (mappingAnchor?.id === anchor.id) return 0xffffff
    if (anchor.id === selectedId) return 0xff8800
    if (anchor.anchor_type === 'reference') return 0xffcc00
    return anchor.ml2_id ? 0x88ff88 : 0x00d4ff
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
  <T.MeshStandardMaterial color={0xff0066} emissive={0xff0066} emissiveIntensity={0.8} />
</T.Mesh>
<T.AxesHelper args={[0.4]} />

<!-- ── Normal viewing mode ── -->
{#if stitchPhase === 'idle'}
  {#if glbUrl}
    <GLTF url={glbUrl} onclick={(e: IntersectionEvent<MouseEvent>) => { e.stopPropagation(); if (e.point) handleMeshClick(e.point) }} />
  {/if}

  {#if showDensity && glbUrl}
    <DensityHeatmap {glbUrl} />
  {/if}

  {#if showBoundingBoxes && boundingBox}
    <BoundingBoxMesh {boundingBox} />
  {/if}

  {#each mergedSpaces as space, i (space.url)}
    <TransformedGltf
      url={space.url}
      transform={space.transform}
      clickable={mergedSpacesClickable}
      onclick={(e) => handleMeshClick(e.point, i)}
    />
  {/each}

  {#each anchors.filter(a => a.glb_position) as anchor (anchor.id)}
    {#if anchor.glb_position}
    <T.Mesh position={[anchor.glb_position.x, anchor.glb_position.y, anchor.glb_position.z]} onclick={(e: IntersectionEvent<MouseEvent>) => handleAnchorClick(anchor.id)}>
      <T.SphereGeometry args={[0.06, 16, 16]} />
      <T.MeshStandardMaterial color={sphereColor(anchor)} emissiveIntensity={0.3} />
    </T.Mesh>
    {/if}
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
        <T.MeshStandardMaterial color={0xff4dff} emissive={0xff4dff} emissiveIntensity={0.6} />
      </T.Mesh>
    {/key}
  {/if}

  {#if pendingPosition}
    <T.Mesh position={[pendingPosition.x, pendingPosition.y, pendingPosition.z]}>
      <T.SphereGeometry args={[0.06, 16, 16]} />
      <T.MeshStandardMaterial color={0xffffff} transparent opacity={0.5} />
    </T.Mesh>
  {/if}
{/if}

<!-- ── Stitch: pick source points (show new space only) ── -->
  {#if stitchPhase === 'pickSource' && stitchSourceGlbUrl}
    <!-- display GLB, use handleMeshClick to allow for adding stitch points -->
    <GLTF url={stitchSourceGlbUrl} ondblclick={(e: IntersectionEvent<MouseEvent>) => { e.stopPropagation(); if (e.point) handleMeshClick(e.point) }} />

    <!-- display the stitch sphere -->
    {#each stitchSourcePoints as pt}
      <T.Mesh position={[pt.x, pt.y, pt.z]}>
        <T.SphereGeometry args={[0.05, 12, 12]} />
        <T.MeshStandardMaterial color={0xff4444} emissive={0xff4444} emissiveIntensity={0.6} />
      </T.Mesh>
    {/each}
{/if}

<!-- ── Stitch: pick target points (show full merged model so far) ── -->
{#if stitchPhase === 'pickTarget'}
  {#each mergedSpaces as space, i (space.url)}
    <TransformedGltf url={space.url} transform={space.transform} clickable={true} ondblclick={(e) => handleMeshClick(e.point, i)} />
  {/each}
  {#each stitchTargetPoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.05, 12, 12]} />
      <T.MeshStandardMaterial color={0x44ffcc} emissive={0x44ffcc} emissiveIntensity={0.6} />
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
      <T.MeshStandardMaterial color={0x44ffcc} emissive={0x44ffcc} emissiveIntensity={0.8} />
    </T.Mesh>
  {/each}

  <!-- Source points transformed into target space (should overlap cyan) -->
  {#each transformedSourcePoints as pt}
    <T.Mesh position={[pt.x, pt.y, pt.z]}>
      <T.SphereGeometry args={[0.06, 12, 12]} />
      <T.MeshStandardMaterial color={0xff4444} emissive={0xff4444} emissiveIntensity={0.8} />
    </T.Mesh>
  {/each}
{/if}
