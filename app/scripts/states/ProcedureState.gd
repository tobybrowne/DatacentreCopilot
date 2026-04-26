class_name ProcedureState
extends State

## User is running a procedure in a calibrated space. Step viewer is shown as
## a standalone 3D panel. Left/right pinches step back/forward; right-hold
## opens the context menu. Voice commands drive the step viewer too.

const _STEP_VIEWER_SCENE := preload("res://ui/standalone/step_viewer/step_viewer_3d.tscn")

var _step_viewer_3d: ViewportPanel3D = null
var _logs: LogsController3D = null
var _wrist_panel: WristPanel3D = null
var _current_step: Step = null
var _current_log_id: String = ""


func enter(data: Dictionary) -> void:
	ui_panel.visible = false
	PanelRouter.action_requested.connect(_on_action)

	CopilotManager.update_tools([
		{
			"type": "function",
			"name": "next_step",
			"description": "Navigate to the next step in the current procedure",
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"type": "function",
			"name": "previous_step",
			"description": "Navigate to the previous step in the current procedure",
			"parameters": {"type": "object", "properties": {}},
		},
		{
			"type": "function",
			"name": "go_home",
			"description": "Exit the current procedure and return to the home screen",
			"parameters": {"type": "object", "properties": {}},
		},
	])
	CopilotManager.function_called.connect(_on_copilot_function)

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

	_logs = LogsController3D.new()
	gesture_manager.get_parent().add_child(_logs)
	_logs.replay_ended.connect(func():
		var sv := _step_viewer()
		if sv: sv.reset_replay_button()
	)

	_wrist_panel = WristPanel3D.new()
	gesture_manager.get_parent().add_child(_wrist_panel)
	_wrist_panel.prev_requested.connect(_voice_prev)
	_wrist_panel.next_requested.connect(_voice_next)


func exit() -> void:
	PanelRouter.action_requested.disconnect(_on_action)
	CopilotManager.update_tools([])
	CopilotManager.function_called.disconnect(_on_copilot_function)

	LogManager.end_procedure()

	if _step_viewer_3d:
		_step_viewer_3d.queue_free()
		_step_viewer_3d = null

	if _logs:
		_logs.queue_free()
		_logs = null

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


func _on_copilot_function(fn_name: String, call_id: String, _args: Dictionary) -> void:
	match fn_name:
		"next_step":
			_voice_next()
			CopilotManager.send_function_output(call_id, "ok")
		"previous_step":
			_voice_prev()
			CopilotManager.send_function_output(call_id, "ok")
		"go_home":
			CopilotManager.send_function_output(call_id, "ok")
			app.get_node("AppState").go_home()


func _step_viewer() -> StepViewer:
	if not _step_viewer_3d:
		return null
	return _step_viewer_3d.get_panel() as StepViewer


# ── Replay ────────────────────────────────────────────────────────────────────

func _on_step_changed_for_replay(_prev: Step, next_step: Step) -> void:
	_current_step = next_step
	_current_log_id = next_step.log_id if next_step else ""
	var sv := _step_viewer()
	if sv:
		sv.show_replay_button(not _current_log_id.is_empty())
	if _logs:
		_logs.refresh({"step_id": next_step.id} if next_step else {})


func _on_replay_requested() -> void:
	_logs.play_log_id(_current_log_id)
