<script lang="ts">
  import { goto } from '$app/navigation'
  import AnchorView from '$lib/AnchorView.svelte'
</script>

<AnchorView on:back={() => goto('/')} />
