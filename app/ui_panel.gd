extends Node3D

const PanelScene = preload("res://ui_panel.tscn")

@export var follow_speed: float = 2.0
@export var distance: float = 0.8
@export var height_offset: float = -0.15

var _camera: XRCamera3D
var _viewport: SubViewport
var _mesh_instance: MeshInstance3D
var _quad_size := Vector2(0.4, 0.4)
var _pressing := false


func _ready() -> void:
	_camera = get_parent().get_node_or_null("XRCamera3D")
	_build_panel()


func _build_panel() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 800)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	var panel := PanelScene.instantiate()
	_viewport.add_child(panel)
	var toggle_btn := panel.get_node("ColorRect/ToggleButton") as Button
	toggle_btn.toggled.connect(_on_toggle)

	var quad := QuadMesh.new()
	quad.size = _quad_size

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _process(delta: float) -> void:
	if not _camera:
		return

	var cam_pos: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_transform.basis.z

	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()

	var target_pos := cam_pos + forward * distance + Vector3(0.0, height_offset, 0.0)
	global_position = global_position.lerp(target_pos, follow_speed * delta)

	var target_y := atan2(-forward.x, -forward.z)
	rotation.y = lerp_angle(rotation.y, target_y, follow_speed * delta)

	_check_poke()


func _check_poke() -> void:
	var xr_origin := get_parent() as XROrigin3D
	if not xr_origin:
		return

	var hit_pos := Vector2(-1.0, -1.0)

	for tracker_path in ["/user/hand_tracker/left", "/user/hand_tracker/right"]:
		var tracker := XRServer.get_tracker(tracker_path)
		if not tracker or not tracker is XRHandTracker:
			continue

		var ht := tracker as XRHandTracker
		# HAND_JOINT_INDEX_TIP = 10, HAND_JOINT_FLAG_POSITION_VALID = 4
		var flags := ht.get_hand_joint_flags(10)
		if not (flags & 4):
			continue

		var joint_xform := ht.get_hand_joint_transform(10)
		var tip_world := xr_origin.global_transform * joint_xform.origin
		var result := _project_to_panel(tip_world)
		if result.x >= 0.0:
			hit_pos = result
			break

	if hit_pos.x >= 0.0:
		# Send hover so buttons highlight correctly
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


# Returns viewport pixel coords if the finger tip is touching the panel face,
# or Vector2(-1, -1) if it is out of range.
func _project_to_panel(tip_world: Vector3) -> Vector2:
	var local := _mesh_instance.global_transform.affine_inverse() * tip_world
	var half_w := _quad_size.x * 0.5
	var half_h := _quad_size.y * 0.5

	# Must be within the quad's XY bounds
	if abs(local.x) > half_w or abs(local.y) > half_h:
		return Vector2(-1.0, -1.0)

	# Must be within 2 cm of the front face (positive Z faces the user)
	if local.z < -0.01 or local.z > 0.02:
		return Vector2(-1.0, -1.0)

	var uv_x := (local.x + half_w) / _quad_size.x
	var uv_y := 1.0 - (local.y + half_h) / _quad_size.y
	return Vector2(uv_x * _viewport.size.x, uv_y * _viewport.size.y)


func _on_toggle(pressed: bool) -> void:
	var panel := _viewport.get_child(0)
	var btn := panel.get_node("ColorRect/ToggleButton") as Button
	btn.text = "Right >" if pressed else "< Left"
