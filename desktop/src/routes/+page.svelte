<script lang="ts">
  import { goto } from '$app/navigation'
  import HomeView from '$lib/HomeView.svelte'
</script>

<HomeView on:navigate={(e) => goto(`/${e.detail}`)} />
