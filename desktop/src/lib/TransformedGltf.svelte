<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF } from '@threlte/extras'
  import { createEventDispatcher } from 'svelte'
  import * as THREE from 'three'
  import type { RigidTransform } from './types'

  export let url: string
  export let transform: RigidTransform | null = null
  export let clickable = false

  const dispatch = createEventDispatcher<{
    click: { point: THREE.Vector3 }
    dblclick: { point: THREE.Vector3 }
  }>()

  let group: THREE.Group

  $: if (group) {
    if (transform) {
      group.position.set(transform.position.x, transform.position.y, transform.position.z)
      group.quaternion.set(transform.quaternion.x, transform.quaternion.y, transform.quaternion.z, transform.quaternion.w)
    } else {
      group.position.set(0, 0, 0)
      group.quaternion.identity()
    }
  }

  function handle(e: any, type: 'click' | 'dblclick'): void {
    if (!clickable) return
    e.stopPropagation()
    const point: THREE.Vector3 | undefined = e.point ?? e.detail?.point
    if (!point) return
    dispatch(type, { point })
  }
</script>

<T.Group bind:ref={group}>
  <GLTF {url}
    on:click={(e) => handle(e, 'click')}
    on:dblclick={(e) => handle(e, 'dblclick')}
  />
</T.Group>
