<script lang="ts">
  import { goto } from '$app/navigation'
  import LiveView from '$lib/LiveView.svelte'
</script>

<LiveView onback={() => goto('/')} />
