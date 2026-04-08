<script lang="ts">
  import { goto } from '$app/navigation'
  import NavigateView from '$lib/NavigateView.svelte'
  import type { PageData } from './$types'

  export let data: PageData
</script>

<NavigateView
  buildingName={data.buildingName}
  spaces={data.spaces}
  on:back={() => goto('/navigate')}
/>
