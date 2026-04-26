import os
from contextlib import asynccontextmanager

from dotenv import load_dotenv
load_dotenv()

from fastapi import FastAPI

from nav.router import router as nav_router
from room_inference.router import router as room_inference_router
from room_inference import infer
from video.router import router as video_router
from copilot.router import router as realtime_router


@asynccontextmanager
async def lifespan(app: FastAPI):
    # load the inference model into memory on startup
    output_dir = os.environ.get('OUTPUT_DIR')
    if output_dir:
        infer.load(output_dir, os.environ.get('METHOD', 'kmeans'))
    yield


app = FastAPI(title='Mono Service', lifespan=lifespan)
app.include_router(nav_router)
app.include_router(video_router)
app.include_router(realtime_router)
# app.include_router(room_inference_router)


@app.get('/health')
def health():
    return {'status': 'ok'}
