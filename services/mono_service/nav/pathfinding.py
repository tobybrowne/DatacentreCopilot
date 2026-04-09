import json
import subprocess
from pathlib import Path


def apply_transform(glb_pos: dict, transform: dict | None) -> dict:
    """Rotate and translate a local-space position into building world space."""
    x, y, z = glb_pos['x'], glb_pos['y'], glb_pos['z']
    if not transform:
        return {'x': x, 'y': y, 'z': z}
    p = transform['position']
    q = transform['quaternion']
    qx, qy, qz, qw = q['x'], q['y'], q['z'], q['w']
    rx = (1 - 2*(qy*qy + qz*qz))*x + 2*(qx*qy - qz*qw)*y + 2*(qx*qz + qy*qw)*z
    ry = 2*(qx*qy + qz*qw)*x + (1 - 2*(qx*qx + qz*qz))*y + 2*(qy*qz - qx*qw)*z
    rz = 2*(qx*qz - qy*qw)*x + 2*(qy*qz + qx*qw)*y + (1 - 2*(qx*qx + qy*qy))*z
    return {'x': rx + p['x'], 'y': ry + p['y'], 'z': rz + p['z']}


def query_navmesh(navmesh_data: bytes, pos_a: dict, pos_b: dict) -> dict:
    """Run the Recast navmesh pathfinding via the Node.js subprocess."""
    proc = subprocess.run(
        [
            'node', 'navmesh_query.mjs',
            str(pos_a['x']), str(pos_a['y']), str(pos_a['z']),
            str(pos_b['x']), str(pos_b['y']), str(pos_b['z']),
        ],
        input=navmesh_data,
        capture_output=True,
        cwd=Path(__file__).parent / 'detour_js',
    )
    if proc.returncode != 0:
        raise RuntimeError(proc.stderr.decode().strip())
    return json.loads(proc.stdout)
