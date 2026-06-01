# mono_service

The backend for [entangl-copilot](../../README.md). A single **FastAPI** service that
handles the compute the headset app and web companion can't do on their own: route
planning, ICP scan stitching, navmesh room segmentation, video transcoding, and a
proxy for the in-headset voice copilot. State lives in Supabase; this service is
mostly stateless request handling plus a couple of background tasks.

## Architecture

- **FastAPI + Uvicorn** ASGI app (`app.py`), title *Mono Service*.
- On startup (lifespan) it:
  - spawns a **Node.js recast-navigation sidecar** (`nav/detour_js/navmesh_server.mjs`)
    on `DETOUR_PORT` and waits for its `/health` to come up — this does the actual
    navmesh pathfinding;
  - launches a background task (`live_asset_data`) that publishes simulated
    power/cooling telemetry to Supabase on an interval.
- **CORS** is fully open, plus a small middleware that answers Chrome's
  Private Network Access preflight (so a browser on the LAN can reach a local instance).
- Auth is **per-endpoint**, not global (see [Auth](#auth)).

## Setup

Requires **Python 3.12+**, [`uv`](../../docs/UV.md), and **Node.js** (for the navmesh sidecar).

```bash
cd services/mono_service
cp .env.example .env      # then fill in the values
uv sync                   # install Python deps
```

## Running

```bash
./start.sh
```

`start.sh` installs the sidecar's npm deps (`npm install --prefix nav/detour_js`),
runs `uv sync`, and starts Uvicorn with `--reload`:

```bash
uv run python -m uvicorn app:app --host "$HOST" --port "$PORT" --reload
```

| Variable | Default | Purpose |
|----------|---------|---------|
| `HOST` | `0.0.0.0` | Uvicorn bind address |
| `PORT` | `8000` | Uvicorn bind port |
| `DETOUR_PORT` | `7654` | Port for the Node navmesh sidecar |

Health check: `curl http://localhost:8000/health` → `{"status": "ok"}`.

## Environment

Set in `.env` (see `.env.example`):

| Variable | Used for |
|----------|----------|
| `SUPABASE_URL` | Supabase project URL |
| `SUPABASE_KEY` | Supabase service key (DB, auth verification, storage) |
| `WEBHOOK_SECRET` | Shared secret authenticating webhook-style endpoints |
| `OPENAI_KEY` | OpenAI key for the copilot Realtime proxy (falls back to `OPENAI_API_KEY`) |
| `FFMPEG_PATH` | Path to the `ffmpeg` binary for video conversion |
| `DETOUR_PORT` | Navmesh sidecar port (also read by `app.py`) |

## API

All routers are mounted under their own prefix. Endpoints marked **auth** require a
Supabase user token (`Authorization: Bearer <token>`); **webhook** endpoints require
`Authorization: Bearer <WEBHOOK_SECRET>`.

### `/nav` — pathfinding
| Method · Path | Auth | Description |
|---|---|---|
| `POST /nav/path` | auth | Find a route between two anchors; returns a list of `{x,y,z}` waypoints. |
| `POST /nav/path-image` | auth | Same route, rendered to a debug PNG (`image/png`). |

### `/spaces` — space geometry
| Method · Path | Auth | Description |
|---|---|---|
| `POST /spaces/compute-bbox` | webhook | Compute and store the footprint (concave n-gon prism) for a space's GLB. Runs in the background. |

### `/stitch` — scan alignment
| Method · Path | Auth | Description |
|---|---|---|
| `POST /stitch/refine` | auth | Coarse-to-fine **ICP** (open3d) alignment between two spaces; returns the refined transform, fitness and inlier RMSE. |

### `/navmesh-rooms` — room segmentation
| Method · Path | Auth | Description |
|---|---|---|
| `POST /navmesh-rooms/segment` | auth | Segment a navmesh into rooms via Louvain community detection (networkx); stores per-room 2D polygons (+ `y_min`/`y_max`) on the navmesh. |

### `/video` — media
| Method · Path | Auth | Description |
|---|---|---|
| `POST /video/convert` | webhook | Transcode an uploaded MP4 to 360p OGV (Theora/Vorbis) via FFmpeg. Runs in the background. |

### `/copilot` — voice assistant
| Method · Path | Auth | Description |
|---|---|---|
| `WS /copilot/ws` | token | Bidirectional proxy to the OpenAI Realtime API (audio, transcripts, tool calls). Token via `Authorization` header or `?token=`. |

### Built-in
| Method · Path | Description |
|---|---|
| `GET /health` | Liveness check. |

## Layout

```
services/mono_service/
├── app.py                # FastAPI app, lifespan, router mounting
├── common.py             # get_supabase(), require_auth(), require_webhook_auth()
├── start.sh              # install deps + run uvicorn
├── nav/
│   ├── router.py         # /nav endpoints
│   ├── pathfinding.py    # talks to the recast sidecar
│   └── detour_js/        # Node recast-navigation navmesh server (sidecar)
├── spaces/router.py      # /spaces endpoints
├── stitch/router.py      # /stitch endpoints (ICP)
├── navmesh_rooms/router.py
├── video/router.py
├── copilot/              # router + OpenAI Realtime proxy
└── live_asset_data/      # background telemetry publisher
```

> The ICP/stitch evaluation and navmesh benchmark scripts that used to live here
> have been moved out to the repo's `testing/` directory.

## Auth (`common.py`)

- `get_supabase()` — Supabase client from `SUPABASE_URL` / `SUPABASE_KEY`.
- `require_auth` — FastAPI dependency; validates a Bearer user token via Supabase.
- `require_webhook_auth` — FastAPI dependency; checks a Bearer token against `WEBHOOK_SECRET`.

## Key dependencies

`fastapi` / `uvicorn` (server) · `supabase` (DB/auth/storage) · `open3d` (ICP) ·
`trimesh` + `numpy` + `scipy` (mesh/geometry) · `shapely` + `alphashape` (footprints) ·
`networkx` (room segmentation) · `matplotlib` (debug renders) · `websockets` (copilot
proxy) · Node `recast-navigation` (navmesh sidecar) · FFmpeg (video).
