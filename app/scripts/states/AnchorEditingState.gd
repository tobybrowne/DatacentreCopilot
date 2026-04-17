class_name AnchorEditingState
extends State

## Right-hand pinch creates/deletes anchors, with a progress ring while held.
## Blue ring = create at pinch position. Red ring = delete nearest existing.

const _DELETE_RADIUS := 0.10
const _CREATE_COLOR  := Color(0.2, 0.8, 1.0)
const _DELETE_COLOR  := Color(1.0, 0.3, 0.2)

var _mode   := ""          # "create" | "delete"
var _target: Anchor = null


func enter(data: Dictionary) -> void:
	ui_panel.visible = false
	var space := data.get("space") as Space
	if space:
		_load_space(space)


func exit() -> void:
	anchor_manager.clear_markers()
	progress_indicator.clear()
	_mode = ""
	_target = null


func _load_space(space: Space) -> void:
	if not await location_manager.ensure_space_local(space):
		return
	await location_manager.localize_to_space(space.id)
	for anchor in location_manager.get_space_anchors(space.id):
		anchor_manager.load_anchor(anchor.ml2_id)


# ── Gestures ──────────────────────────────────────────────────────────────────

func on_pinch_started(hand: String, position: Vector3) -> void:
	if hand != "right":
		return
	var near: Anchor = anchor_manager.get_anchor_near(position, _DELETE_RADIUS)
	_mode   = "delete" if near != null else "create"
	_target = near


func on_pinch_held(hand: String, position: Vector3, duration: float) -> void:
	if hand != "right":
		return
	var color := _CREATE_COLOR if _mode == "create" else _DELETE_COLOR
	progress_indicator.update(position, minf(duration / gesture_manager.hold_time, 1.0), color)


func on_pinch_completed(hand: String, position: Vector3) -> void:
	if hand != "right":
		return
	progress_indicator.clear()
	if _mode == "create":
		anchor_manager.place_anchor(Transform3D(Basis.IDENTITY, position))
	elif _target:
		anchor_manager.remove_anchor(_target)
	_mode = ""
	_target = null


func on_pinch_ended(hand: String) -> void:
	if hand != "right":
		return
	progress_indicator.clear()
	_mode = ""
	_target = null
