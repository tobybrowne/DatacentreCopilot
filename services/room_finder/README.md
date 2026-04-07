# room-finder-service

Processing service built on FastAPI. Accepts jobs over HTTP and processes them on a single background worker, keeping the model warm in memory.

## Setup

```bash
cd services/room_finder
uv sync
```

The service imports directly from `../../room_finder`, so no installation of that package is needed.

## Start

```bash
OUTPUT_DIR=../../room_finder/run uvicorn app:app --reload
```

| Variable | Default | Description |
|----------|---------|-------------|
| `OUTPUT_DIR` | required | Path to a `room_finder` training output directory |
| `METHOD` | `kmeans` | `kmeans` or `nn` |

## Endpoints

### `POST /jobs/room-inference`

Submit an image for room classification. Returns a job ID immediately.

```bash
curl -X POST http://localhost:8000/jobs/room-inference \
  -F "file=@photo.jpg"
```

```json
{"job_id": "abc-123", "status": "pending"}
```

### `GET /jobs/{job_id}`

Blocks until the job is complete, then returns the result.

```bash
curl http://localhost:8000/jobs/abc-123
```

```json
{
  "id": "abc-123",
  "type": "room_inference",
  "status": "done",
  "result": {
    "predicted_room": "kitchen",
    "confidence": 0.912,
    "method": "kmeans",
    "top5": {
      "kitchen": 0.912,
      "dining_room": 0.841,
      "living_room": 0.798,
      "corridor": 0.761,
      "bathroom": 0.743
    },
    "timing_ms": {
      "load": 1.2,
      "embed": 104.3,
      "search": 0.08,
      "total": 105.6
    }
  },
  "queued_at": "2026-04-05T14:00:00",
  "started_at": "2026-04-05T14:00:00",
  "finished_at": "2026-04-05T14:00:01"
}
```

### `GET /health`

```bash
curl http://localhost:8000/health
```

```json
{"status": "ok", "handlers": ["room_inference"]}
```

## Testing

Run the test script against a directory of images:

```bash
# single image
python tests/room_inference/run.py photo.jpg

# whole directory
python tests/room_inference/run.py ./test_images/

# multiple directories
python tests/room_inference/run.py ./kitchen/ ./bedroom/

# submit one at a time (shows per-image round-trip time)
python tests/room_inference/run.py ./test_images/ --sequential

# different host
python tests/room_inference/run.py ./test_images/ --url http://192.168.1.10:8000
```

## Adding a new job type

1. Create a handler class in `handlers/` with a `__call__(self, payload)` method
2. Register it in `_load_handlers()` in `app.py`
3. Add a `POST /jobs/<type>` endpoint that calls `jobs.submit()`
