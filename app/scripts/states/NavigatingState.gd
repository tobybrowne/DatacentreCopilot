class_name NavigatingState
extends State

## User is navigating within a calibrated space. UI panel is hidden; right-hand
## pinch-hold opens the 3D context menu. No 2D panels are reachable in this
## state, so there are no PanelRouter intents to handle.


func enter(data: Dictionary) -> void:
	ui_panel.visible = false

	var space_id: String = data.get("space_id", "")
	var space := data.get("space") as Space
	if space_id.is_empty() and space:
		if not await location_manager.ensure_space_local(space):
			return
		space_id = space.id
	if not space_id.is_empty():
		location_manager.calibrate_to_space(space_id)


func exit() -> void:
	_context_close()
	_context_pending = false
	progress_indicator.clear()
	route_manager.clear_goto_route()
	location_manager.clear_markers()
	NoteManager.clear()


# ── Gestures ──────────────────────────────────────────────────────────────────

func on_pinch_held(hand: String, position: Vector3, duration: float) -> void:
	if hand == "right":
		_context_update_hold(position, duration)


func on_pinch_ended(hand: String) -> void:
	if hand == "right":
		_context_handle_end()
