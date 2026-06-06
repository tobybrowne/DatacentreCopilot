class_name DevConfig

# =============================================================================
# DEV MODE
# When true: all markers visible (reference anchors, content anchors, bounding boxes).
# When false (production): only asset and note markers are shown.
# =============================================================================
const DEV_MODE := false

# When true: logs localisation quality, Kabsch error, anchor positions and user
# position every LOCATION_EXPERIMENT_INTERVAL seconds while in NavigatingState.
# Each sample contains: loc_confidence, kabsch_error_m, coarse_space_id,
# localised_space_id, user_pos (building-space xyz), anchor_pairs, calibration,
# fps, anchor_xr_positions (current-space reference anchors), and asset_positions
# (world positions of every building-wide asset marker - persists across
# re-localisation, so usable for content-judder analysis).
# When LOCATION_EXPERIMENT_LOCAL is false, samples are written to Supabase
# (experiment_logs table). When true, saved to user://experiment_<timestamp>.json
# on-device instead — useful for offline or high-frequency capture.
const LOCATION_EXPERIMENT := true
const LOCATION_EXPERIMENT_INTERVAL := 0.2   # seconds between samples
const LOCATION_EXPERIMENT_FLUSH_INTERVAL := 30.0  # seconds between DB/file writes
const LOCATION_EXPERIMENT_LOCAL := true

const ANCHOR_VERBOSE_LOG := true

const PERIODIC_RECALIBRATION := true
const PERIODIC_RECALIBRATION_INTERVAL := 3.0  # seconds

# =============================================================================
# ICP CALIBRATION REFINEMENT
# Periodically refine the Kabsch anchor calibration against the live ML2 world
# mesh via the backend /stitch/refine_live endpoint. The current calibration
# seeds the ICP; the result is stored as a correction (relative to the pure
# Kabsch solve) applied on top of every subsequent Kabsch solve, so the periodic
# recalibration and ICP refinement don't fight.
# =============================================================================
const ICP_REFINEMENT := false
const ICP_REFINEMENT_INTERVAL := 10.0       # seconds between ICP refinement passes
const ICP_REFINEMENT_VOXEL := 0.05          # downsample live mesh to this spacing (m) before upload
const ICP_REFINEMENT_MIN_POINTS := 500      # skip refinement if fewer live points than this
const ICP_REFINEMENT_MIN_FITNESS := 0.3     # reject result below this Open3D fitness
const ICP_REFINEMENT_MAX_DELTA := 0.5       # reject if it moves the calibration more than this (m) from the seed
# When true: ignore MIN_FITNESS / MAX_DELTA and snap exactly to every ICP result.
const ICP_REFINEMENT_FORCE := false

const OCCLUSION_ENABLED := false
const TOF_OCCLUSION_ENABLED := false

# When true: registers a local ML2 voice intent ("show map") that opens the
# dollhouse map directly, bypassing the copilot WebSocket. Headset-only dev
# shortcut for testing the map without the realtime voice connection.
const DOLLHOUSE_MAP_VOICE_SHORTCUT := false

const SHOW_FPS := true
const SHOW_BOUNDING_BOXES := false

# When false: hides the floating space-name label shown above the user while
# navigating.
const SHOW_SPACE_LABEL := false

# =============================================================================
# CALIBRATION VALIDATION
# When true and a space has more than CALIBRATION_VALIDATION_MIN_ANCHORS reference
# anchors, the excess anchors are held out from calibration and used to measure
# prediction error: their positions are predicted from GLB coords + the calibration
# matrix and compared visually and numerically to where ML2 actually tracked them.
# =============================================================================
const CALIBRATION_VALIDATION := true
const CALIBRATION_VALIDATION_MIN_ANCHORS := 6

# If non-empty, only anchors with these names will be used as calibration anchors
# (the rest become holdouts). Falls back to random selection if none of the named
# anchors are found in the current space.
const CALIBRATION_ANCHOR_NAMES: Array[String] = ["52", "53", "55", "62"]

# =============================================================================
# CROSS-SPACE ALIGNMENT VISUALISATION
# When true: after calibrating to a new space, spawns markers on each of that
# space's reference anchors showing two predictions -
#   orange: where the previous space's calibration + stitch offset predicts them
#   green:  where this space's own calibration places them
# The distance between the two is the error you would incur by not recalibrating.
# =============================================================================
const CROSS_SPACE_ALIGNMENT_VIZ := false
