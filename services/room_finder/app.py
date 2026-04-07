"""
Processing service.

Start with:
    OUTPUT_DIR=./run METHOD=kmeans uvicorn app:app --reload

Environment variables:
    OUTPUT_DIR   path to a room_finder training output directory (required)
    METHOD       nn | kmeans (default: kmeans)
    HOST         bind host (default: 0.0.0.0)
    PORT         bind port (default: 8000)
"""

import asyncio
import io
import os
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image, ImageDraw, ImageFont

import jobs
from handlers.room_inference import InferencePayload, RoomInferenceHandler

FRAMES_DIR = Path("./frames")
MAX_FRAMES = 20


def _save_frame(image_bytes: bytes, mime_type: str, label: str, confidence: float):
    FRAMES_DIR.mkdir(exist_ok=True)

    img = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    w, h = img.size

    font_size = max(12, int(h * 0.06))
    try:
        font = ImageFont.load_default(size=font_size)
    except TypeError:
        font = ImageFont.load_default()

    text = f"{label}  {confidence:.0%}"
    draw = ImageDraw.Draw(img)

    bbox = draw.textbbox((0, 0), text, font=font)
    text_w = bbox[2] - bbox[0]
    text_h = bbox[3] - bbox[1]
    pad = max(4, int(font_size * 0.25))

    x, y = pad, pad
    draw.rectangle([x - pad, y - pad, x + text_w + pad, y + text_h + pad], fill=(0, 0, 0, 180))
    draw.text((x, y), text, font=font, fill=(255, 255, 255))

    ext = "jpg" if "jpeg" in mime_type else mime_type.split("/")[-1]
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%f")
    path = FRAMES_DIR / f"{timestamp}_{label}.{ext}"
    img.save(path)

    # Keep only the most recent MAX_FRAMES files
    files = sorted(FRAMES_DIR.glob("*"), key=lambda f: f.stat().st_mtime)
    for old in files[:-MAX_FRAMES]:
        old.unlink()


async def _save_frame_after_job(job: jobs.Job, image_bytes: bytes, mime_type: str):
    while job.status in (jobs.JobStatus.PENDING, jobs.JobStatus.RUNNING):
        await asyncio.sleep(0.1)

    if job.status == jobs.JobStatus.DONE and job.result:
        label = job.result.get("predicted_room", "unknown")
        confidence = job.result.get("confidence", 0.0)
        _save_frame(image_bytes, mime_type, label, confidence)


# ---------------------------------------------------------------------------
# Handler registry — add new job types here
# ---------------------------------------------------------------------------

_handlers: dict = {}


def _load_handlers():
    output_dir = os.environ.get("OUTPUT_DIR")
    if not output_dir:
        raise RuntimeError("OUTPUT_DIR environment variable is required")

    method = os.environ.get("METHOD", "kmeans")
    _handlers["room_inference"] = RoomInferenceHandler(output_dir, method=method)


# ---------------------------------------------------------------------------
# App lifecycle
# ---------------------------------------------------------------------------

@asynccontextmanager
async def lifespan(app: FastAPI):
    _load_handlers()
    worker = asyncio.create_task(jobs.worker_loop())

    yield
    worker.cancel()


app = FastAPI(title="Processing Service", lifespan=lifespan)


# ---------------------------------------------------------------------------
# Room inference
# ---------------------------------------------------------------------------

@app.post("/jobs/room-inference")
async def submit_room_inference(file: UploadFile = File(...)):
    image_bytes = await file.read()
    mime_type = file.content_type or "image/jpeg"
    payload = InferencePayload(image_bytes=image_bytes, mime_type=mime_type)
    job = jobs.submit("room_inference", _handlers["room_inference"], payload)
    asyncio.create_task(_save_frame_after_job(job, image_bytes, mime_type))

    while job.status in (jobs.JobStatus.PENDING, jobs.JobStatus.RUNNING):
        await asyncio.sleep(0.05)

    if job.status == jobs.JobStatus.FAILED:
        raise HTTPException(status_code=500, detail=job.error)

    return {"job_id": job.id, "status": job.status, "result": job.result}


# ---------------------------------------------------------------------------
# Shared job endpoints — wildcard must come after specific routes
# ---------------------------------------------------------------------------

@app.get("/jobs/{job_id}")
async def get_job(job_id: str):
    job = jobs.get_job(job_id)
    if job is None:
        raise HTTPException(status_code=404, detail="Job not found")

    while job.status in (jobs.JobStatus.PENDING, jobs.JobStatus.RUNNING):
        await asyncio.sleep(0.1)

    if job.status == jobs.JobStatus.FAILED:
        raise HTTPException(status_code=500, detail=job.error)

    return {
        "id":          job.id,
        "type":        job.type,
        "status":      job.status,
        "result":      job.result,
        "queued_at":   job.queued_at,
        "started_at":  job.started_at,
        "finished_at": job.finished_at,
    }


# ---------------------------------------------------------------------------
# Health
# ---------------------------------------------------------------------------

@app.get("/health")
def health():
    return {"status": "ok", "handlers": list(_handlers.keys())}
