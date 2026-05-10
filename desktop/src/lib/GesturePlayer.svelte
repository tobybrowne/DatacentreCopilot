<script lang="ts">
  import { T, useThrelte } from '@threlte/core'
  import * as THREE from 'three'
  import type { GestureRecording } from './types'

  interface Props {
    recording: GestureRecording
    playbackMs: number
  }

  let { recording, playbackMs }: Props = $props()
  const { invalidate } = useThrelte()

  // OpenXR hand joint connections for skeleton visualization
  const CONNECTIONS: [number, number][] = [
    [0, 1],                               // palm → wrist
    [1, 2], [2, 3], [3, 4], [4, 5],      // wrist → thumb tip
    [1, 6], [6, 7], [7, 8], [8, 9], [9, 10],   // index
    [1, 11], [11, 12], [12, 13], [13, 14], [14, 15], // middle
    [1, 16], [16, 17], [17, 18], [18, 19], [19, 20], // ring
    [1, 21], [21, 22], [22, 23], [23, 24], [24, 25], // pinky
  ]
  const NC = CONNECTIONS.length

  // Frame layout (639 elements per row):
  //   [0]       timestamp_msec
  //   [1..12]   head transform (12 floats: basis 9 + origin 3)
  //   [13..324] left joints (26 × 12)
  //   [325..636] right joints (26 × 12)
  //   [637]     left_tracked
  //   [638]     right_tracked
  const HEAD_OFF  = 1
  const LEFT_OFF  = 13
  const RIGHT_OFF = 325

  function readPos(frame: number[], off: number): THREE.Vector3 {
    return new THREE.Vector3(frame[off + 9], frame[off + 10], frame[off + 11])
  }

  function findFrameIndex(ms: number): number {
    const frames = recording.frames
    if (!frames.length) return 0
    const target = frames[0][0] + ms
    let lo = 0, hi = frames.length - 1
    while (lo < hi) {
      const mid = (lo + hi) >> 1
      if (frames[mid][0] < target) lo = mid + 1
      else hi = mid
    }
    return Math.min(lo, frames.length - 1)
  }

  function makeLines(color: number): THREE.LineSegments {
    const geo = new THREE.BufferGeometry()
    geo.setAttribute('position', new THREE.BufferAttribute(new Float32Array(NC * 6), 3))
    return new THREE.LineSegments(geo, new THREE.LineBasicMaterial({ color }))
  }

  const headMesh = new THREE.Mesh(
    new THREE.SphereGeometry(0.1, 12, 8),
    new THREE.MeshStandardMaterial({
      color: 0x00d4ff,
      emissive: 0x00d4ff,
      emissiveIntensity: 0.4,
    })
  )

  const leftLines  = makeLines(0x00d4ff)
  const rightLines = makeLines(0xff8844)

  function updateLines(lines: THREE.LineSegments, joints: THREE.Vector3[]): void {
    const buf = (lines.geometry.getAttribute('position') as THREE.BufferAttribute)
      .array as Float32Array
    for (let i = 0; i < NC; i++) {
      const [a, b] = CONNECTIONS[i]
      buf[i * 6 + 0] = joints[a].x; buf[i * 6 + 1] = joints[a].y; buf[i * 6 + 2] = joints[a].z
      buf[i * 6 + 3] = joints[b].x; buf[i * 6 + 4] = joints[b].y; buf[i * 6 + 5] = joints[b].z
    }
    ;(lines.geometry.getAttribute('position') as THREE.BufferAttribute).needsUpdate = true
  }

  $effect(() => {
    const fi = findFrameIndex(playbackMs)
    const f = recording.frames[fi]
    if (!f) return

    headMesh.position.copy(readPos(f, HEAD_OFF))

    if (f[637] === 1) {
      updateLines(leftLines, Array.from({ length: 26 }, (_, i) => readPos(f, LEFT_OFF + i * 12)))
      leftLines.visible = true
    } else {
      leftLines.visible = false
    }

    if (f[638] === 1) {
      updateLines(rightLines, Array.from({ length: 26 }, (_, i) => readPos(f, RIGHT_OFF + i * 12)))
      rightLines.visible = true
    } else {
      rightLines.visible = false
    }

    invalidate()
  })
</script>

<T is={headMesh} />
<T is={leftLines} />
<T is={rightLines} />
