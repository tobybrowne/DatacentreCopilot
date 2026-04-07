# Handles UI Panel boilerplate:
#	- SubViewport setup
#	- QuadMesh setup to render the SubViewport in 3D space
#	- Positioning and orienting the panel in front of the user
#	- Projecting hand tracker positions to the panel and sending input events to the SubViewport

class_name ViewportPanel3D
extends Node3D

@export var panel_scene: PackedScene

@export var follow_speed: float = 2.0
@export var locked_to_head: bool = false
@export var distance: float = 1.2
# Floating mode offsets (metres, world space)
@export var height_offset: float = 0.0
@export var lateral_offset: float = 0.0
# Locked-to-head screen position: (0,0) = centre, (1,1) = top-right corner of visible FOV
@export var screen_position: Vector2 = Vector2(0.0, 0.0)
# ML2 waveguide shows only a portion of what the projection matrix covers
@export var fov_scale: Vector2 = Vector2(22.8, 24.7)
@export var viewport_size: Vector2i = Vector2i(800, 800)
@export var quad_size: Vector2 = Vector2(0.4, 0.4)
@export var background_color: Color = Color(1, 1, 1, 1)
@export var touchable: bool = true


var _camera: XRCamera3D
var _viewport: SubViewport
var _mesh_instance: MeshInstance3D
var _panel: Control
var _pressing := false


func _ready() -> void:
	_camera = get_parent().get_node_or_null("XRCamera3D")
	_viewport = SubViewport.new()
	_viewport.size = viewport_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	if panel_scene:
		_panel = panel_scene.instantiate()
		_on_panel_ready(_panel)
		_viewport.add_child(_panel)

	var quad := QuadMesh.new()
	quad.size = quad_size

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.albedo_color = background_color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


# Override in subclass to wire signals or configure the panel after instantiation
func _on_panel_ready(_p: Control) -> void:
	pass


func get_panel() -> Control:
	return _panel


func _process(delta: float) -> void:
	if not _camera:
		return

	if locked_to_head:
		# uses the cameras projection matrix (given by ML2 at runtime)
		# to positions things relative to the users FOV (great for HUD stuff)
		var cam := _camera.global_transform
		var x_off: float = screen_position.x * tan(deg_to_rad(fov_scale.x)) * distance
		var y_off: float = screen_position.y * tan(deg_to_rad(fov_scale.y)) * distance
		global_position = cam.origin \
			+ cam.basis.x * x_off \
			+ cam.basis.y * y_off \
			+ cam.basis.z * (-distance)
		global_basis = cam.basis

	else:
		var cam_basis := _camera.global_transform.basis
		var cam_pos := _camera.global_position

		var forward := -cam_basis.z
		forward.y = 0.0
		if forward.length_squared() < 0.001:
			return
		forward = forward.normalized()

		var right := cam_basis.x
		right.y = 0.0
		right = right.normalized()

		var target_pos := cam_pos \
			+ forward * distance \
			+ right * lateral_offset \
			+ Vector3(0.0, height_offset, 0.0)

		target_pos = _avoid_planes(target_pos)
		global_position = global_position.lerp(target_pos, follow_speed * delta)

		var target_y := atan2(-forward.x, -forward.z)
		rotation.y = lerp_angle(rotation.y, target_y, follow_speed * delta)

	if touchable:
		_check_poke()


const PLANE_CLEARANCE := 0.15

func _avoid_planes(pos: Vector3) -> Vector3:
	var plane_manager := get_parent().get_node_or_null("PlaneManager")
	if not plane_manager:
		return pos
	for plane in plane_manager.planes_data:
		var t: Transform3D = plane["transform"]
		var local := t.affine_inverse() * pos
		if abs(local.x) > plane["width"] * 0.5 or abs(local.y) > plane["height"] * 0.5:
			continue
		if local.z < PLANE_CLEARANCE:
			pos += t.basis.z * (PLANE_CLEARANCE - local.z)
	return pos


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
