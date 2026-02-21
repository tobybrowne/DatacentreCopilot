class_name HandStepControl3D
extends Node3D

@export var viewport_size: Vector2i = Vector2i(300, 120)
@export var quad_size: Vector2 = Vector2(0.12, 0.048)
@export var finger_offset: float = 0.15

signal prev_requested
signal next_requested

const PanelScene = preload("res://hand_step_control.tscn")

var _viewport: SubViewport
var _mesh_instance: MeshInstance3D
var _panel: Control
var _pressing := false


func _ready() -> void:
	_viewport = SubViewport.new()
	_viewport.size = viewport_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_panel = PanelScene.instantiate()
	_panel.prev_requested.connect(prev_requested.emit)
	_panel.next_requested.connect(next_requested.emit)
	_viewport.add_child(_panel)

	var quad := QuadMesh.new()
	quad.size = quad_size

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _process(_delta: float) -> void:
	_update_wrist_position()
	_check_poke()


func _update_wrist_position() -> void:
	var xr_origin := get_parent() as XROrigin3D
	if not xr_origin:
		return

	var tracker := XRServer.get_tracker("/user/hand_tracker/left")
	if not tracker or not tracker is XRHandTracker:
		return

	var ht := tracker as XRHandTracker
	# HAND_JOINT_PALM = 0, HAND_JOINT_FLAG_POSITION_VALID = 4
	var flags := ht.get_hand_joint_flags(0)
	if not (flags & 4):
		return

	var palm_xform := ht.get_hand_joint_transform(0)
	var world_xform := xr_origin.global_transform * palm_xform
	# Shift along the palm's local +y (towards fingertips)
	world_xform.origin += world_xform.basis.y * finger_offset
	global_transform = world_xform


func _check_poke() -> void:
	var xr_origin := get_parent() as XROrigin3D
	if not xr_origin:
		return

	var hit_pos := Vector2(-1.0, -1.0)

	var tracker := XRServer.get_tracker("/user/hand_tracker/right")
	if tracker and tracker is XRHandTracker:
		var ht := tracker as XRHandTracker
		# HAND_JOINT_INDEX_TIP = 10, HAND_JOINT_FLAG_POSITION_VALID = 4
		var flags := ht.get_hand_joint_flags(10)
		if flags & 4:
			var joint_xform := ht.get_hand_joint_transform(10)
			var tip_world := xr_origin.global_transform * joint_xform.origin
			hit_pos = _project_to_panel(tip_world)

	if hit_pos.x >= 0.0:
		var motion := InputEventMouseMotion.new()
		motion.position = hit_pos
		_viewport.push_input(motion)

		if not _pressing:
			_pressing = true
			var press := InputEventMouseButton.new()
			press.position = hit_pos
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			_viewport.push_input(press)
	elif _pressing:
		_pressing = false
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		_viewport.push_input(release)


func _project_to_panel(tip_world: Vector3) -> Vector2:
	var local := _mesh_instance.global_transform.affine_inverse() * tip_world
	var half_w := quad_size.x * 0.5
	var half_h := quad_size.y * 0.5

	if abs(local.x) > half_w or abs(local.y) > half_h:
		return Vector2(-1.0, -1.0)

	if local.z < -0.01 or local.z > 0.02:
		return Vector2(-1.0, -1.0)

	var uv_x := (local.x + half_w) / quad_size.x
	var uv_y := 1.0 - (local.y + half_h) / quad_size.y
	return Vector2(uv_x * _viewport.size.x, uv_y * _viewport.size.y)
