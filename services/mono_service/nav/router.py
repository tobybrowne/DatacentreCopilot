from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import Response
from pydantic import BaseModel
from supabase import Client

from common import get_supabase, require_auth
from .pathfinding import apply_transform, query_navmesh
from .render import render_path_image

router = APIRouter(prefix='/nav')


class PathRequest(BaseModel):
    anchor_a_id: str
    anchor_b_id: str


def _resolve_path(sb: Client, req: PathRequest) -> tuple[dict, dict, list[dict]]:
    """Shared logic: fetch anchors, resolve navmesh, compute path.

    Returns (pos_a, pos_b, waypoints) where pos_a/pos_b are world-space dicts
    and waypoints is the list of {x,y,z} dicts from the pathfinder.
    Raises HTTPException on any failure.
    """
    anchors = (
        sb.table('anchors')
        .select('id,glb_position,space_id')
        .in_('id', [req.anchor_a_id, req.anchor_b_id])
        .execute()
        .data
    )
    by_id = {a['id']: a for a in anchors}
    anchor_a = by_id.get(req.anchor_a_id)
    anchor_b = by_id.get(req.anchor_b_id)
    if not anchor_a or not anchor_b:
        raise HTTPException(404, 'One or both anchors not found')
    if not anchor_a['glb_position'] or not anchor_b['glb_position']:
        raise HTTPException(400, 'One or both anchors have no position')

    space_ids = list({anchor_a['space_id'], anchor_b['space_id']})
    rows = (
        sb.table('spaces')
        .select('id,offset_transformation,buildings(navmeshes(navmesh_path))')
        .in_('id', space_ids)
        .execute()
        .data
    )
    if not rows:
        raise HTTPException(404, "No building found for this anchor's space")

    transform_by_space = {r['id']: r.get('offset_transformation') for r in rows}
    building = rows[0].get('buildings') or {}
    navmesh_rec = building.get('navmeshes')
    navmesh_path = navmesh_rec.get('navmesh_path') if navmesh_rec else None
    if not navmesh_path:
        raise HTTPException(404, 'No navmesh saved for this building yet')

    navmesh_data = sb.storage.from_('spaces_bucket').download(navmesh_path)

    pos_a = apply_transform(anchor_a['glb_position'], transform_by_space.get(anchor_a['space_id']))
    pos_b = apply_transform(anchor_b['glb_position'], transform_by_space.get(anchor_b['space_id']))
    print(f"[nav] {anchor_a['space_id']} → world {pos_a}")
    print(f"[nav] {anchor_b['space_id']} → world {pos_b}")

    try:
        result = query_navmesh(navmesh_data, pos_a, pos_b)
    except RuntimeError as e:
        raise HTTPException(500, f'Pathfinding failed: {e}')

    waypoints = result.get('path', [])

    if waypoints:
        sb.table('routes').insert({
            'start_anchor_id': req.anchor_a_id,
            'end_anchor_id': req.anchor_b_id,
            'waypoints': waypoints,
        }).execute()

    return pos_a, pos_b, waypoints, result


@router.post('/path')
async def path(req: PathRequest, _: None = Depends(require_auth)) -> dict:
    """Return computed waypoints as JSON for in-headset route display."""
    sb = get_supabase()
    _pos_a, _pos_b, waypoints, _result = _resolve_path(sb, req)
    return {'waypoints': waypoints}


@router.post('/path-image')
async def path_image(req: PathRequest, _: None = Depends(require_auth)) -> Response:
    """Return a PNG visualisation of the computed path (debug/desktop tool)."""
    sb = get_supabase()
    pos_a, pos_b, _waypoints, result = _resolve_path(sb, req)
    return Response(content=render_path_image(pos_a, pos_b, result), media_type='image/png')
