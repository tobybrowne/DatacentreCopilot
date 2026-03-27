# entangl-copilot

AR procedure guidance application for Magic Leap 2, built with Godot 4.6.1 (mono). Displays step-by-step procedures fetched from Supabase and lets the user place world-locked spatial anchors to persist content positions across sessions.

---

## Project structure

```
entangl-copilot/
├── launch.sh                  # Build & deploy to ML2 via ADB, streams logcat
├── supabase/                  # Supabase migrations and seed data
└── app/                       # Godot project
    ├── main.tscn / main.gd    # Scene root, XR init, anchor placement input
    ├── anchor_manager.gd      # ML2 spatial anchor lifecycle (create/load/save/remove)
    ├── SupabaseManager.gd     # Fetches procedures from Supabase
    ├── procedure_panel*       # UI for selecting a procedure
    ├── step_viewer*           # Displays current step
    ├── pinch_step_control.gd  # Left/right pinch → prev/next step
    └── addons/godotopenxrvendors/  # Custom-built ML2 OpenXR plugin (see below)
```

---

## Scene hierarchy

```
Main (Node3D)
└── XROrigin3D              ← tracking space origin
    ├── XRCamera3D          ← head pose (updated by OpenXR runtime)
    ├── LeftHand / RightHand (XRNode3D + skeleton)
    ├── UIPanel             ← floating UI, follows head
    ├── ProcedurePanel      ← procedure list
    ├── StepViewer          ← current step display
    ├── PinchStepControl    ← detects left/right pinch
    └── AnchorManager       ← manages spatial anchors
```

> **Important:** Any content that must appear at a fixed physical location must be under `XROrigin3D` and driven by an `XRAnchor3D` tracker. Static scene objects placed at a fixed world transform will appear relative to where your head was when the app started (see Coordinate System below).

---

## Spatial anchor system

### Coordinate systems on ML2

Magic Leap 2 runs OpenXR with a **LOCAL reference space**. The LOCAL space places its origin at the device's position/orientation at session start. This means:

- `XROrigin3D` maps to the LOCAL space origin — wherever your head was when the app launched.
- All Godot world coordinates are relative to that starting position.
- A `MeshInstance3D` placed at `(0, 0, -5)` in the scene always appears 5 m in front of your starting head position, **not** at a fixed physical location in the room.

Spatial anchors bypass this entirely. When you create an anchor, ML2's OpenXR runtime:
1. Records the anchor's position in its internal **spatial map** — a persistent, device-wide coordinate system tied to the physical environment (like ARKit/ARCore world anchors).
2. Assigns it a UUID.
3. On subsequent sessions, when you call `load_anchor(uuid)`, the runtime relocates the anchor in the spatial map and reports its pose relative to the current LOCAL space origin each frame.

The net effect: `XRAnchor3D` nodes (which read the anchor's tracker pose) always end up at the correct physical location regardless of where your head was at startup.

### How `anchor_manager.gd` works

```
_ready()
  └── instantiate OpenXRMlSpatialAnchorManager
  └── connect signals (tracked / untracked / failed)
  └── connect tree_entered → _on_mgr_entered_tree   (deferred add_child)
  └── add_child.call_deferred(_ml_mgr)               ← must be under XROrigin3D

_on_mgr_entered_tree()   (fires after add_child completes)
  └── connect xr.session_begun → _load_anchors
  └── if xr already active → _load_anchors()         ← safe: node is in tree now

place_anchor(world_transform)
  └── _ml_mgr.create_anchor(world_transform)
        → async: ML2 creates XrSpace, publishes to storage, returns UUID
        → on success: openxr_ml_spatial_anchor_tracked(anchor_node, uuid, is_new=true)

_on_anchor_tracked(anchor_node, uuid, is_new)
  └── add visual marker as child of anchor_node
  └── if is_new: _save_anchors()

_load_anchors()   (called when session begins)
  └── reads UUIDs from user://spatial_anchors.json
  └── for each uuid: _ml_mgr.load_anchor(uuid)
        → async: ML2 recreates XrSpace from storage
        → on success: openxr_ml_spatial_anchor_tracked(anchor_node, uuid, is_new=false)
```

### Why `OpenXRMlSpatialAnchorManager` must be under `XROrigin3D`

The C++ node stores a pointer to its `XROrigin3D` parent on `NOTIFICATION_ENTER_TREE`. It uses this to convert between global world space and XROrigin-local space when creating/loading anchors. If the node isn't in the tree (or isn't a child of `XROrigin3D`), the pointer is null and all anchor operations fail immediately.

### Anchor persistence

UUIDs are stored in `user://spatial_anchors.json` on the device. ML2's spatial map persists anchor data between sessions at the system level — the UUID is the key into that system store. If you uninstall the app the JSON file is deleted, but the anchor data in the ML2 spatial map may remain (it can be cleared from the ML2 system settings).

---

## Placing world-locked content

To attach content to a specific physical location:

1. Place a spatial anchor there (right-hand pinch, hold 1 second).
2. The `openxr_ml_spatial_anchor_tracked` signal fires with the `XRAnchor3D` node.
3. Add your content as a child of that `XRAnchor3D` node — it will track the physical location each session.

**Do not** place world-locked content as a static scene node with a fixed `Transform3D`. That transform is relative to the LOCAL space origin (head position at startup) and will drift between sessions.

---

## Building and deploying

```bash
# Deploy to connected ML2 and stream logs
./launch.sh
```

`launch.sh` runs a Gradle one-click deploy via ADB, force-stops the previous instance, starts the app in OpenXR immersive mode, and streams `logcat -s godot`.

The Godot project uses a custom-built `godotopenxrvendors` plugin (see `app/addons/godotopenxrvendors/`). The AAR files there must be rebuilt after any C++ changes to the plugin — see the plugin repo README.

---

## What was changed (commit guide)

### `launch.sh`
Added `$ADB logcat -s godot` so Godot output is visible in the terminal during development.

### `app/SupabaseManager.gd`
Added a null guard before iterating `task.data`. When the Supabase host is unreachable, the HTTP response can fail JSON parsing and leave `task.data = null` without setting `task.error`, which previously crashed.

### `app/android/build/src/main/AndroidManifest.xml`
Added `com.magicleap.permission.SPATIAL_ANCHOR` permission. Without this the ML2 runtime denies all anchor API calls at runtime even if the extension is loaded.

### `app/anchor_manager.gd`
Two timing fixes were needed to get `OpenXRMlSpatialAnchorManager` properly into the scene tree before being used:

1. **`add_child.call_deferred`** — `_ready()` is called while the parent node is still setting up its children. Calling `add_child` synchronously during `_ready` fails ("parent node busy"). Deferring it to the next frame resolves this.

2. **`tree_entered` gate** — The OpenXR `session_begun` signal (and the `xr.is_initialized()` fast-path) must not be connected until after `_ml_mgr` is confirmed to be in the scene tree. The signal can fire in the same frame as `_ready`, before the deferred `add_child` runs, causing `load_anchor` to fail because `xr_origin` is still null inside the C++ node. Gating all XR session setup on `_ml_mgr.tree_entered` fixes this completely.

### Files to commit (entangl-copilot repo)

```
launch.sh
app/SupabaseManager.gd
app/anchor_manager.gd
app/android/build/src/main/AndroidManifest.xml
app/addons/godotopenxrvendors/.bin/android/debug/godotopenxr-magicleap-debug.aar
app/addons/godotopenxrvendors/.bin/android/release/godotopenxr-magicleap-release.aar
```

The AAR files contain the rebuilt plugin with ML2 spatial anchor support (x86_64 + arm64) and the `register_types.cpp` bug fix (see plugin repo). They are binary build artefacts — if you prefer not to commit them, document the rebuild steps instead and `.gitignore` them.

---

## Dependencies

- Godot 4.6.1 stable mono
- Custom `godotopenxrvendors` plugin (built from `github.com/[your-fork]/godot_openxr_vendors`)
- Supabase project (URL and anon key in `app/addons/supabase/supabase.cfg`)
- Magic Leap Hub + ML2 device in developer mode
- Android SDK with `adb` available at `~/Library/Android/sdk/platform-tools/adb`
