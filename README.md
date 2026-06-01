# entangl-copilot

Spatial copilot for teams managing critical infrastructure. An augmented-reality
application for the **Magic Leap 2** guides engineers through procedures in the
physical space, with world-locked spatial anchors, occlusion against the real
environment, in-headset navigation, and a voice copilot. A **web companion** is
used to scan, stitch and calibrate buildings and to manage assets and logs, and a
**Python backend** handles the heavier geometry and AI work. **Supabase** is the
shared source of truth for all three.

---

## Components

| Path | What it is | Stack |
|------|------------|-------|
| [`app/`](app) | The Magic Leap 2 headset application | Godot 4.6 (mono), GDScript, OpenXR |
| [`desktop/`](desktop/README.md) | Web companion for scanning, stitching, calibration, navigation, asset & log management | SvelteKit 5, Threlte / three.js |
| [`services/mono_service/`](services/mono_service/README.md) | Backend API: pathfinding, ICP scan stitching, room segmentation, video conversion, copilot voice proxy | FastAPI (Python 3.12), open3d, trimesh, Node/recast sidecar |
| [`supabase/`](supabase) | Database schema, migrations, config and seed data | Supabase (Postgres) |

### Native Godot extensions (consumed by `app/`)

| Path | Purpose |
|------|---------|
| [`cv_camera_plugin/`](cv_camera_plugin/README.md) | Access the ML2's camera streams via the Android Camera2 API |
| [`ml2_voice_gdext/`](ml2_voice_gdext/README.md) | ML2 voice-intent system ("copilot" wake word) |
| `ml2_imu_gdext/` | ML2 IMU access |

> The headset app also depends on a **fork of `godot_openxr_vendors`** (built
> separately, not vendored in this repo) for ML2-specific OpenXR extensions such as
> spatial anchors, world-mesh detection and localization maps.

---

## How it fits together

- **`app/`** and **`desktop/`** both read/write Supabase directly (database, auth,
  storage buckets, realtime) and call **`mono_service`** over HTTP for compute that
  doesn't belong on-device: building/space bounding boxes, ICP scan stitching,
  navmesh room segmentation, and route-finding.
- **`mono_service`** spawns a Node.js **recast-navigation** sidecar for navmesh
  pathfinding and proxies the in-headset **voice copilot** to the OpenAI Realtime API.

---

## Getting started

Each component has its own setup instructions — start there:

- **Headset app:** build & deploy to a connected ML2 with `./launch.sh` (exports the
  Godot project to an APK via `adb`, launches it as an immersive HMD app, and streams
  `logcat`). See [`docs/ANDROID.md`](docs/ANDROID.md) and [`docs/DEPLOY.md`](docs/DEPLOY.md).
- **Backend:** [`services/mono_service/README.md`](services/mono_service/README.md)
- **Web companion:** [`desktop/README.md`](desktop/README.md)
- **Database:** the `supabase/` directory holds the schema and migrations; run a local
  stack with the Supabase CLI (`supabase start`) or point the apps at a hosted project.

All three apps share one Supabase project. For local development, run Supabase and
`mono_service` locally and set the matching URLs/keys in each app's environment.

---

## Repository layout

```
entangl-copilot/
├── app/                  # Magic Leap 2 Godot application
├── desktop/              # SvelteKit + Threlte web companion
├── services/
│   └── mono_service/     # FastAPI backend (+ Node recast navmesh sidecar)
├── supabase/             # schema, migrations, config, seed
├── cv_camera_plugin/     # ML2 Camera2 GDExtension
├── ml2_voice_gdext/      # ML2 voice-intent GDExtension
├── ml2_imu_gdext/        # ML2 IMU GDExtension
├── docs/                 # deeper docs + database ERD
├── testing/              # experiments & benchmarks (git-ignored)
└── launch.sh             # build & deploy the headset app to ML2
```

---

## Documentation

Deeper notes live in [`docs/`](docs):

| Doc | Topic |
|-----|-------|
| [`Anchors.md`](docs/Anchors.md) | Spatial anchor system and the coordinate-space rules for world-locked content |
| [`SCAN_STITCHING.md`](docs/SCAN_STITCHING.md) | How room scans are aligned and stitched into a building |
| [`LOCALISATION.md`](docs/LOCALISATION.md) | ML2 localization maps |
| [`ANDROID.md`](docs/ANDROID.md) · [`DEPLOY.md`](docs/DEPLOY.md) | Building and deploying the ML2 APK |
| [`GODOT-NOTES.md`](docs/GODOT-NOTES.md) | Godot / OpenXR gotchas |
| [`UV.md`](docs/UV.md) | Python tooling (`uv`) |
| `erd.*` | Generated database entity-relationship diagrams |
