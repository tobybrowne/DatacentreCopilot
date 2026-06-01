<script lang="ts">
  import { goto } from '$app/navigation'
  import { Hand, Video } from 'lucide-svelte'
  import { formatDate, getStepText } from '$lib/logUtils'
  import Sidebar from '$lib/Sidebar.svelte'
  import { toast } from '$lib/toast'
  import type { LogWithContext, Procedure } from '$lib/types'
  import type { PageData } from './$types'

  interface Props { data: PageData }
  let { data }: Props = $props()

  const building = data.building
  const allLogs: LogWithContext[] = data.logs

  let filterDateFrom = $state('')
  let filterDateTo = $state('')
  let filterUserId = $state('')
  let filterProcedureId = $state('')
  let filterAssetId = $state('')

  let filteredLogs = $derived(
    allLogs.filter(log => {
      if (filterDateFrom && log.created_at.slice(0, 10) < filterDateFrom) return false
      if (filterDateTo   && log.created_at.slice(0, 10) > filterDateTo)   return false
      if (filterUserId   && log.user_id !== filterUserId) return false
      if (filterProcedureId && log.procedureRun?.procedure.id !== filterProcedureId) return false
      if (filterAssetId  && !log.assets.some(a => a.id === filterAssetId)) return false
      return true
    })
  )

  let uniqueUsers = $derived(
    [...new Map(allLogs.map(l => [l.user_id, { id: l.user_id, email: l.userEmail }])).values()]
  )

  let uniqueProcedures = $derived(
    [
      ...new Map(
        allLogs
          .filter(l => l.procedureRun?.procedure)
          .map(l => [l.procedureRun!.procedure.id, l.procedureRun!.procedure] as [string, Procedure])
      ).values()
    ]
  )

  let uniqueAssets = $derived(
    [...new Map(allLogs.flatMap(l => l.assets).map(a => [a.id, a])).values()]
  )


  function clearFilters(): void {
    filterDateFrom = ''
    filterDateTo = ''
    filterUserId = ''
    filterProcedureId = ''
    filterAssetId = ''
  }
</script>

<div class="log-browser">
  <Sidebar title={building.name ?? 'Log Viewer'} onback={() => goto('/log')}>

    <section class="filters">
      <label class="section-label">Filters</label>
      <div class="filter-row">
        <span class="filter-label">From</span>
        <input type="date" bind:value={filterDateFrom} />
      </div>
      <div class="filter-row">
        <span class="filter-label">To</span>
        <input type="date" bind:value={filterDateTo} />
      </div>
      <div class="filter-row">
        <span class="filter-label">User</span>
        <select bind:value={filterUserId}>
          <option value="">All</option>
          {#each uniqueUsers as u}
            <option value={u.id}>{u.email ?? u.id.slice(0, 8)}</option>
          {/each}
        </select>
      </div>
      <div class="filter-row">
        <span class="filter-label">Proc.</span>
        <select bind:value={filterProcedureId}>
          <option value="">All</option>
          {#each uniqueProcedures as proc}
            <option value={proc.id}>{proc.title}</option>
          {/each}
        </select>
      </div>
      {#if uniqueAssets.length > 0}
        <div class="filter-row">
          <span class="filter-label">Asset</span>
          <select bind:value={filterAssetId}>
            <option value="">All</option>
            {#each uniqueAssets as asset}
              <option value={asset.id}>{asset.name ?? asset.id.slice(0, 8)}</option>
            {/each}
          </select>
        </div>
      {/if}
      {#if filterDateFrom || filterDateTo || filterUserId || filterProcedureId || filterAssetId}
        <button class="clear-btn" onclick={clearFilters}>Clear filters</button>
      {/if}
    </section>

  </Sidebar>

  <div class="main">
    <div class="log-list">
      {#if filteredLogs.length === 0}
        <p class="empty-msg">
          {allLogs.length === 0
            ? 'No logs found for this building.'
            : 'No logs match the current filters.'}
        </p>
      {:else}
        {#each filteredLogs as log, i (log.id)}
          {@const hasGesture = !!log.geometry_recording_path}
          {@const hasVideo   = !!log.camera_recording_path}
          {@const clickable  = hasVideo}
          {@const day = log.created_at.slice(0, 10)}
          {@const prevDay = i > 0 ? filteredLogs[i - 1].created_at.slice(0, 10) : null}
          {#if day !== prevDay}
            <div class="day-divider">
              <span>{new Date(day + 'T12:00:00').toLocaleDateString(undefined, { weekday: 'long', month: 'long', day: 'numeric' })}</span>
            </div>
          {/if}
          <button
            class="log-card"
            onclick={() => goto(`/log/${building.id}/${log.id}`)}
            disabled={!clickable}
          >
            <div class="lc-header">
              <span class="lc-proc">{log.procedureRun?.procedure.title ?? 'Standalone'}</span>
              <span class="lc-time">{formatDate(log.created_at)}</span>
            </div>
            {#if getStepText(log)}
              <span class="lc-step">{getStepText(log)}</span>
            {/if}
            <div class="lc-footer">
              <span class="lc-user">{log.userEmail ?? log.user_id.slice(0, 8)}</span>
              <div class="lc-icons">
                {#if hasGesture}<span class="lc-icon gesture"><Hand size={14} /></span>{/if}
                {#if hasVideo}<span class="lc-icon video"><Video size={14} /></span>{/if}
              </div>
            </div>
          </button>
        {/each}
      {/if}
    </div>
  </div>
</div>

<style>
  .log-browser {
    display: flex;
    width: 100vw;
    height: 100vh;
    overflow: hidden;
  }

  .main {
    flex: 1;
    height: 100vh;
    overflow: hidden;
    display: flex;
    flex-direction: column;
    background: var(--bg);
  }

  .filters { gap: 7px !important; }
  .filter-row { display: flex; align-items: center; gap: 8px; }
  .filter-label { font-size: 11px; color: var(--text-muted); width: 40px; flex-shrink: 0; }
  .filter-row input[type="date"],
  .filter-row select {
    flex: 1;
    min-width: 0;
    background: var(--bg);
    border: 1px solid var(--border);
    color: var(--text);
    border-radius: 4px;
    padding: 4px 6px;
    font-size: 11px;
    outline: none;
    color-scheme: dark;
  }
  .filter-row input[type="date"]:focus,
  .filter-row select:focus { border-color: var(--accent); }
  .clear-btn {
    font-size: 11px;
    padding: 4px 8px;
    color: var(--text-muted);
    border-color: var(--border);
    background: transparent;
    width: 100%;
  }
  .clear-btn:hover { color: var(--danger); border-color: var(--danger); }

  .log-list {
    flex: 1;
    overflow-y: auto;
    padding: 20px;
    display: flex;
    flex-direction: column;
    gap: 10px;
  }

  .day-divider {
    display: flex;
    align-items: center;
    gap: 10px;
    margin-top: 6px;
  }
  .day-divider::before,
  .day-divider::after {
    content: '';
    flex: 1;
    height: 1px;
    background: var(--border);
  }
  .day-divider span {
    font-size: 11px;
    color: var(--text-muted);
    white-space: nowrap;
    letter-spacing: 0.04em;
  }

  .empty-msg {
    color: var(--text-muted);
    font-size: 13px;
    font-style: italic;
    text-align: center;
    margin-top: 40px;
  }

  .log-card {
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 8px;
    padding: 14px 16px;
    text-align: left;
    cursor: pointer;
    transition: border-color 0.15s, background 0.15s;
    display: flex;
    flex-direction: column;
    gap: 7px;
    width: 100%;
  }
  .log-card:hover:not(:disabled) { border-color: var(--accent); background: #1f1f1f; }
  .log-card:disabled { opacity: 0.5; cursor: default; }

  .lc-header { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .lc-proc { font-size: 13px; font-weight: 500; color: var(--text); }
  .lc-time { font-size: 11px; color: var(--text-muted); white-space: nowrap; flex-shrink: 0; }
  .lc-step { font-size: 12px; color: var(--text-muted); font-style: italic; }

  .lc-footer { display: flex; align-items: center; justify-content: space-between; gap: 8px; }
  .lc-user { font-size: 11px; color: var(--text-muted); font-family: monospace; }

  .lc-icons { display: flex; align-items: center; gap: 6px; }
  .lc-icon { display: flex; align-items: center; }
  .lc-icon.gesture { color: var(--accent); }
  .lc-icon.video { color: #ff8844; }
</style>
