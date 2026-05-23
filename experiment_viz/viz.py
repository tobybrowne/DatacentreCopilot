#!/usr/bin/env python3
"""
Visualize a location experiment log.

Usage:
    python viz.py <experiment-uuid>

Reads SUPABASE_URL and SUPABASE_KEY from .env (walks up from this file).
Outputs two SVGs into ./<uuid>/: timeseries.svg and floorplan.svg
"""

import sys
import os
from pathlib import Path

import numpy as np
import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.colors as mcolors
from matplotlib.collections import LineCollection
from scipy.spatial.transform import Rotation
from dotenv import load_dotenv, find_dotenv
from supabase import create_client

load_dotenv(find_dotenv())

# Must match DevConfig.LOCATION_EXPERIMENT_INTERVAL in the Godot app.
SAMPLE_INTERVAL = 0.5  # seconds

# ── Styling ───────────────────────────────────────────────────────────────────

BG       = '#1a1a2e'
PANEL_BG = '#16213e'
GRID     = '#2a2a4a'
TEXT     = '#e0e0e0'

CONF_COLORS = ['#e74c3c', '#f39c12', '#2ecc71', '#27ae60']  # POOR→EXCELLENT
CONF_LABELS = ['POOR', 'FAIR', 'GOOD', 'EXCELLENT']

SPACE_PALETTE  = ['#4a9eff', '#ff6b6b', '#ffd93d', '#6bcb77', '#c77dff', '#ff9f43']
ANCHOR_PALETTE = ['#ff6b6b', '#ffd93d', '#6bcb77', '#c77dff', '#ff9f43', '#00d4ff']

plt.rcParams.update({
    'text.color': TEXT,
    'axes.labelcolor': TEXT,
    'xtick.color': TEXT,
    'ytick.color': TEXT,
    'figure.facecolor': BG,
    'axes.facecolor': PANEL_BG,
    'axes.edgecolor': GRID,
    'grid.color': GRID,
    'legend.facecolor': BG,
    'legend.edgecolor': GRID,
    'legend.labelcolor': TEXT,
})


# ── Supabase ──────────────────────────────────────────────────────────────────

def get_supabase():
    url = os.environ.get('SUPABASE_URL')
    key = os.environ.get('SUPABASE_KEY')
    if not url or not key:
        sys.exit('SUPABASE_URL and SUPABASE_KEY must be set in .env')
    return create_client(url, key)


def fetch_samples(sb, log_id: str) -> list[dict]:
    row = sb.table('experiment_logs').select('data').eq('id', log_id).single().execute()
    return row.data['data']['samples']


def fetch_spaces(sb, space_ids: set[str]) -> dict[str, dict]:
    if not space_ids:
        return {}
    rows = sb.table('spaces').select('id, name, loc_bounding_box, offset_transformation') \
             .in_('id', list(space_ids)).execute()
    return {r['id']: r for r in rows.data}


# ── Transform helpers ─────────────────────────────────────────────────────────

def make_transform(t: dict) -> np.ndarray:
    """Convert {position:{x,y,z}, quaternion:{x,y,z,w}} → 4×4 matrix."""
    if not t:
        return np.eye(4)
    p = t.get('position', {})
    q = t.get('quaternion', {})
    M = np.eye(4)
    M[:3, :3] = Rotation.from_quat([q.get('x', 0), q.get('y', 0),
                                     q.get('z', 0), q.get('w', 1)]).as_matrix()
    M[:3,  3] = [p.get('x', 0), p.get('y', 0), p.get('z', 0)]
    return M


def apply(M: np.ndarray, xyz: dict) -> np.ndarray:
    p = np.array([xyz['x'], xyz['y'], xyz['z'], 1.0])
    return (M @ p)[:3]


# ── Derived data ──────────────────────────────────────────────────────────────

def anchor_building_positions(samples: list[dict], spaces: dict) -> dict[str, list[tuple]]:
    """
    Returns ml2_id → [(x, z), …] in building coordinates.
    Converts glb_pos using the localised space's offset_transformation.
    """
    result: dict[str, list] = {}
    transforms: dict[str, np.ndarray] = {
        sid: make_transform(s.get('offset_transformation') or {})
        for sid, s in spaces.items()
    }
    for sample in samples:
        sid = sample.get('localised_space_id', '')
        M = transforms.get(sid, np.eye(4))
        for pair in sample.get('anchor_pairs', []):
            mid = pair.get('ml2_id') or str(pair.get('index', '?'))
            glb = pair.get('glb_pos')
            if not glb:
                continue
            building = apply(M, glb)
            result.setdefault(mid, []).append((building[0], building[2]))
    return result


# ── Plots ─────────────────────────────────────────────────────────────────────

def _style_ax(ax):
    ax.grid(True, linewidth=0.5, alpha=0.6)
    for spine in ax.spines.values():
        spine.set_edgecolor(GRID)


def space_changes(samples: list[dict], field: str) -> list[tuple[int, str]]:
    """Returns [(sample_index, new_space_id), …] wherever the given field changes."""
    changes, prev = [], None
    for i, s in enumerate(samples):
        sid = s.get(field, '')
        if sid != prev:
            if prev is not None:
                changes.append((i, sid))
            prev = sid
    return changes


def _mark_changes(axes, changes: list[tuple[int, str]], spaces: dict,
                  color: str, label_y: float, linestyle: str = '--') -> None:
    for idx, sid in changes:
        name = spaces.get(sid, {}).get('name') or sid[:8]
        for ax in axes:
            ax.axvline(idx, color=color, lw=1.0, alpha=0.6, linestyle=linestyle, zorder=10)
        axes[0].text(idx + 0.3, label_y, name, color=color, fontsize=6,
                     rotation=90, va='top', alpha=0.9)


def plot_timeseries(samples: list[dict], spaces: dict, out: Path) -> None:
    n = len(samples)
    t = np.arange(n)

    confidence       = [s.get('loc_confidence', -1) for s in samples]
    kabsch_mm        = [s.get('kabsch_error_m', 0) * 1000 for s in samples]
    coarse_ch        = space_changes(samples, 'coarse_space_id')
    localised_ch     = space_changes(samples, 'localised_space_id')

    # Walking speed: distance between consecutive user positions / sample interval
    user_x = np.array([s['user_pos']['x'] for s in samples])
    user_z = np.array([s['user_pos']['z'] for s in samples])
    speed_ms = np.full(n, np.nan)
    for i in range(1, n):
        dx = user_x[i] - user_x[i - 1]
        dz = user_z[i] - user_z[i - 1]
        speed_ms[i] = np.sqrt(dx**2 + dz**2) / SAMPLE_INTERVAL

    # Calibration transform delta between consecutive samples
    # Drift from the start of each localised space segment (resets on relocalisation)
    calib_trans_drift = np.full(n, np.nan)  # mm from segment start
    calib_rot_drift   = np.full(n, np.nan)  # degrees from segment start
    seg_pos, seg_rot, prev_space = None, None, None
    for i, s in enumerate(samples):
        c = s.get('calibration')
        cur_space = s.get('localised_space_id', '')
        if not c:
            seg_pos, seg_rot, prev_space = None, None, cur_space
            continue
        p = c['position']
        q = c['quaternion']
        pos = np.array([p['x'], p['y'], p['z']])
        rot = Rotation.from_quat([q['x'], q['y'], q['z'], q['w']])
        if cur_space != prev_space or seg_pos is None:
            seg_pos, seg_rot = pos, rot
        calib_trans_drift[i] = np.linalg.norm(pos - seg_pos) * 1000
        rel_rot = rot * seg_rot.inv()
        calib_rot_drift[i] = np.degrees(rel_rot.magnitude())
        prev_space = cur_space

    # Per-anchor world positions indexed by sample (NaN where anchor not present)
    anchor_pos_by_sample: dict[str, np.ndarray] = {}
    for i, sample in enumerate(samples):
        for pair in sample.get('anchor_pairs', []):
            mid = pair.get('ml2_id') or str(pair.get('index', '?'))
            if mid not in anchor_pos_by_sample:
                anchor_pos_by_sample[mid] = np.full((n, 2), np.nan)
            wp = pair.get('world_pos', {})
            anchor_pos_by_sample[mid][i] = [wp.get('x', 0), wp.get('z', 0)]

    ROLLING_WIN = 10

    # Drift from each anchor's first known position (mm), NaN where untracked
    anchor_drift: dict[str, np.ndarray] = {}
    for mid, pos_arr in anchor_pos_by_sample.items():
        first_valid = pos_arr[~np.isnan(pos_arr[:, 0])][0] if not np.all(np.isnan(pos_arr[:, 0])) else np.zeros(2)
        drift = np.full(n, np.nan)
        for i in range(n):
            if not np.isnan(pos_arr[i, 0]):
                drift[i] = np.linalg.norm(pos_arr[i] - first_valid) * 1000
        anchor_drift[mid] = drift

    # Rolling stdev of anchor positions (mm) — one series per anchor
    anchor_rolling_std: dict[str, np.ndarray] = {}
    for mid, pos_arr in anchor_pos_by_sample.items():
        magnitudes = np.where(np.isnan(pos_arr[:, 0]), np.nan,
                              np.linalg.norm(pos_arr, axis=1) * 1000)
        stds = np.full(n, np.nan)
        for i in range(n):
            window = magnitudes[max(0, i - ROLLING_WIN):i + 1]
            valid = window[~np.isnan(window)]
            if len(valid) >= 2:
                stds[i] = valid.std()
        anchor_rolling_std[mid] = stds

    fig, axes = plt.subplots(7, 1, figsize=(13, 20), sharex=True)
    fig.suptitle('Location Experiment — Time Series', fontsize=13)

    # --- Confidence ---
    ax = axes[0]
    for i in range(n - 1):
        c = max(0, confidence[i])
        ax.axvspan(t[i], t[i + 1], color=CONF_COLORS[c], alpha=0.25)
    ax.step(t, [max(0, c) for c in confidence], where='post', color='white', lw=1.5)
    ax.set_yticks([0, 1, 2, 3])
    ax.set_yticklabels(CONF_LABELS, fontsize=8)
    ax.set_ylim(-0.3, 3.5)
    ax.set_ylabel('Loc Confidence')
    legend_patches = [plt.Rectangle((0, 0), 1, 1, fc=CONF_COLORS[i], alpha=0.6)
                      for i in range(4)]
    ax.legend(legend_patches, CONF_LABELS, fontsize=7, loc='lower right',
              ncol=4, framealpha=0.4)
    _style_ax(ax)

    # --- Kabsch error ---
    ax = axes[1]
    ax.plot(t, kabsch_mm, color='#00d4ff', lw=1.8)
    ax.fill_between(t, kabsch_mm, alpha=0.15, color='#00d4ff')
    ax.set_ylabel('Kabsch Error (mm)')
    _style_ax(ax)

    # --- Per-anchor drift ---
    ax = axes[2]
    for i, (mid, drift) in enumerate(anchor_drift.items()):
        color = ANCHOR_PALETTE[i % len(ANCHOR_PALETTE)]
        ax.plot(t, drift, color=color, lw=1.4, alpha=0.85, label=mid[:8])
    ax.set_ylabel('Anchor Drift (mm)')
    ax.legend(fontsize=7, loc='upper left', framealpha=0.4, ncol=2)
    _style_ax(ax)

    # --- Rolling stdev of anchor position ---
    ax = axes[3]
    for i, (mid, stds) in enumerate(anchor_rolling_std.items()):
        color = ANCHOR_PALETTE[i % len(ANCHOR_PALETTE)]
        ax.plot(t, stds, color=color, lw=1.4, alpha=0.85, label=mid[:8])
        ax.fill_between(t, np.where(np.isnan(stds), 0, stds), alpha=0.1, color=color)
    ax.set_ylabel(f'Anchor Pos StdDev\n(rolling {ROLLING_WIN}, mm)')
    ax.legend(fontsize=7, loc='upper left', framealpha=0.4, ncol=2)
    _style_ax(ax)

    # --- Walking speed ---
    ax = axes[4]
    # Smooth with a small rolling mean to reduce per-sample noise
    speed_smooth = np.convolve(np.nan_to_num(speed_ms), np.ones(5) / 5, mode='same')
    speed_smooth[:2] = np.nan
    ax.plot(t, speed_ms, color='#c77dff', lw=0.8, alpha=0.35)
    ax.plot(t, speed_smooth, color='#c77dff', lw=1.8, alpha=0.9, label='smoothed (5-sample)')
    ax.fill_between(t, np.nan_to_num(speed_ms), alpha=0.08, color='#c77dff')
    ax.set_ylabel('Walking Speed (m/s)')
    ax.set_xlabel('Sample index')
    ax.legend(fontsize=7, loc='upper right', framealpha=0.4)
    _style_ax(ax)

    # --- Calibration translation delta ---
    ax = axes[5]
    ax.plot(t, calib_trans_drift, color='#ff6b6b', lw=1.5, alpha=0.85)
    ax.fill_between(t, np.nan_to_num(calib_trans_drift), alpha=0.12, color='#ff6b6b')
    ax.set_ylabel('Calib Translation\nDrift (mm)')
    _style_ax(ax)

    # --- Calibration rotation drift ---
    ax = axes[6]
    ax.plot(t, calib_rot_drift, color='#ffd93d', lw=1.5, alpha=0.85)
    ax.fill_between(t, np.nan_to_num(calib_rot_drift), alpha=0.12, color='#ffd93d')
    ax.set_ylabel('Calib Rotation\nDrift (deg)')
    ax.set_xlabel('Sample index')
    _style_ax(ax)

    _mark_changes(axes, coarse_ch,    spaces, color='#ffffff', label_y=3.2, linestyle='--')
    _mark_changes(axes, localised_ch, spaces, color='#ffdd57', label_y=1.8, linestyle=':')

    plt.tight_layout()
    fig.savefig(out, format='svg', bbox_inches='tight')
    plt.close()
    print(f'  saved {out}')


def plot_floorplan(samples: list[dict], spaces: dict, anchor_bpos: dict[str, list],
                   out: Path) -> None:
    fig, ax = plt.subplots(figsize=(14, 14))
    ax.set_aspect('equal')
    ax.set_title('Location Experiment — Floor Plan', fontsize=13)
    _style_ax(ax)

    # Space outlines
    for i, (sid, space) in enumerate(spaces.items()):
        bbox = space.get('loc_bounding_box')
        if not bbox:
            continue
        verts = bbox['vertices_2d']
        xs = [v[0] for v in verts] + [verts[0][0]]
        zs = [v[1] for v in verts] + [verts[0][1]]
        color = SPACE_PALETTE[i % len(SPACE_PALETTE)]
        ax.fill(xs, zs, color=color, alpha=0.07)
        ax.plot(xs, zs, color=color, lw=1.8, alpha=0.75,
                label=space.get('name') or sid[:8])

    # User trajectory coloured by confidence
    xs = [s['user_pos']['x'] for s in samples]
    zs = [s['user_pos']['z'] for s in samples]
    conf_norm = [max(0, s.get('loc_confidence', 0)) / 3.0 for s in samples]
    conf_cmap = mcolors.LinearSegmentedColormap.from_list('conf', CONF_COLORS)

    if len(xs) > 1:
        pts  = np.array([xs, zs]).T.reshape(-1, 1, 2)
        segs = np.concatenate([pts[:-1], pts[1:]], axis=1)
        lc   = LineCollection(segs, cmap=conf_cmap, lw=2.5, zorder=5, alpha=0.9)
        lc.set_array(np.array(conf_norm[:-1]))
        ax.add_collection(lc)
        cbar = fig.colorbar(lc, ax=ax, pad=0.02, fraction=0.025,
                            ticks=[0, 1/3, 2/3, 1])
        cbar.ax.set_yticklabels(CONF_LABELS, color=TEXT, fontsize=8)
        cbar.set_label('Loc Confidence', color=TEXT)

    # Start / end
    if xs:
        ax.scatter(xs[0],  zs[0],  color='white',   s=80, zorder=10,
                   marker='o', label='Start')
        ax.scatter(xs[-1], zs[-1], color='#ffdd57',  s=80, zorder=10,
                   marker='X', label='End')

    # Coarse space transitions — white diamond
    for idx, sid in space_changes(samples, 'coarse_space_id'):
        if idx >= len(xs):
            continue
        label = spaces.get(sid, {}).get('name') or sid[:8]
        ax.scatter(xs[idx], zs[idx], color='white', s=90, zorder=11,
                   marker='D', edgecolors='#ffdd57', linewidths=1.2)
        ax.annotate(f'→ {label}', (xs[idx], zs[idx]), color='white',
                    fontsize=7, xytext=(6, 6), textcoords='offset points',
                    bbox=dict(boxstyle='round,pad=0.2', fc=BG, alpha=0.6, ec='none'))

    # Localised space transitions — yellow star
    for idx, sid in space_changes(samples, 'localised_space_id'):
        if idx >= len(xs):
            continue
        label = spaces.get(sid, {}).get('name') or sid[:8]
        ax.scatter(xs[idx], zs[idx], color='#ffdd57', s=120, zorder=12,
                   marker='*', edgecolors='white', linewidths=0.8)
        ax.annotate(f'⟳ {label}', (xs[idx], zs[idx]), color='#ffdd57',
                    fontsize=7, xytext=(6, -12), textcoords='offset points',
                    bbox=dict(boxstyle='round,pad=0.2', fc=BG, alpha=0.6, ec='none'))

    # Anchors: scatter all building-space positions, mark mean
    for i, (mid, positions) in enumerate(anchor_bpos.items()):
        axs_a = [p[0] for p in positions]
        azs_a = [p[1] for p in positions]
        color = ANCHOR_PALETTE[i % len(ANCHOR_PALETTE)]
        ax.scatter(axs_a, azs_a, color=color, s=14, alpha=0.3, zorder=6)
        mx, mz = np.mean(axs_a), np.mean(azs_a)
        ax.scatter(mx, mz, color=color, s=70, zorder=8,
                   marker='^', edgecolors='white', linewidths=0.6)
        ax.annotate(mid[:8] if mid != '?' else '?', (mx, mz),
                    color=color, fontsize=7,
                    xytext=(5, 5), textcoords='offset points')

    ax.set_xlabel('X (m)')
    ax.set_ylabel('Z (m)')
    ax.legend(fontsize=8, loc='upper right', framealpha=0.4)
    ax.autoscale()

    plt.tight_layout()
    fig.savefig(out, format='svg', bbox_inches='tight')
    plt.close()
    print(f'  saved {out}')


# ── Entry point ───────────────────────────────────────────────────────────────

def main() -> None:
    if len(sys.argv) != 2:
        sys.exit('Usage: python viz.py <experiment-uuid>')

    log_id = sys.argv[1]
    sb     = get_supabase()

    print(f'Fetching experiment {log_id}…')
    samples = fetch_samples(sb, log_id)
    print(f'  {len(samples)} samples')

    space_ids = {s.get('coarse_space_id') for s in samples} \
              | {s.get('localised_space_id') for s in samples}
    space_ids.discard(None)
    space_ids.discard('')

    print(f'Fetching {len(space_ids)} space(s)…')
    spaces = fetch_spaces(sb, space_ids)

    anchor_bpos = anchor_building_positions(samples, spaces)

    out_dir = Path(log_id[:8])
    out_dir.mkdir(exist_ok=True)

    print('Plotting…')
    plot_timeseries(samples, spaces, out_dir / 'timeseries.svg')
    plot_floorplan(samples, spaces, anchor_bpos, out_dir / 'floorplan.svg')
    print('Done.')


if __name__ == '__main__':
    main()
