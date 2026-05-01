<script lang="ts">
  import { onMount } from 'svelte'
  import HomeView from './lib/HomeView.svelte'
  import AnchorView from './lib/AnchorView.svelte'
  import BuildingView from './lib/BuildingView.svelte'
  import LiveView from './lib/LiveView.svelte'

  type Route = 'home' | 'anchors' | 'buildings' | 'navigate' | 'assets' | 'live'

  function hashToRoute(hash: string): Route {
    if (hash === '#/anchors') return 'anchors'
    if (hash === '#/buildings') return 'buildings'
    if (hash === '#/live') return 'live'
    return 'home'
  }

  let route: Route = $state(hashToRoute(window.location.hash))

  function navigate(to: Route) {
    window.location.hash = to === 'home' ? '/' : `/${to}`
  }

  // TO-DO: is this the best way to handle routing?
  onMount(() => {
    const onHashChange = () => { route = hashToRoute(window.location.hash) }
    window.addEventListener('hashchange', onHashChange)
    return () => window.removeEventListener('hashchange', onHashChange)
  })
</script>

{#if route === 'home'}
  <HomeView onnavigate={(dest) => navigate(dest)} />
{:else if route === 'anchors'}
  <AnchorView onback={() => navigate('home')} />
{:else if route === 'buildings'}
  <BuildingView onback={() => navigate('home')} />
{:else if route === 'live'}
  <LiveView onback={() => navigate('home')} />
{/if}
