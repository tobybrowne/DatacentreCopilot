<script lang="ts">
  import '../app.css'
  import { session } from '$lib/auth'
  import Login from '$lib/Login.svelte'
</script>

{#if $session}
  <slot />
{:else}
  <Login />
{/if}
