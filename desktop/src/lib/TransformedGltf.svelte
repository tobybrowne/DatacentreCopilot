<script lang="ts">
  import { T } from '@threlte/core'
  import { GLTF } from '@threlte/extras'
  import { createEventDispatcher } from 'svelte'
  import * as THREE from 'three'
  import type { RigidTransform } from './types'

  export let url: string
  export let transform: RigidTransform | null = null
  export let clickable = false

  const dispatch = createEventDispatcher<{ dblclick: { point: THREE.Vector3 } }>()

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

  function handleClick(e: any): void {
    if (!clickable) return
    e.stopPropagation()
    // Threlte puts the point directly on e or in e.detail depending on context
    const point: THREE.Vector3 | undefined = e.point ?? e.detail?.point
    if (!point) return
    dispatch('dblclick', { point })
  }
</script>

<T.Group bind:ref={group}>
  <GLTF {url} on:dblclick={handleClick} />
</T.Group>
