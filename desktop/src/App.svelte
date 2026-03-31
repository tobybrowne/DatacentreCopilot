<script lang="ts">
  import { onMount } from 'svelte'
  import HomeView from './lib/HomeView.svelte'
  import AnchorView from './lib/AnchorView.svelte'
  import BuildingView from './lib/BuildingView.svelte'

  type Route = 'home' | 'anchors' | 'buildings'

  function hashToRoute(hash: string): Route {
    if (hash === '#/anchors') return 'anchors'
    if (hash === '#/buildings') return 'buildings'
    return 'home'
  }

  let route: Route = hashToRoute(window.location.hash)

  function navigate(to: Route) {
    window.location.hash = to === 'home' ? '/' : `/${to}`
  }

  onMount(() => {
    const onHashChange = () => { route = hashToRoute(window.location.hash) }
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  })
</script>

{#if route === 'home'}
  <HomeView on:navigate={(e) => navigate(e.detail)} />
{:else if route === 'anchors'}
  <AnchorView on:back={() => navigate('home')} />
{:else if route === 'buildings'}
  <BuildingView on:back={() => navigate('home')} />
{/if}
