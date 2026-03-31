<script lang="ts">
  import HomeView from './lib/HomeView.svelte'
  import AnchorView from './lib/AnchorView.svelte'
  import BuildingView from './lib/BuildingView.svelte'

  type Route = 'home' | 'anchors' | 'buildings'
  let route: Route = 'home'
</script>

{#if route === 'home'}
  <HomeView on:navigate={(e) => route = e.detail} />
{:else if route === 'anchors'}
  <AnchorView on:back={() => route = 'home'} />
{:else if route === 'buildings'}
  <BuildingView on:back={() => route = 'home'} />
{/if}
