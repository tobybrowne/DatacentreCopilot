<script lang="ts">
  import { goto } from '$app/navigation'
  import NavigateView from '$lib/NavigateView.svelte'
  import type { PageData } from './$types'

  export let data: PageData
</script>

<NavigateView
  buildingId={data.buildingId}
  buildingName={data.buildingName}
  spaces={data.spaces}
  existingNavMesh={data.existingNavMesh}
  on:back={() => goto('/navigate')}
/>
