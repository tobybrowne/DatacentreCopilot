from fastapi import APIRouter, WebSocket, WebSocketDisconnect

from .proxy import run_proxy

router = APIRouter(prefix="/copilot")


@router.websocket("/ws")
async def realtime_ws(websocket: WebSocket) -> None:
    await websocket.accept()
    try:
        await run_proxy(websocket)
    except WebSocketDisconnect:
        pass
