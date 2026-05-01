<script lang="ts">
  import { signIn } from './auth'

  let email = $state('')
  let password = $state('')
  let error: string | null = $state(null)
  let loading = $state(false)

  async function handleSubmit() {
    error = null
    loading = true
    error = await signIn(email, password)
    loading = false
  }
</script>

<div class="wrap">
  <form class="card" onsubmit={(e) => { e.preventDefault(); handleSubmit() }}>
    <img src="/entangl-cyan.svg" alt="Entangl" class="logo" />

    <label>
      Email
      <input type="email" bind:value={email} autocomplete="email" required />
    </label>

    <label>
      Password
      <input type="password" bind:value={password} autocomplete="current-password" required />
    </label>

    {#if error}
      <p class="error">{error}</p>
    {/if}

    <button type="submit" class="primary" disabled={loading}>
      {loading ? 'Signing in…' : 'Sign in'}
    </button>
  </form>
</div>

<style>
  .wrap {
    width: 100vw;
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--bg);
  }

  .card {
    display: flex;
    flex-direction: column;
    gap: 14px;
    width: 320px;
    padding: 28px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 10px;
  }

  .logo {
    height: 48px;
    width: auto;
    margin-bottom: 4px;
  }

  label {
    display: flex;
    flex-direction: column;
    gap: 6px;
    font-size: 12px;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.05em;
  }

  input {
    padding: 6px 10px;
    border-radius: 6px;
    border: 1px solid var(--border);
    background: var(--bg);
    color: var(--text);
    font-size: 13px;
    outline: none;
    transition: border-color 0.15s;
    width: 100%;
  }

  input:focus {
    border-color: var(--accent);
  }

  .error {
    font-size: 12px;
    color: var(--danger);
  }
</style>
