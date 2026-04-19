class_name ProcedureState
extends State

## User is running a procedure in a calibrated space. Step viewer is shown as
## a standalone 3D panel. Left/right pinches step back/forward; right-hold
## opens the context menu. Voice commands drive the step viewer too.

const _STEP_VIEWER_SCENE := preload("res://ui/standalone/step_viewer/step_viewer_3d.tscn")

var _step_viewer_3d: ViewportPanel3D = null


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
	if not space_id.is_empty():
		location_manager.calibrate_to_space(space_id)

	_step_viewer_3d = _STEP_VIEWER_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_step_viewer_3d)
	if procedure:
		var sv := _step_viewer_3d.get_panel() as StepViewer
		if sv:
			sv.init({"procedure": procedure})


func exit() -> void:
	PanelRouter.action_requested.disconnect(_on_action)
	voice_manager.next_step.disconnect(_voice_next)
	voice_manager.previous_step.disconnect(_voice_prev)

	if _step_viewer_3d:
		_step_viewer_3d.queue_free()
		_step_viewer_3d = null

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

func on_pinch_started(hand: String, _position: Vector3) -> void:
	var sv := _step_viewer()
	if not sv:
		return
	if hand == "left":
		sv.prev_step()
	elif hand == "right":
		sv.next_step()


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
