import json
import os
import urllib.error
import urllib.request

DETOUR_PORT = int(os.environ.get('DETOUR_PORT', '7654'))
_BASE = f'http://127.0.0.1:{DETOUR_PORT}'


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
    """Query the persistent Detour HTTP server for a path between two points."""
    url = (
        f'{_BASE}/query'
        f'?x1={pos_a["x"]}&y1={pos_a["y"]}&z1={pos_a["z"]}'
        f'&x2={pos_b["x"]}&y2={pos_b["y"]}&z2={pos_b["z"]}'
    )
    req = urllib.request.Request(
        url,
        data=navmesh_data,
        method='POST',
        headers={'Content-Type': 'application/octet-stream'},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            result = json.loads(resp.read())
    except urllib.error.HTTPError as e:
        body = json.loads(e.read())
        raise RuntimeError(body.get('error', str(e)))
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result
