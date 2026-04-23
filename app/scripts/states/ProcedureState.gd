class_name ProcedureState
extends State

## User is running a procedure in a calibrated space. Step viewer is shown as
## a standalone 3D panel. Left/right pinches step back/forward; right-hold
## opens the context menu. Voice commands drive the step viewer too.

const _STEP_VIEWER_SCENE := preload("res://ui/standalone/step_viewer/step_viewer_3d.tscn")

var _step_viewer_3d: ViewportPanel3D = null
var _wrist_panel: WristPanel3D = null
var _gesture_replayer: PoseReplayer = null
var _current_log_path: String = ""


func enter(data: Dictionary) -> void:
	ui_panel.visible = false
	PanelRouter.action_requested.connect(_on_action)

	voice_manager.next_step.connect(_voice_next)
	voice_manager.previous_step.connect(_voice_prev)

	var procedure := data.get("procedure") as Procedure
	var space_id: String = data.get("space_id", "")
	var space := data.get("space") as Space
	if space_id.is_empty() and space:
		if not await location_manager.ensure_space_local(space):
			return
		space_id = space.id
	if not space_id.is_empty() and not data.get("pre_calibrated", false):
		location_manager.calibrate_to_space(space_id)

	_step_viewer_3d = _STEP_VIEWER_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_step_viewer_3d)
	if procedure:
		var site_id: String = space.site_id if space else ""
		await LogManager.start_procedure(procedure, site_id)
		var sv := _step_viewer_3d.get_panel() as StepViewer
		if sv:
			sv.step_changed.connect(LogManager.on_step_changed)
			sv.step_changed.connect(_on_step_changed_for_replay)
			sv.replay_requested.connect(_on_replay_requested)
			sv.init({"procedure": procedure})

	_wrist_panel = WristPanel3D.new()
	gesture_manager.get_parent().add_child(_wrist_panel)
	_wrist_panel.prev_requested.connect(_voice_prev)
	_wrist_panel.next_requested.connect(_voice_next)


func exit() -> void:
	PanelRouter.action_requested.disconnect(_on_action)
	voice_manager.next_step.disconnect(_voice_next)
	voice_manager.previous_step.disconnect(_voice_prev)

	LogManager.end_procedure()
	_stop_replay()

	if _step_viewer_3d:
		_step_viewer_3d.queue_free()
		_step_viewer_3d = null

	if _wrist_panel:
		_wrist_panel.queue_free()
		_wrist_panel = null

	_context_close()
	_context_pending = false
	progress_indicator.clear()
	route_manager.clear_goto_route()
	location_manager.clear_markers()
	NoteManager.clear()


func _on_action(action: String, data: Dictionary) -> void:
	match action:
		"goto_step":
			route_manager.handle_goto_step(data.get("anchor_id", ""))
		"goto_cleared":
			route_manager.clear_goto_route()


# ── Gestures ──────────────────────────────────────────────────────────────────

func on_pinch_started(_hand: String, _position: Vector3) -> void:
	pass


func on_pinch_held(hand: String, position: Vector3, duration: float) -> void:
	if hand == "right":
		_context_update_hold(position, duration)


func on_pinch_ended(hand: String) -> void:
	if hand == "right":
		_context_handle_end()


# ── Voice ─────────────────────────────────────────────────────────────────────

func _voice_next() -> void:
	var sv := _step_viewer()
	if sv: sv.next_step()


func _voice_prev() -> void:
	var sv := _step_viewer()
	if sv: sv.prev_step()


func _step_viewer() -> StepViewer:
	if not _step_viewer_3d:
		return null
	return _step_viewer_3d.get_panel() as StepViewer


# ── Replay ────────────────────────────────────────────────────────────────────

func _on_step_changed_for_replay(_prev: Step, next_step: Step) -> void:
	_stop_replay()
	_current_log_path = ""
	var sv := _step_viewer()
	if sv:
		sv.show_replay_button(false)
	if not next_step:
		return
	var path := await _fetch_log_path(next_step.id)
	_current_log_path = path
	sv = _step_viewer()
	if sv:
		sv.show_replay_button(not path.is_empty())


func _fetch_log_path(step_id: String) -> String:
	var task = await Supabase.database.query(
		SupabaseQuery.new()
			.from("logs")
			.select(["geometry_recording_path"])
			.eq("step_id", step_id)
			.Is("geometry_recording_path", "null", true)
			.order("created_at", SupabaseQuery.Directions.Descending)
			.range(0, 0)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		return ""
	return task.data[0].get("geometry_recording_path", "")


func _on_replay_requested() -> void:
	if _current_log_path.is_empty():
		return
	var task = await Supabase.storage.from("log_bucket").download(_current_log_path, "", true).completed
	if task.error != null:
		push_warning("ProcedureState: replay download failed — %s" % task.error.message)
		return
	var frames := PoseRec.frames_from_bytes(task.data)
	if frames.is_empty():
		push_warning("ProcedureState: no frames in replay recording")
		return
	_stop_replay()
	_gesture_replayer = PoseReplayer.new()
	_gesture_replayer.skeleton_enabled = true
	gesture_manager.get_parent().add_child(_gesture_replayer)
	_gesture_replayer.global_transform = location_manager.get_calibration()
	_gesture_replayer.play(frames, true)


func _stop_replay() -> void:
	if _gesture_replayer:
		_gesture_replayer.queue_free()
		_gesture_replayer = null
