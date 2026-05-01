<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF, type IntersectionEvent } from '@threlte/extras'
  import * as THREE from 'three'
  import type { RigidTransform } from './types'

  interface Props {
    url: string;
    transform?: RigidTransform | null;
    clickable?: boolean;
    onclick?: (e: { point: THREE.Vector3 }) => void;
    ondblclick?: (e: { point: THREE.Vector3 }) => void;
  }

  let { url, transform = null, clickable = false, onclick, ondblclick }: Props = $props();

  let group = $state<THREE.Group | undefined>(undefined)

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

  function handle(e: IntersectionEvent<MouseEvent>, type: 'click' | 'dblclick'): void {
    if (!clickable) return
    e.stopPropagation()
    const point: THREE.Vector3 | undefined = e.point
    if (!point) return
    if (type === 'click') onclick?.({ point })
    else ondblclick?.({ point })
  }
</script>

<T.Group bind:ref={group}>
  <GLTF {url}
    onclick={(e: IntersectionEvent<MouseEvent>) => handle(e, 'click')}
    ondblclick={(e: IntersectionEvent<MouseEvent>) => handle(e, 'dblclick')}
  />
</T.Group>
