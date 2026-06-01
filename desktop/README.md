# desktop

The web companion for [entangl-copilot](../README.md). Where the headset app
*consumes* spatial data in the field, this app is where that data is *authored and
managed*: scanning is calibrated, room scans are stitched into buildings, routes are
checked, and assets, procedures and run logs are administered. It renders interactive
3D scenes of the scanned environment in the browser.

Built with **SvelteKit 5 + Threlte (three.js)**. It talks to **Supabase** directly
(database, auth, storage, realtime) and calls the **`mono_service`** backend for
heavier compute.

## Setup

Requires **Node.js**. From this directory:

```bash
npm install
cp .env.example .env   # if present; otherwise create .env (see Environment)
npm run dev            # Vite dev server, http://localhost:5173
```

| Script | Description |
|--------|-------------|
| `npm run dev` | Start the Vite dev server |
| `npm run build` | Build a static site (`adapter-static`) |
| `npm run preview` | Serve the production build locally |
| `npm run check` | Type-check with `svelte-check` |

The build output is a fully static site (SvelteKit `adapter-static`), so it can be
hosted from any static host.

## Environment

All variables are `VITE_`-prefixed and read via `import.meta.env`:

| Variable | Purpose |
|----------|---------|
| `VITE_SUPABASE_URL` | Supabase project URL (local default `http://127.0.0.1:64321`) |
| `VITE_SUPABASE_KEY` | Supabase anon key |
| `VITE_MONO_URL` | `mono_service` base URL (local default `http://127.0.0.1:8000`) |

For local development, run the Supabase stack and `mono_service` locally and point
these at them.

## Pages (`src/routes`)

| Route | Purpose |
|-------|---------|
| `/` | Dashboard / entry point |
| `/calibration`, `/calibration/[space_id]` | Map reference anchors onto a 3D scan to calibrate a space |
| `/buildings`, `/buildings/[id]`, `/buildings/create` | Browse buildings; stitch multiple spaces into one building |
| `/navigate`, `/navigate/[id]`, `/navigate/space/[id]` | Route-find within a building or a single space |
| `/assets` | Manage assets and bind them to anchor locations |
| `/log`, `/log/[building_id]`, `/log/[building_id]/[log_id]` | Browse procedure run logs |

## Key modules (`src/lib`)

**Data & auth**
- `supabase.ts` — Supabase client wrapper: fetches buildings/spaces/anchors/assets/
  procedures/logs, uploads navmesh binaries and GLBs to storage, calls the
  `mono_service` API (e.g. compute-bbox), and subscribes to realtime user-position updates.
- `auth.ts` — email/password auth store and session reactivity.
- `types.ts` — shared TypeScript types (`Building`, `Space`, `Anchor`, `Asset`, `RigidTransform`, `RoomSegment`, …).
- `toast.ts` — toast notifications.

**Geometry & navigation**
- `navmesh.ts` — build a navmesh from GLB meshes (recast-navigation) and run pathfinding.
- `stitching.ts` — rigid-transform computation (3-point frame registration, matrix/quaternion math).
- `polygon2d.ts` — 2D polygon utilities.
- `glbMerge.ts` — merge multiple GLB models.

**3D scene components (Threlte)**
- `Scene.svelte` / `SceneInner.svelte` — base 3D scene (camera, lights, loaded GLBs).
- `NavigateView.svelte` / `NavigateSceneInner.svelte` — route-finding scene + UI.
- `BuildingStitchScene.svelte` / `StitchSceneInner.svelte` — multi-space stitching with transform gizmos.
- `TransformedGltf.svelte`, `BoundingBoxMesh.svelte`, `DensityHeatmap.svelte` — transformed GLB, bbox wireframe, and floor density overlays.

## Backend integration

- **Supabase** is the primary backend: Postgres tables, email/password auth, storage
  buckets (`spaces_bucket` for GLBs and navmeshes, image/log buckets), and realtime
  subscriptions for live user position.
- **`mono_service`** (`VITE_MONO_URL`) is called for compute such as space bounding-box
  generation; route-finding and stitching also flow through it.

## Stack

SvelteKit 5 · Vite · Threlte 8 / three.js · `@supabase/supabase-js` ·
`recast-navigation` (+ `@recast-navigation/three`) · `concaveman` / `polygon-clipping`
· `lucide-svelte` · TypeScript.
