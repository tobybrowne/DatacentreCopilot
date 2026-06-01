class_name WristPanel3D
extends ViewportPanel3D

signal home_requested

@export var tracked_hand: String = "left"

const _PALM_FACE_THRESHOLD := 0.80
const _PALM_JOINT := 0
const _WRIST_JOINT := 1
const _WRIST_NORMAL_OFFSET := 0.02  # metres above palm surface

const _HOLD_TIME := 1.5
const _HOLD_Z_FRONT := -0.02  # finger must breach this depth to start hold
const _HOLD_Z_BACK := 0.15    # finger stays "in" until it retreats past front

var _hold_timer := 0.0


func _ready() -> void:
	world_anchored = true
	panel_scene = preload("res://ui/standalone/wrist_controls/wrist_controls.tscn")
	viewport_size = Vector2i(480, 240)
	quad_size = Vector2(0.12, 0.06)
	corner_radius_m = 0.008
	touchable = true
	ray_enabled = false
	super._ready()
	visible = false
	_mesh_instance.visible = false


func _on_panel_ready(p: Control) -> void:
	p.home_requested.connect(func(): home_requested.emit())


func _process(delta: float) -> void:
	var xr_origin := get_parent() as XROrigin3D
	var camera := get_viewport().get_camera_3d()
	if not xr_origin or not camera:
		_set_visible(false)
		super._process(delta)
		return

	var tracker := XRServer.get_tracker("/user/hand_tracker/" + tracked_hand)
	if not tracker or not tracker is XRHandTracker:
		_set_visible(false)
		super._process(delta)
		return
	var ht := tracker as XRHandTracker

	if not (ht.get_hand_joint_flags(_PALM_JOINT) & 4) or not (ht.get_hand_joint_flags(_WRIST_JOINT) & 4):
		_set_visible(false)
		super._process(delta)
		return

	var xr_tf := xr_origin.global_transform
	var palm_xform := xr_tf * ht.get_hand_joint_transform(_PALM_JOINT)

	var palm_normal := palm_xform.basis.z
	var facing := palm_normal.dot((camera.global_position - palm_xform.origin).normalized())

	if facing > _PALM_FACE_THRESHOLD:
		global_position = palm_xform.origin + palm_normal * _WRIST_NORMAL_OFFSET
		_set_visible(true)
	else:
		_set_visible(false)

	super._process(delta)

	if visible and _panel:
		var other_hand := "right" if tracked_hand == "left" else "left"
		var tip := _get_index_tip(other_hand)
		if tip != Vector3.INF and _finger_over_panel(tip):
			_hold_timer += delta
		else:
			_hold_timer = 0.0
		_panel.set_hold_progress(_hold_timer / _HOLD_TIME)


const _HOLD_RADIUS := 0.03  # metres - must be within 3cm of panel centre

func _finger_over_panel(tip_world: Vector3) -> bool:
	var local := _mesh_instance.global_transform.affine_inverse() * tip_world
	if local.z < _HOLD_Z_FRONT or local.z > _HOLD_Z_BACK:
		return false
	return Vector2(local.x, local.y).length() <= _HOLD_RADIUS




func _set_visible(v: bool) -> void:
	if not v and visible and _panel:
		_hold_timer = 0.0
		_panel.reset()
	visible = v
	_mesh_instance.visible = v
