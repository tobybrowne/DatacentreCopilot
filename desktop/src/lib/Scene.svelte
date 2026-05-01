<script lang="ts">
  import { Canvas } from '@threlte/core'
  import SceneInner from './SceneInner.svelte'
  import type { Anchor, Position, RigidTransform } from './types'


  
  interface Props {
    glbUrl?: string | null;
    anchors?: Anchor[];
    selectedId?: string | null;
    pendingPosition?: Position | null;
    mappingAnchor?: Anchor | null;
    userPosition?: Position | null;
    // stitch mode
    stitchPhase?: 'idle' | 'pickSource' | 'pickTarget' | 'preview';
    stitchSourceGlbUrl?: string | null;
    mergedSpaces?: Array<{ url: string; transform: RigidTransform | null }>;
    stitchSourcePoints?: Position[];
    stitchTargetPoints?: Position[];
    stitchTransform?: RigidTransform | null;
    pointClouds?: Array<{ points: Position[]; color: number }>;
    mergedSpacesClickable?: boolean;
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
    stitchPhase = 'idle',
    stitchSourceGlbUrl = null,
    mergedSpaces = [],
    stitchSourcePoints = [],
    stitchTargetPoints = [],
    stitchTransform = null,
    pointClouds = [],
    mergedSpacesClickable = false,
    onplace,
    onselect
  }: Props = $props();
</script>

<div class="canvas-wrap">
  <Canvas>
    <SceneInner
      {glbUrl}
      {anchors}
      {selectedId}
      {pendingPosition}
      {mappingAnchor}
      {userPosition}
      {stitchPhase}
      {stitchSourceGlbUrl}
      {mergedSpaces}
      {stitchSourcePoints}
      {stitchTargetPoints}
      {stitchTransform}
      {pointClouds}
      {mergedSpacesClickable}
      {onplace}
      {onselect}
    />
  </Canvas>
</div>

<style>
  .canvas-wrap {
    flex: 1;
    height: 100vh;
    overflow: hidden;
  }
</style>
