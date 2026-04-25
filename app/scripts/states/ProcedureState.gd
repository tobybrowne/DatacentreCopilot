class_name ProcedureState
extends State

## User is running a procedure in a calibrated space. Step viewer is shown as
## a standalone 3D panel. Left/right pinches step back/forward; right-hold
## opens the context menu. Voice commands drive the step viewer too.

const _STEP_VIEWER_SCENE := preload("res://ui/standalone/step_viewer/step_viewer_3d.tscn")
const _VIDEO_PLAYER_SCENE := preload("res://ui/standalone/video_player/video_player_panel_3d.tscn")
const _LOG_BROWSER_SCENE := preload("res://ui/standalone/log_browser/log_browser_panel_3d.tscn")
const _LOGS_FAB_SCENE := preload("res://ui/standalone/logs_fab/logs_fab_3d.tscn")
const _VIDEO_TMP_PATH := "user://replay_video.ogv"

var _step_viewer_3d: ViewportPanel3D = null
var _logs_fab_3d: ViewportPanel3D = null
var _wrist_panel: WristPanel3D = null
var _gesture_replayer: PoseReplayer = null
var _video_player_3d: ViewportPanel3D = null
var _log_browser_3d: ViewportPanel3D = null
var _current_step: Step = null
var _current_log_id: String = ""
var _replay_loading: bool = false


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
			sv.stop_requested.connect(_on_stop_requested)
			sv.init({"procedure": procedure})

	_logs_fab_3d = _LOGS_FAB_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_logs_fab_3d)
	var fab := _logs_fab_3d.get_panel() as LogsFab
	if fab:
		fab.logs_requested.connect(_on_logs_requested)

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
	_stop_video()

	if _step_viewer_3d:
		_step_viewer_3d.queue_free()
		_step_viewer_3d = null

	if _logs_fab_3d:
		_logs_fab_3d.queue_free()
		_logs_fab_3d = null

	if _wrist_panel:
		_wrist_panel.queue_free()
		_wrist_panel = null

	_close_log_browser()
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
	_stop_video()
	_current_step = next_step
	_current_log_id = next_step.log_id if next_step else ""
	var sv := _step_viewer()
	if sv:
		sv.show_replay_button(not _current_log_id.is_empty())
	if _log_browser_3d and next_step:
		var panel := _log_browser_3d.get_panel() as LogBrowserPanel
		if panel:
			panel.init({"step_id": next_step.id})


func _fetch_log_paths(log_id: String) -> Array[String]:
	var task = await Supabase.database.query(
		SupabaseQuery.new()
			.from("logs")
			.select(["geometry_recording_path", "camera_recording_path_ogv"])
			.eq("id", log_id)
			.range(0, 0)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		return ["", ""]
	var row: Dictionary = task.data[0]
	var geo: String = row.get("geometry_recording_path", "") if row.get("geometry_recording_path") != null else ""
	var ogv: String = row.get("camera_recording_path_ogv", "") if row.get("camera_recording_path_ogv") != null else ""
	return [geo, ogv]


func _on_replay_requested() -> void:
	if _replay_loading or _current_log_id.is_empty():
		return
	_replay_loading = true
	_stop_replay()
	_stop_video()

	var paths := await _fetch_log_paths(_current_log_id)
	var geo_path: String = paths[0]
	var cam_path: String = paths[1]

	if not geo_path.is_empty():
		var a = Time.get_ticks_msec()
		print("Downloading Replay...")
		var task = await Supabase.storage.from("log_bucket").download(geo_path, "", true).completed
		if task.error != null:
			push_warning("ProcedureState: replay download failed \u2014 %s" % task.error.message)
		else:
			var frames := PoseRec.frames_from_bytes(task.data)
			if frames.is_empty():
				push_warning("ProcedureState: no frames in replay recording")
			else:
				var b = Time.get_ticks_msec()
				print("Finished downloading... (%d ms)" % (b - a))
				_gesture_replayer = PoseReplayer.new()
				_gesture_replayer.skeleton_enabled = true
				gesture_manager.get_parent().add_child(_gesture_replayer)
				_gesture_replayer.global_transform = location_manager.get_calibration()
				_gesture_replayer.play(frames, true)
				b = Time.get_ticks_msec()
				print("Gesture Replay 'play' called... (%d ms)" % (b - a))

	if not cam_path.is_empty():
		var vtask = await Supabase.storage.from("log_bucket").download(cam_path, "", true).completed
		if vtask.error != null:
			push_warning("ProcedureState: video replay download failed \u2014 %s" % vtask.error.message)
		else:
			_launch_video_player(vtask.data)

	_replay_loading = false


func _on_stop_requested() -> void:
	_replay_loading = false
	_stop_replay()
	_stop_video()
	var sv := _step_viewer()
	if sv:
		sv.reset_replay_button()


func _stop_replay() -> void:
	if _gesture_replayer:
		_gesture_replayer.queue_free()
		_gesture_replayer = null
		var sv := _step_viewer()
		if sv:
			sv.reset_replay_button()


func _launch_video_player(data: PackedByteArray) -> void:
	var f := FileAccess.open(_VIDEO_TMP_PATH, FileAccess.WRITE)
	if not f:
		push_warning("ProcedureState: could not write temp video file")
		return
	f.store_buffer(data)
	f.close()
	_video_player_3d = _VIDEO_PLAYER_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_video_player_3d)
	var panel := _video_player_3d.get_panel() as VideoPlayerPanel
	if panel:
		panel.close_requested.connect(_stop_video)
		panel.init({"path": _VIDEO_TMP_PATH})


func _stop_video() -> void:
	if _video_player_3d:
		_video_player_3d.queue_free()
		_video_player_3d = null
	if FileAccess.file_exists(_VIDEO_TMP_PATH):
		DirAccess.remove_absolute(_VIDEO_TMP_PATH)


# ── Log Browser ───────────────────────────────────────────────────────────────

func _on_logs_requested() -> void:
	if _log_browser_3d:
		_close_log_browser()
		return
	if not _current_step:
		return
	_log_browser_3d = _LOG_BROWSER_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_log_browser_3d)
	var panel := _log_browser_3d.get_panel() as LogBrowserPanel
	if panel:
		panel.close_requested.connect(_close_log_browser)
		panel.play_requested.connect(_on_log_browser_play)
		panel.stop_requested.connect(_on_log_browser_stop)
		panel.init({"step_id": _current_step.id})


func _close_log_browser() -> void:
	if _log_browser_3d:
		_stop_replay()
		_log_browser_3d.queue_free()
		_log_browser_3d = null


func _on_log_browser_play(log_id: String, geo_path: String, ogv_path: String) -> void:
	if _replay_loading:
		return
	_replay_loading = true
	_stop_replay()
	_stop_video()

	if not geo_path.is_empty():
		print("Log Browser: downloading geometry %s" % geo_path)
		var task = await Supabase.storage.from("log_bucket").download(geo_path, "", true).completed
		if task.error != null:
			push_warning("ProcedureState: log browser geo download failed — %s" % task.error.message)
		else:
			var frames := PoseRec.frames_from_bytes(task.data)
			if not frames.is_empty():
				_gesture_replayer = PoseReplayer.new()
				_gesture_replayer.skeleton_enabled = true
				gesture_manager.get_parent().add_child(_gesture_replayer)
				_gesture_replayer.global_transform = location_manager.get_calibration()
				_gesture_replayer.playback_finished.connect(_on_log_browser_playback_finished)
				_gesture_replayer.play(frames, false)

	if not ogv_path.is_empty():
		print("Log Browser: downloading video %s" % ogv_path)
		var vtask = await Supabase.storage.from("log_bucket").download(ogv_path, "", true).completed
		if vtask.error != null:
			push_warning("ProcedureState: log browser video download failed — %s" % vtask.error.message)
		else:
			_launch_video_player(vtask.data)

	_replay_loading = false


func _on_log_browser_stop() -> void:
	_stop_replay()


func _on_log_browser_playback_finished() -> void:
	_gesture_replayer = null
	var panel := _log_browser_3d.get_panel() as LogBrowserPanel if _log_browser_3d else null
	if panel:
		panel.notify_playback_finished()
