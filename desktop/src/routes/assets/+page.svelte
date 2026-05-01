<script lang="ts">
  import { goto } from '$app/navigation'
  import AssetView from '$lib/AssetView.svelte'
</script>

<AssetView onback={() => goto('/')} />
