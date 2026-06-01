class_name NavigatingState
extends State

## User is navigating within a calibrated space. Space label is shown as a
## standalone 3D panel; UI panel is hidden. Right-hand pinch-hold opens the
## 3D context menu.

const _SPACE_LABEL_SCENE := preload("res://ui/standalone/space_label/space_label_3d.tscn")

var _space_label_3d: ViewportPanel3D = null
var _space_names: Dictionary = {}  # space_id → name
var _experiment_running := false
var _experiment_samples: Array = []
var _experiment_events: Array = []
var _experiment_row_id := ""
var _experiment_local_path := ""


func enter(data: Dictionary) -> void:
	ui_panel.visible = false

	if DevConfig.SHOW_SPACE_LABEL:
		_space_label_3d = _SPACE_LABEL_SCENE.instantiate()
		gesture_manager.get_parent().add_child(_space_label_3d)
	location_manager.coarse_space_changed.connect(_on_coarse_space_changed)
	location_manager.localised_space_changed.connect(_on_localised_space_changed)
	location_manager.localised_space_changed.connect(_on_localisation_event)

	var spaces: Array[Space] = await SupabaseManager.get_spaces()
	for s in spaces:
		_space_names[s.id] = s.name if not s.name.is_empty() else s.id

	var space_id: String = data.get("space_id", "")
	var space := data.get("space") as Space
	if space_id.is_empty() and space:
		if not await space_manager.ensure_space_local(space):
			return
		space_id = space.id
	if not space_id.is_empty() and not data.get("pre_calibrated", false):
		location_manager.calibrate_to_space(space_id)

	if DevConfig.LOCATION_EXPERIMENT:
		_experiment_running = true
		if DevConfig.LOCATION_EXPERIMENT_LOCAL:
			_experiment_local_path = "user://experiment_%d.json" % int(Time.get_unix_time_from_system())
		_run_experiment_loop()


func _serialise_transform(t: Transform3D) -> Dictionary:
	var q := t.basis.get_rotation_quaternion()
	return {
		"position": {"x": snappedf(t.origin.x, 0.0001), "y": snappedf(t.origin.y, 0.0001), "z": snappedf(t.origin.z, 0.0001)},
		"quaternion": {"x": snappedf(q.x, 0.0001), "y": snappedf(q.y, 0.0001), "z": snappedf(q.z, 0.0001), "w": snappedf(q.w, 0.0001)},
	}


func _run_experiment_loop() -> void:
	var flush_timer := 0.0
	while _experiment_running:
		await location_manager.get_tree().create_timer(DevConfig.LOCATION_EXPERIMENT_INTERVAL).timeout
		if not _experiment_running:
			break
		var camera := location_manager.get_viewport().get_camera_3d()
		var user_building_pos := Vector3.ZERO
		if camera and anchor_manager._calibrated:
			var glb_pos := anchor_manager.world_to_glb(camera.position)
			var offsets := anchor_manager.get_space_offsets()
			var offset: Transform3D = offsets.get(anchor_manager.get_current_space_id(), Transform3D.IDENTITY)
			user_building_pos = offset * glb_pos
		var data := {
			"loc_confidence": location_manager.get_loc_confidence(),
			"kabsch_error_m": snappedf(anchor_manager.get_last_kabsch_error(), 0.0001),
			"coarse_space_id": location_manager.current_coarse_space,
			"localised_space_id": anchor_manager.get_current_space_id(),
			"user_pos": {
				"x": snappedf(user_building_pos.x, 0.001),
				"y": snappedf(user_building_pos.y, 0.001),
				"z": snappedf(user_building_pos.z, 0.001),
			},
			"anchor_pairs": anchor_manager.get_kabsch_pairs(),
			"calibration": _serialise_transform(anchor_manager.get_calibration()),
		}
		data["fps"] = Engine.get_frames_per_second()
		data["anchor_xr_positions"] = anchor_manager.get_space_anchor_xr_positions()
		_experiment_samples.append(data)

		flush_timer += DevConfig.LOCATION_EXPERIMENT_INTERVAL
		if flush_timer < DevConfig.LOCATION_EXPERIMENT_FLUSH_INTERVAL:
			continue
		flush_timer = 0.0
		_flush_experiment()


func _flush_experiment() -> void:
	if _experiment_samples.is_empty():
		return
	var payload := {"samples": _experiment_samples, "events": _experiment_events}
	if DevConfig.LOCATION_EXPERIMENT_LOCAL:
		var f := FileAccess.open(_experiment_local_path, FileAccess.WRITE)
		if f:
			f.store_string(JSON.stringify(payload))
			f.close()
	elif _experiment_row_id.is_empty():
		_experiment_row_id = await SupabaseManager.insert_experiment_log(payload)
	else:
		SupabaseManager.update_experiment_log(_experiment_row_id, payload)


func exit() -> void:
	_experiment_running = false
	_flush_experiment()
	if DevConfig.LOCATION_EXPERIMENT_LOCAL:
		print("NavigatingState: experiment saved locally to ", _experiment_local_path)
	_experiment_samples.clear()
	_experiment_events.clear()
	_experiment_row_id = ""
	_experiment_local_path = ""
	location_manager.coarse_space_changed.disconnect(_on_coarse_space_changed)
	location_manager.localised_space_changed.disconnect(_on_localised_space_changed)
	location_manager.localised_space_changed.disconnect(_on_localisation_event)
	if _space_label_3d:
		_space_label_3d.queue_free()
		_space_label_3d = null

	_context_close()
	_context_pending = false
	progress_indicator.clear()
	route_manager.clear_goto_route()
	anchor_manager.clear_markers()
	note_manager.clear()


# ── Gestures ──────────────────────────────────────────────────────────────────

func _on_localisation_event(space_id: String) -> void:
	if not _experiment_running:
		return
	_experiment_events.append({
		"type": "localisation",
		"space_id": space_id,
		"t": snappedf(Time.get_unix_time_from_system(), 0.001),
		"sample_index": _experiment_samples.size(),
	})


func _on_coarse_space_changed(space_id: String) -> void:
	var sl := _space_label_3d.get_panel() as SpaceLabel if _space_label_3d else null
	if sl:
		sl.update_coarse(_space_names.get(space_id, space_id))


func _on_localised_space_changed(space_id: String) -> void:
	var sl := _space_label_3d.get_panel() as SpaceLabel if _space_label_3d else null
	if sl:
		sl.update_localised(_space_names.get(space_id, space_id))


func on_pinch_held(hand: String, position: Vector3, duration: float) -> void:
	if hand == "right":
		_context_update_hold(position, duration)


func on_pinch_ended(hand: String) -> void:
	if hand == "right":
		_context_handle_end()
