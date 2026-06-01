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
# localised_space_id, user_pos (building-space xyz), anchor_pairs, calibration.
# When LOCATION_EXPERIMENT_LOCAL is false, samples are written to Supabase
# (experiment_logs table). When true, saved to user://experiment_<timestamp>.json
# on-device instead — useful for offline or high-frequency capture.
const LOCATION_EXPERIMENT := false
const LOCATION_EXPERIMENT_INTERVAL := 0.2   # seconds between samples
const LOCATION_EXPERIMENT_FLUSH_INTERVAL := 30.0  # seconds between DB/file writes
const LOCATION_EXPERIMENT_LOCAL := false

const ANCHOR_VERBOSE_LOG := true

const PERIODIC_RECALIBRATION := true
const PERIODIC_RECALIBRATION_INTERVAL := 3.0  # seconds

const OCCLUSION_ENABLED := true
const TOF_OCCLUSION_ENABLED := true

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
const CALIBRATION_VALIDATION := false
const CALIBRATION_VALIDATION_MIN_ANCHORS := 4

# If non-empty, only anchors with these names will be used as calibration anchors
# (the rest become holdouts). Falls back to random selection if none of the named
# anchors are found in the current space.
const CALIBRATION_ANCHOR_NAMES: Array[String] = []

# =============================================================================
# CROSS-SPACE ALIGNMENT VISUALISATION
# When true: after calibrating to a new space, spawns markers on each of that
# space's reference anchors showing two predictions -
#   orange: where the previous space's calibration + stitch offset predicts them
#   green:  where this space's own calibration places them
# The distance between the two is the error you would incur by not recalibrating.
# =============================================================================
const CROSS_SPACE_ALIGNMENT_VIZ := false
