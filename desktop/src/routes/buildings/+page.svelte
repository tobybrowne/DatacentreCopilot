<script lang="ts">
  import { goto } from '$app/navigation'
  import BuildingView from '$lib/BuildingView.svelte'
</script>

<BuildingView onback={() => goto('/')} />
