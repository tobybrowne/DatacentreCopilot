class_name ProcedureState
extends State

## User is running a procedure in a calibrated space. UI panel is visible
## (hosting the step viewer). Left/right pinches step back/forward; right-hold
## opens the context menu. Voice commands drive the step viewer too.


func enter(data: Dictionary) -> void:
	ui_panel.visible = true
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

	if procedure:
		PanelRouter.push("step_viewer", {"procedure": procedure})


func exit() -> void:
	PanelRouter.action_requested.disconnect(_on_action)
	voice_manager.next_step.disconnect(_voice_next)
	voice_manager.previous_step.disconnect(_voice_prev)

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
	return ui_panel.get_panel() as StepViewer
