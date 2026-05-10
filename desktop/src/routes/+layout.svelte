<script lang="ts">
  import '../app.css'
  import { session } from '$lib/auth'
  import Login from '$lib/Login.svelte'
  import Toast from '$lib/Toast.svelte'
  interface Props {
    children?: import('svelte').Snippet;
  }

  let { children }: Props = $props();
</script>

{#if $session}
  {@render children?.()}
{:else}
  <Login />
{/if}

<Toast />
