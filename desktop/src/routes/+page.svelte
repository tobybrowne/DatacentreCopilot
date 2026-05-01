<script lang="ts">
  import { goto } from '$app/navigation'
  import HomeView from '$lib/HomeView.svelte'
</script>

<HomeView onnavigate={(dest) => goto(`/${dest}`)} />
