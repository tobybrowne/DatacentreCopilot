<script lang="ts">
  import { goto } from '$app/navigation'
  import { signOut } from '$lib/auth'
</script>

<div class="home">
  <button class="sign-out" onclick={signOut}>Sign out</button>
  <div class="center">
    <img src="/entangl-cyan.svg" alt="Entangl" class="logo" />
    <p class="subtitle">What would you like to do?</p>
    <div class="cards">
      <button class="card" onclick={() => goto('/calibration')}>
        <span class="card-icon">⬡</span>
        <span class="card-title">Space Calibration</span>
        <span class="card-desc">View spaces and map reference anchors to your 3D scans</span>
      </button>
      <button class="card" onclick={() => goto('/buildings')}>
        <span class="card-icon">⬢</span>
        <span class="card-title">Building Manager</span>
        <span class="card-desc">Stitch multiple room scans together into a single building</span>
      </button>
      <button class="card" onclick={() => goto('/navigate')}>
        <span class="card-icon">⟐</span>
        <span class="card-title">Navigate</span>
        <span class="card-desc">Find routes between points in a stitched building</span>
      </button>
      <button class="card" onclick={() => goto('/assets')}>
        <span class="card-icon">◈</span>
        <span class="card-title">Asset Manager</span>
        <span class="card-desc">Manage assets and map them to locations in your buildings</span>
      </button>
      <button class="card" onclick={() => goto('/live')}>
        <span class="card-icon">◎</span>
        <span class="card-title">Live View</span>
        <span class="card-desc">Monitor real-time user position within a space</span>
      </button>
    </div>
  </div>
</div>

<style>
  .home {
    width: 100vw;
    height: 100vh;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--bg);
    position: relative;
  }

  .sign-out {
    position: absolute;
    top: 16px;
    right: 16px;
    padding: 6px 14px;
    font-size: 12px;
    border-radius: 6px;
    border: 1px solid var(--border);
    color: var(--text-muted);
    background: transparent;
    cursor: pointer;
    transition: color 0.15s, border-color 0.15s;
  }
  .sign-out:hover {
    color: var(--text);
    border-color: var(--text-muted);
  }

  .center {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 32px;
  }

  .logo {
    height: 64px;
    width: auto;
  }

  .subtitle {
    color: var(--text-muted);
    font-size: 14px;
    margin-top: -20px;
  }

  .cards {
    display: flex;
    gap: 20px;
  }

  .card {
    width: 220px;
    display: flex;
    flex-direction: column;
    align-items: flex-start;
    gap: 10px;
    padding: 24px 20px;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    cursor: pointer;
    text-align: left;
    transition: border-color 0.15s, background 0.15s;
  }
  .card:hover {
    border-color: var(--accent);
    background: #1f1f1f;
  }

  .card-icon {
    font-size: 24px;
    color: var(--accent);
    line-height: 1;
  }

  .card-title {
    font-size: 15px;
    font-weight: 600;
    color: var(--text);
  }

  .card-desc {
    font-size: 12px;
    color: var(--text-muted);
    line-height: 1.5;
  }
</style>
