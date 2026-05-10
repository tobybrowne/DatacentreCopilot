<script lang="ts">
  import { goto } from '$app/navigation'
  import NavigateView from '$lib/NavigateView.svelte'
  import type { PageData } from './$types'

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();
</script>

<NavigateView
  buildingId={data.buildingId}
  buildingName={data.buildingName}
  spaces={data.spaces}
  existingNavMesh={data.existingNavMesh}
  navmeshId={data.navmeshId}
  onback={() => goto('/navigate')}
/>
