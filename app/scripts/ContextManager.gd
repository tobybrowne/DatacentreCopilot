extends Node

const GAZE_CONE_DEG  := 20.0
const GAZE_DWELL_SEC := 2.0

var _location_manager: LocationManager = null
var _app_state = null
var _camera: Camera3D = null

var _state := {}
var _debounce_timer: SceneTreeTimer = null

var _gaze_candidate: String = ""
var _gaze_dwell: float = 0.0
var _gaze_reported: String = ""


func setup(location_manager: LocationManager, app_state, camera: Camera3D) -> void:
	_location_manager = location_manager
	_app_state = app_state
	_camera = camera
	location_manager.coarse_space_changed.connect(_on_space_changed)
	app_state.state_changed.connect(_on_app_state_changed)
	PanelRouter.panel_changed.connect(_on_panel_changed)


func _process(delta: float) -> void:
	if _camera == null:
		return
	_update_gaze(delta)

# detects what the user is looking at
func _update_gaze(delta: float) -> void:
	var cam_pos := _camera.global_position
	var cam_fwd := -_camera.global_basis.z
	var best_name := ""
	var best_angle := GAZE_CONE_DEG

	for node in get_tree().get_nodes_in_group("asset_markers"):
		var m := node as AssetAnchorMarker
		if not m or m.get_asset_label().is_empty():
			continue
		var dir := (m.global_position - cam_pos).normalized()
		var angle := rad_to_deg(cam_fwd.angle_to(dir))
		if angle < best_angle:
			best_angle = angle
			best_name = m.get_asset_label()

	if best_name == _gaze_candidate:
		_gaze_dwell += delta
		# if you're looking at something new, schedule a context update
		if _gaze_dwell >= GAZE_DWELL_SEC and _gaze_reported != best_name:
			_gaze_reported = best_name
			if best_name.is_empty():
				_state.erase("looking_at")
			else:
				_state["looking_at"] = best_name
			_schedule_update()
	else:
		_gaze_candidate = best_name
		_gaze_dwell = 0.0


func _on_space_changed(coarse_id: String, active_id: String) -> void:
	_state["space"] = active_id if not active_id.is_empty() else coarse_id
	_schedule_update()


func _on_app_state_changed(_from_name: String, to_name: String) -> void:
	_state["app_state"] = to_name
	_schedule_update()


func _on_panel_changed(panel_id: String, _data: Dictionary) -> void:
	_state["panel"] = panel_id
	_schedule_update()


func set_procedure_context(procedure_title: String, step_num: int, step_total: int, step_text: String) -> void:
	_state["procedure"] = procedure_title
	_state["step"] = "%d/%d: %s" % [step_num, step_total, step_text]
	_schedule_update()


func clear_procedure_context() -> void:
	_state.erase("procedure")
	_state.erase("step")
	_schedule_update()


func on_asset_interacted(asset_name: String, asset_type: String) -> void:
	var label := asset_name if asset_type.is_empty() else "%s (%s)" % [asset_name, asset_type]
	var text := "User just interacted with asset: %s" % label
	print("ContextManager: %s" % text)
	if CopilotManager._is_connected:
		CopilotManager.inject_context(text)


func _schedule_update() -> void:
	if _debounce_timer:
		return
	_debounce_timer = get_tree().create_timer(1.0)
	_debounce_timer.timeout.connect(_flush)


func _flush() -> void:
	_debounce_timer = null
	if not CopilotManager._is_connected:
		return
	var parts := PackedStringArray()
	for key in _state:
		parts.append("%s: %s" % [key, _state[key]])
	if parts.is_empty():
		return
	var text := "[context update]\n" + "\n".join(parts)
	print("ContextManager: %s" % text)
	CopilotManager.inject_context(text)
