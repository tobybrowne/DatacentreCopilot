import asyncio
import os
from contextlib import asynccontextmanager

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


@asynccontextmanager
async def lifespan(app: FastAPI):
    # load the inference model into memory on startup
    output_dir = os.environ.get('OUTPUT_DIR')
    if output_dir:
        infer.load(output_dir, os.environ.get('METHOD', 'kmeans'))

    task = asyncio.create_task(live_asset_data.run())
    yield
    task.cancel()


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
# app.include_router(room_inference_router)


@app.get('/health')
def health():
    return {'status': 'ok'}
