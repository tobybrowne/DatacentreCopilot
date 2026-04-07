<script lang="ts">
  import { createEventDispatcher } from 'svelte'
  const dispatch = createEventDispatcher<{ navigate: 'anchors' | 'buildings' | 'navigate' }>()
</script>

<div class="home">
  <div class="center">
    <h1 class="logo">Entangl Desktop</h1>
    <p class="subtitle">What would you like to do?</p>
    <div class="cards">
      <button class="card" on:click={() => dispatch('navigate', 'anchors')}>
        <span class="card-icon">⬡</span>
        <span class="card-title">Anchor Placement</span>
        <span class="card-desc">View spaces and map reference anchors to your 3D scans</span>
      </button>
      <button class="card" on:click={() => dispatch('navigate', 'buildings')}>
        <span class="card-icon">⬢</span>
        <span class="card-title">Building Manager</span>
        <span class="card-desc">Stitch multiple room scans together into a single building</span>
      </button>
      <button class="card" on:click={() => dispatch('navigate', 'navigate')}>
        <span class="card-icon">⟐</span>
        <span class="card-title">Navigate</span>
        <span class="card-desc">Find routes between points in a stitched building</span>
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
  }

  .center {
    display: flex;
    flex-direction: column;
    align-items: center;
    gap: 32px;
  }

  .logo {
    font-size: 28px;
    font-weight: 700;
    color: var(--accent);
    letter-spacing: 0.02em;
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
