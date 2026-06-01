import asyncio
import os
import subprocess
import time
import urllib.request as _urllib
from contextlib import asynccontextmanager
from pathlib import Path

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from starlette.middleware.base import BaseHTTPMiddleware

from nav.router import router as nav_router
from room_inference import infer
from spaces.router import router as spaces_router
from stitch.router import router as stitch_router
from video.router import router as video_router
from copilot.router import router as realtime_router
from navmesh_rooms.router import router as navmesh_rooms_router
import live_asset_data

_DETOUR_PORT = int(os.environ.get('DETOUR_PORT', '7654'))
_DETOUR_JS_DIR = Path(__file__).parent / 'nav' / 'detour_js'


def _start_detour_server() -> subprocess.Popen:
    proc = subprocess.Popen(
        ['node', 'navmesh_server.mjs'],
        cwd=_DETOUR_JS_DIR,
        env={**os.environ, 'DETOUR_PORT': str(_DETOUR_PORT)},
    )
    health = f'http://127.0.0.1:{_DETOUR_PORT}/health'
    for _ in range(100):
        try:
            _urllib.urlopen(health, timeout=0.5)
            print(f'[detour] server ready on port {_DETOUR_PORT}')
            return proc
        except Exception:
            time.sleep(0.1)
    raise RuntimeError('Detour server did not start in time')


@asynccontextmanager
async def lifespan(app: FastAPI):
    detour_proc = await asyncio.to_thread(_start_detour_server)

    task = asyncio.create_task(live_asset_data.run())
    yield

    task.cancel()
    detour_proc.terminate()
    detour_proc.wait()


app = FastAPI(title='Mono Service', lifespan=lifespan)
app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_methods=['*'],
    allow_headers=['*'],
)

class PrivateNetworkMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        response = await call_next(request)
        if request.headers.get('access-control-request-private-network'):
            response.headers['access-control-allow-private-network'] = 'true'
        return response

app.add_middleware(PrivateNetworkMiddleware)
app.include_router(nav_router)
app.include_router(spaces_router)
app.include_router(stitch_router)
app.include_router(video_router)
app.include_router(realtime_router)
app.include_router(navmesh_rooms_router)


@app.get('/health')
def health():
    return {'status': 'ok'}
