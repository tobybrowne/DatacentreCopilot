# Handles UI Panel boilerplate:
#	- SubViewport setup
#	- QuadMesh setup to render the SubViewport in 3D space
#	- Positioning and orienting the panel in front of the user
#	- Projecting hand tracker positions to the panel and sending input events to the SubViewport

class_name ViewportPanel3D
extends Node3D

@export var use_router: bool = false
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
@export var ray_enabled: bool = true
@export var tilt_degrees: float = 0.0
@export var lazy_follow: bool = false
@export var lazy_follow_distance: float = 0.8
@export var lazy_follow_angle_degrees: float = 110.0
@export var lazy_follow_face_angle_degrees: float = 15.0
@export var lazy_follow_height_angle_degrees: float = 8.0
@export var environment_avoidance: bool = false
@export var environment_clearance: float = 0.2
@export_range(0.0, 1.0) var desktop_sim_alpha: float = 0.65
@export var corner_radius_m: float = 0.02


const _PANEL_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D viewport_tex : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 panel_size = vec2(1.0, 1.0);
uniform float corner_radius = 0.02;

void fragment() {
	vec2 p = (UV - 0.5) * panel_size;
	vec2 half_size = panel_size * 0.5;
	vec2 d = abs(p) - (half_size - corner_radius);
	float outside = length(max(d, 0.0));
	float inside = min(max(d.x, d.y), 0.0);
	float dist = outside + inside - corner_radius;
	float mask = 1.0 - smoothstep(-0.002, 0.002, dist);

	vec4 col = texture(viewport_tex, UV) * tint;
	ALBEDO = col.rgb;
	ALPHA = col.a * mask;
}
"""


var _camera: XRCamera3D
var _viewport: SubViewport
var _mesh_instance: MeshInstance3D
var _panel: Control
var _pressing := false
var _ray_pressing := {"left": false, "right": false}
var _mouse_pressing := false
var _desktop_sim := false
var _placed := false
var _stable_frames := 0
var _last_cam_pos := Vector3.ZERO
var _sliding := false
var _slide_target_pos := Vector3.ZERO
var _slide_target_y := 0.0


func _ready() -> void:
	_camera = get_parent().get_node_or_null("XRCamera3D")
	_viewport = SubViewport.new()
	_viewport.size = viewport_size
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	if use_router:
		PanelRouter.panel_changed.connect(_swap_panel)
		if not PanelRouter.current().is_empty():
			_swap_panel(PanelRouter.current(), {})
	elif panel_scene:
		_panel = panel_scene.instantiate()
		_on_panel_ready(_panel)
		_viewport.add_child(_panel)

	var quad := QuadMesh.new()
	quad.size = quad_size

	_desktop_sim = not XRMode.is_active()

	var shader := Shader.new()
	shader.code = _PANEL_SHADER_CODE
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("viewport_tex", _viewport.get_texture())
	mat.set_shader_parameter("panel_size", quad_size)
	mat.set_shader_parameter("corner_radius", corner_radius_m)
	var tint := background_color
	if _desktop_sim:
		# Rough AR feel on desktop: semi-transparent panel (dark pixels remain visible, just muted).
		tint.a *= desktop_sim_alpha
	mat.set_shader_parameter("tint", tint)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)

	# Hide until first placement so the panel isn't visible at its default scene position.
	_mesh_instance.visible = false


# Called when a new panel is loaded via the router
func _swap_panel(panel_id: String, data: Dictionary) -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
	var scene := PanelRouter.get_scene(panel_id)
	if not scene:
		return
	_panel = scene.instantiate()
	if _panel.has_signal("navigate_to"):
		_panel.navigate_to.connect(func(id: String, d: Dictionary): PanelRouter.push(id, d))
	if _panel.has_signal("close_requested"):
		_panel.close_requested.connect(PanelRouter.pop)
	_viewport.add_child(_panel)
	if _panel.has_method("init"):
		_panel.init(data)


# Override in subclass to wire signals or configure the panel after instantiation (non-router mode)
func _on_panel_ready(_p: Control) -> void:
	pass


func get_panel() -> Control:
	return _panel


func _process(delta: float) -> void:
	if not _camera or not visible:
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
		if environment_avoidance:
			target_pos = _avoid_world_mesh(cam_pos, target_pos)

		var target_y := atan2(-forward.x, -forward.z)

		if not _placed:
			# Wait for OpenXR pose to stabilise: non-zero position AND steady for several frames.
			if cam_pos.length() < 0.3:
				_stable_frames = 0
				_last_cam_pos = cam_pos
				return
			if cam_pos.distance_to(_last_cam_pos) < 0.02:
				_stable_frames += 1
			else:
				_stable_frames = 0
			_last_cam_pos = cam_pos
			if _stable_frames < 10:
				return
			global_position = target_pos
			rotation.y = target_y
			rotation.x = deg_to_rad(tilt_degrees)
			_placed = true
			_mesh_instance.visible = true
		elif not lazy_follow:
			var t: float = clamp(follow_speed * delta, 0.0, 1.0)
			global_position = global_position.lerp(target_pos, t)
			rotation.y = lerp_angle(rotation.y, target_y, t)
			rotation.x = deg_to_rad(tilt_degrees)
		else:
			var to_panel := global_position - cam_pos
			to_panel.y = 0.0
			var dist_to_panel := to_panel.length()
			var occluded := environment_avoidance and _is_occluded(cam_pos, global_position)
			if dist_to_panel > distance + lazy_follow_distance or dist_to_panel < distance * 0.75 or occluded:
				# Too far, too close, or occluded — slide to optimal spot in front.
				_slide_target_pos = target_pos
				_slide_target_y = target_y
				_sliding = true
			elif dist_to_panel > 0.01:
				var to_panel_dir := to_panel / dist_to_panel
				var view_dot: float = clamp(forward.dot(to_panel_dir), -1.0, 1.0)
				var view_angle: float = acos(view_dot)
				var face_y: float = atan2(cam_pos.x - global_position.x, cam_pos.z - global_position.z)
				var target_height: float = cam_pos.y + height_offset
				var height_angle: float = abs(atan2(global_position.y - target_height, dist_to_panel))
				if view_angle > deg_to_rad(lazy_follow_angle_degrees):
					# Look-away — full reposition into view.
					_slide_target_pos = target_pos
					_slide_target_y = target_y
					_sliding = true
				elif abs(wrapf(face_y - rotation.y, -PI, PI)) > deg_to_rad(lazy_follow_face_angle_degrees):
					# Face-tracking — rotate in place to point at the user's position.
					_slide_target_pos = global_position
					_slide_target_y = face_y
					_sliding = true
				elif height_angle > deg_to_rad(lazy_follow_height_angle_degrees):
					# Height tracking — slide Y only to follow the user up/down.
					_slide_target_pos = Vector3(global_position.x, target_height, global_position.z)
					_slide_target_y = rotation.y
					_sliding = true

			if _sliding:
				var t: float = clamp(follow_speed * delta, 0.0, 1.0)
				global_position = global_position.lerp(_slide_target_pos, t)
				rotation.y = lerp_angle(rotation.y, _slide_target_y, t)
				rotation.x = deg_to_rad(tilt_degrees)
				if global_position.distance_to(_slide_target_pos) < 0.005 and abs(wrapf(_slide_target_y - rotation.y, -PI, PI)) < 0.01:
					global_position = _slide_target_pos
					rotation.y = _slide_target_y
					_sliding = false

	if touchable:
		_check_poke()
	if ray_enabled:
		_check_ray()
		if _desktop_sim:
			_check_mouse_ray()


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


func _is_occluded(from_pos: Vector3, to_pos: Vector3) -> bool:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from_pos, to_pos)
	query.collision_mask = WorldMeshManager.COLLISION_LAYER
	return not space.intersect_ray(query).is_empty()


func _avoid_world_mesh(from_pos: Vector3, target_pos: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(from_pos, target_pos)
	query.collision_mask = WorldMeshManager.COLLISION_LAYER
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return target_pos
	var dir := (target_pos - from_pos).normalized()
	var pulled := (hit["position"] as Vector3) - dir * environment_clearance
	# Don't pull the panel behind the camera.
	if (pulled - from_pos).dot(dir) < 0.0:
		return from_pos
	return pulled


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
			var touch := InputEventScreenTouch.new()
			touch.position = hit_pos
			touch.pressed = true
			touch.index = 0
			_viewport.push_input(touch)
	elif _pressing:
		_pressing = false
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		_viewport.push_input(release)
		var touch_up := InputEventScreenTouch.new()
		touch_up.pressed = false
		touch_up.index = 0
		_viewport.push_input(touch_up)


func _check_mouse_ray() -> void:
	if not _camera:
		return
	var origin := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var hw := _ray_world_hit(origin, dir)
	var uv := _world_hit_to_panel_uv(hw) if hw != Vector3.INF else Vector2(-1.0, -1.0)

	if uv.x < 0.0:
		if _mouse_pressing:
			_mouse_pressing = false
			var release := InputEventMouseButton.new()
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			_viewport.push_input(release)
		return

	var motion := InputEventMouseMotion.new()
	motion.position = uv
	_viewport.push_input(motion)

	var pressed := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if pressed and not _mouse_pressing:
		_mouse_pressing = true
		var press := InputEventMouseButton.new()
		press.position = uv
		press.button_index = MOUSE_BUTTON_LEFT
		press.pressed = true
		_viewport.push_input(press)
	elif not pressed and _mouse_pressing:
		_mouse_pressing = false
		var release := InputEventMouseButton.new()
		release.position = uv
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		_viewport.push_input(release)


func _check_ray() -> void:
	var gm := get_parent().get_node_or_null("GestureManager") as GestureManager
	if not gm:
		return

	for hand in ["left", "right"]:
		if not gm.ray_active[hand]:
			_release_ray(hand)
			continue

		var hw := _ray_world_hit(gm.ray_origins[hand], gm.ray_directions[hand])
		if hw == Vector3.INF:
			_release_ray(hand)
			continue

		var uv := _world_hit_to_panel_uv(hw)
		if uv.x < 0.0:
			_release_ray(hand)
			continue

		gm.set_hit_point(hand, hw)
		gm.claim_ui(hand)

		var motion := InputEventMouseMotion.new()
		motion.position = uv
		_viewport.push_input(motion)

		if gm.is_ray_pinching(hand) and not _ray_pressing[hand]:
			_ray_pressing[hand] = true
			var press := InputEventMouseButton.new()
			press.position = uv
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			_viewport.push_input(press)
			var touch := InputEventScreenTouch.new()
			touch.position = uv
			touch.pressed = true
			touch.index = 0
			_viewport.push_input(touch)
		elif not gm.is_ray_pinching(hand) and _ray_pressing[hand]:
			_ray_pressing[hand] = false
			var release := InputEventMouseButton.new()
			release.position = uv
			release.button_index = MOUSE_BUTTON_LEFT
			release.pressed = false
			_viewport.push_input(release)
			var touch_up := InputEventScreenTouch.new()
			touch_up.position = uv
			touch_up.pressed = false
			touch_up.index = 0
			_viewport.push_input(touch_up)


func _release_ray(hand: String) -> void:
	if _ray_pressing[hand]:
		_ray_pressing[hand] = false
		var release := InputEventMouseButton.new()
		release.button_index = MOUSE_BUTTON_LEFT
		release.pressed = false
		_viewport.push_input(release)
		var touch_up := InputEventScreenTouch.new()
		touch_up.pressed = false
		touch_up.index = 0
		_viewport.push_input(touch_up)


func _ray_world_hit(ray_origin: Vector3, ray_dir: Vector3) -> Vector3:
	var panel_normal := _mesh_instance.global_transform.basis.z
	var panel_center := _mesh_instance.global_position
	var denom := ray_dir.dot(panel_normal)
	if abs(denom) < 0.001:
		return Vector3.INF
	var t := (panel_center - ray_origin).dot(panel_normal) / denom
	if t < 0.0:
		return Vector3.INF
	return ray_origin + ray_dir * t


func _world_hit_to_panel_uv(hit_world: Vector3) -> Vector2:
	var local := _mesh_instance.global_transform.affine_inverse() * hit_world
	var half_w := quad_size.x * 0.5
	var half_h := quad_size.y * 0.5
	if abs(local.x) > half_w or abs(local.y) > half_h:
		return Vector2(-1.0, -1.0)
	var uv_x := (local.x + half_w) / quad_size.x
	var uv_y := 1.0 - (local.y + half_h) / quad_size.y
	var px := uv_x * _viewport.size.x
	var py := uv_y * _viewport.size.y
	if not _hit_inside_content(px, py):
		return Vector2(-1.0, -1.0)
	return Vector2(px, py)


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
	var px := uv_x * _viewport.size.x
	var py := uv_y * _viewport.size.y
	if not _hit_inside_content(px, py):
		return Vector2(-1.0, -1.0)
	return Vector2(px, py)


# Only accept hits within the current Control's rect, so transparent regions
# of the SubViewport (common when the Control is smaller than the viewport)
# don't block rays or poke input.
func _hit_inside_content(px: float, py: float) -> bool:
	if not _panel:
		return false
	var r := _panel.get_rect()
	return px >= r.position.x and py >= r.position.y \
		and px <= r.position.x + r.size.x and py <= r.position.y + r.size.y
