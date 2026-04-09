from io import BytesIO

import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.collections import PolyCollection


def render_path_image(pos_a: dict, pos_b: dict, navmesh_data: dict) -> bytes:
    """Render the navmesh and path as a PNG, returned as bytes."""
    fig, ax = plt.subplots(figsize=(10, 10), facecolor='#1a1a2e')
    ax.set_facecolor('#1a1a2e')
    ax.set_aspect('equal')
    ax.axis('off')

    if navmesh_data['verts'] and navmesh_data['faces']:
        verts = np.array(navmesh_data['verts'])
        faces = np.array(navmesh_data['faces'])
        tris = verts[faces][:, :, [0, 2]]
        tris[:, :, 1] *= -1
        poly = PolyCollection(tris, facecolor='#00d4ff18', edgecolor='#00d4ff55', linewidth=0.4)
        ax.add_collection(poly)

    ax.scatter([pos_a['x']], [-pos_a['z']], color='#00ff88', s=80, marker='x', linewidths=2, zorder=5)
    ax.scatter([pos_b['x']], [-pos_b['z']], color='#ff4444', s=80, marker='x', linewidths=2, zorder=5)

    waypoints = navmesh_data.get('path', [])
    if waypoints:
        snap_s = navmesh_data.get('snapStart')
        snap_e = navmesh_data.get('snapEnd')
        xs = [p['x'] for p in waypoints]
        zs = [-p['z'] for p in waypoints]
        ax.plot(xs, zs, color='#ffffff', linewidth=2, zorder=3)
        if snap_s:
            ax.scatter([snap_s['x']], [-snap_s['z']], color='#00ff88', s=120, zorder=4)
        if snap_e:
            ax.scatter([snap_e['x']], [-snap_e['z']], color='#ff4444', s=120, zorder=4)

    ax.autoscale()
    ax.margins(0.05)

    buf = BytesIO()
    fig.savefig(buf, format='png', bbox_inches='tight', pad_inches=0.2,
                dpi=150, facecolor=fig.get_facecolor())
    plt.close(fig)
    buf.seek(0)
    return buf.read()
