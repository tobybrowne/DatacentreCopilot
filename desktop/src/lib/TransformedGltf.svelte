<script lang="ts">
  // Shared GLB renderer for building/room scans. Loads a GLB, optionally applies a
  // rigid transform, and overrides its materials with the procedural "dollhouse"
  // shading (see scanMaterial.ts) so every scene gets the same hologram look from
  // one place.
  import { T, useTask, useThrelte } from '@threlte/core'
  import { GLTF, type IntersectionEvent } from '@threlte/extras'
  import { onDestroy } from 'svelte'
  import * as THREE from 'three'
  import type { RigidTransform } from './types'
  import { createScanMaterial, applyScanMaterial } from './scanMaterial'

  interface Props {
    url: string;
    transform?: RigidTransform | null;
    clickable?: boolean;
    /** Flat tint overlay, e.g. to mark the best-reference space in the stitch view. */
    highlight?: boolean;
    onclick?: (e: { point: THREE.Vector3 }) => void;
    ondblclick?: (e: { point: THREE.Vector3 }) => void;
  }

  let { url, transform = null, clickable = false, highlight = false, onclick, ondblclick }: Props = $props();

  const { invalidate } = useThrelte()
  let group = $state<THREE.Group | undefined>(undefined)
  const material = createScanMaterial()
  let shadedUrl: string | null = null

  $effect(() => {
    if (group) {
      if (transform) {
        group.position.set(transform.position.x, transform.position.y, transform.position.z)
        group.quaternion.set(transform.quaternion.x, transform.quaternion.y, transform.quaternion.z, transform.quaternion.w)
      } else {
        group.position.set(0, 0, 0)
        group.quaternion.identity()
      }
    }
  })

  // When the url changes the GLTF reloads, so re-apply the material to the new meshes.
  $effect(() => { url; shadedUrl = null })

  $effect(() => {
    material.uniforms.highlightStrength.value = highlight ? 0.18 : 0.0
    invalidate()
  })

  // GLTF loads asynchronously; keep trying until its meshes exist under the group.
  useTask(() => {
    if (!group || shadedUrl === url) return
    if (applyScanMaterial(group, material)) {
      shadedUrl = url
      invalidate()
    }
  })

  function handle(e: IntersectionEvent<MouseEvent>, type: 'click' | 'dblclick'): void {
    if (!clickable) return
    e.stopPropagation()
    const point: THREE.Vector3 | undefined = e.point
    if (!point) return
    if (type === 'click') onclick?.({ point })
    else ondblclick?.({ point })
  }

  onDestroy(() => material.dispose())
</script>

<T.Group bind:ref={group}>
  <GLTF {url}
    onclick={(e: IntersectionEvent<MouseEvent>) => handle(e, 'click')}
    ondblclick={(e: IntersectionEvent<MouseEvent>) => handle(e, 'dblclick')}
  />
</T.Group>
