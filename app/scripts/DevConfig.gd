class_name DevConfig

# =============================================================================
# DEV MODE
# When true: all markers visible (reference anchors, content anchors, bounding boxes).
# When false (production): only asset and note markers are shown.
# =============================================================================
const DEV_MODE := false

# When true: logs localisation quality, Kabsch error, anchor positions and user
# position to experiment_logs every 0.5 s while in NavigatingState.
const LOCATION_EXPERIMENT := true
const LOCATION_EXPERIMENT_INTERVAL := 0.5  # seconds between log writes

const PERIODIC_RECALIBRATION := true
const PERIODIC_RECALIBRATION_INTERVAL := 3.0  # seconds

const OCCLUSION_ENABLED := true
