class_name NavigatingState
extends State

## User is navigating within a calibrated space. Space label is shown as a
## standalone 3D panel; UI panel is hidden. Right-hand pinch-hold opens the
## 3D context menu.

const _SPACE_LABEL_SCENE := preload("res://ui/standalone/space_label/space_label_3d.tscn")

var _space_label_3d: ViewportPanel3D = null


func enter(data: Dictionary) -> void:
	ui_panel.visible = false

	_space_label_3d = _SPACE_LABEL_SCENE.instantiate()
	gesture_manager.get_parent().add_child(_space_label_3d)
	location_manager.coarse_space_changed.connect(_on_coarse_space_changed)

	var space_id: String = data.get("space_id", "")
	var space := data.get("space") as Space
	if space_id.is_empty() and space:
		if not await space_manager.ensure_space_local(space):
			return
		space_id = space.id
	if not space_id.is_empty() and not data.get("pre_calibrated", false):
		location_manager.calibrate_to_space(space_id)


func exit() -> void:
	location_manager.coarse_space_changed.disconnect(_on_coarse_space_changed)
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

func _on_coarse_space_changed(coarse_id: String, active_id: String) -> void:
	var sl := _space_label_3d.get_panel() as SpaceLabel if _space_label_3d else null
	if sl:
		sl.update(coarse_id, active_id)


func on_pinch_held(hand: String, position: Vector3, duration: float) -> void:
	if hand == "right":
		_context_update_hold(position, duration)


func on_pinch_ended(hand: String) -> void:
	if hand == "right":
		_context_handle_end()
