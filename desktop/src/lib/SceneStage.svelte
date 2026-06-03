<script lang="ts">
  // Shared scene boilerplate: white-background toggle, lights, and the default
  // perspective camera + orbit controls. Drop inside any Threlte <Canvas>.
  import { T } from '@threlte/core'
  import { OrbitControls } from '@threlte/extras'

  interface Props {
    cameraPosition?: [number, number, number];
    fov?: number;
    orbitEnabled?: boolean;
    whiteBackground?: boolean;
  }

  let {
    cameraPosition = [0, 2, 5],
    fov = 60,
    orbitEnabled = true,
    whiteBackground = false,
  }: Props = $props()
</script>

{#if whiteBackground}
  <T.Color attach="background" args={[0xffffff]} />
{/if}

<T.AmbientLight intensity={0.6} />
<T.DirectionalLight position={[5, 10, 5]} intensity={1} castShadow />

<T.PerspectiveCamera makeDefault position={cameraPosition} {fov}>
  <OrbitControls enabled={orbitEnabled} zoomToCursor={true} screenSpacePanning={true} />
</T.PerspectiveCamera>
