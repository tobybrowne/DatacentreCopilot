import json

from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from common import verify_token
from .proxy import run_proxy

router = APIRouter(prefix="/copilot")


@router.websocket("/ws")
async def realtime_ws(websocket: WebSocket, token: str = "") -> None:
    await websocket.accept()

    # accept token from Authorization header or ?token= query param
    if not token:
        token = websocket.headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not await verify_token(token):
        print(f"[copilot] rejected - {'no token' if not token else 'invalid token'}")
        await websocket.send_text(json.dumps({"type": "error", "message": "Unauthorized"}))
        await websocket.close(code=4001)
        return
    
    try:
        await run_proxy(websocket)
    except WebSocketDisconnect:
        pass
