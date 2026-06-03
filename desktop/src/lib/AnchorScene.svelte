<script lang="ts">
  import SceneCanvas from './SceneCanvas.svelte'
  import AnchorSceneInner from './AnchorSceneInner.svelte'
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
    // stitch mode
    stitchPhase?: 'idle' | 'pickSource' | 'pickTarget' | 'preview';
    stitchSourceGlbUrl?: string | null;
    mergedSpaces?: Array<{ url: string; transform: RigidTransform | null }>;
    stitchSourcePoints?: Position[];
    stitchTargetPoints?: Position[];
    stitchTransform?: RigidTransform | null;
    pointClouds?: Array<{ points: Position[]; color: number }>;
    mergedSpacesClickable?: boolean;
    showDensity?: boolean;
    draggableAnchorId?: string | null;
    canExport?: boolean;
    exportName?: string;
    onplace?: (detail: { position: Position; spaceIndex: number | null }) => void;
    onselect?: (id: string) => void;
    ondraganchor?: (id: string, pos: Position) => void;
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
    draggableAnchorId = null,
    canExport = false,
    exportName = 'space',
    onplace,
    onselect,
    ondraganchor
  }: Props = $props();
</script>

<SceneCanvas {canExport} {exportName}>
  {#snippet children({ whiteBackground, exportTrigger, onexportblob })}
    <AnchorSceneInner
      {glbUrl}
      {anchors}
      {selectedId}
      {pendingPosition}
      {mappingAnchor}
      {userPosition}
      {boundingBox}
      {showBoundingBoxes}
      {stitchPhase}
      {stitchSourceGlbUrl}
      {mergedSpaces}
      {stitchSourcePoints}
      {stitchTargetPoints}
      {stitchTransform}
      {pointClouds}
      {mergedSpacesClickable}
      {showDensity}
      {whiteBackground}
      {draggableAnchorId}
      {exportTrigger}
      exportScale={2}
      {onplace}
      {onselect}
      {ondraganchor}
      {onexportblob}
    />
  {/snippet}
</SceneCanvas>
