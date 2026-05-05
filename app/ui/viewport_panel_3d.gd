# Handles UI Panel boilerplate:
#	- SubViewport setup
#	- QuadMesh setup to render the SubViewport in 3D space
#	- Positioning and orienting the panel in front of the user
#	- Projecting hand tracker positions to the panel and sending input events to the SubViewport

class_name ViewportPanel3D
extends Node3D

@export var use_router: bool = false
@export var panel_scene: PackedScene

# When true, the panel stays at its world position and only faces the camera.
# Used for menus pinned to a pinch point.
@export var world_anchored: bool = false

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
# Local offset applied to the quad mesh (relative to this Node3D's origin).
# Lets scenes add world-anchored decorations at the root (e.g. a pinch dot)
# with the visible panel hanging below.
@export var mesh_offset: Vector3 = Vector3.ZERO
@export var pinnable: bool = false
# When false, world_anchored panels face the camera once on spawn then stay put.
@export var track_camera: bool = true
# When true, snaps the panel's Y to camera height on the first frame.
@export var eye_level: bool = false


const _PANEL_SHADER_CODE := """
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_opaque;

uniform sampler2D viewport_tex : source_color, filter_linear;
uniform vec4 tint : source_color = vec4(1.0);
uniform vec2 panel_size = vec2(1.0, 1.0);
uniform float corner_radius = 0.02;
uniform float content_ratio = 1.0;

void fragment() {
	vec2 p = (UV - 0.5) * panel_size;
	vec2 half_size = panel_size * 0.5;
	vec2 d = abs(p) - (half_size - corner_radius);
	float outside = length(max(d, 0.0));
	float inside = min(max(d.x, d.y), 0.0);
	float dist = outside + inside - corner_radius;
	float mask = 1.0 - smoothstep(-0.002, 0.002, dist);

	vec4 col = texture(viewport_tex, vec2(UV.x, clamp(UV.y * content_ratio, 0.0, 1.0))) * tint;
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
var _pinned := false
var _camera_faced := false
var _eye_leveled := false
var _pin_bg: ColorRect = null
var _pin_strip: HBoxContainer = null
var _pin_button: Button = null
var _pin_icon: TextureRect = null
var _dragging := false
var _drag_offset := Vector3.ZERO
var _drag_depth := 0.0
var _drag_using_ray := false
var _drag_ray_origin_prev := Vector3.ZERO
var _drag_hand := ""
var _poke_hand := ""
var _audio_player: AudioStreamPlayer
var _press_debounce := 0.0
var _initial_quad_h: float
var _last_panel_h := -1.0
var _panel_height_px: float
var _ray_prev_uv := {"left": Vector2(-1.0, -1.0), "right": Vector2(-1.0, -1.0)}
var _ray_press_start_uv := {"left": Vector2.INF, "right": Vector2.INF}
var _ray_scroll_mode := {"left": false, "right": false}
var _poke_prev_uv := Vector2(-1.0, -1.0)
var _poke_press_start_uv := Vector2.INF
var _poke_scroll_mode := false

const _PRESS_DEBOUNCE_TIME := 0.5
const _SCROLL_DRAG_THRESHOLD_PX := 20.0
const _SCROLL_SPEED := 0.01
const _RAY_SNAP_RADIUS_PX := 80.0   # attraction kicks in within this pixel radius
const _RAY_SNAP_STRENGTH := 0.65    # 0 = no pull, 1 = hard snap to centre
const _RAY_HYSTERESIS_M := 0.015    # metres of extra panel margin while pressing

const _PIN_STRIP_PX := 80


static func _create_pop_stream() -> AudioStreamWAV:
	var sample_rate := 22050
	var num_samples := sample_rate * 25 / 1000  # 25 ms
	var data := PackedByteArray()
	data.resize(num_samples * 2)
	for i in num_samples:
		var t := float(i) / sample_rate
		var v := int(sin(TAU * 1000.0 * t) * exp(-t * 80.0) * 32767.0)
		data[i * 2]     = v & 0xFF
		data[i * 2 + 1] = (v >> 8) & 0xFF
	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = sample_rate
	stream.stereo = false
	return stream


func _ready() -> void:
	_audio_player = AudioStreamPlayer.new()
	_audio_player.stream = _create_pop_stream()
	_audio_player.volume_db = -6.0
	add_child(_audio_player)

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
	_mesh_instance.position = mesh_offset
	add_child(_mesh_instance)
	_initial_quad_h = quad_size.y
	_panel_height_px = float(viewport_size.y)

	if world_anchored:
		# World-anchored panels are positioned by the caller — show immediately.
		_placed = true
		_mesh_instance.visible = true
	else:
		# Hide until first placement so the panel isn't visible at its default scene position.
		_mesh_instance.visible = false

	if pinnable:
		_setup_pin_button()


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
	if _pin_strip:
		_pin_bg.move_to_front()
		_pin_strip.move_to_front()


# Override in subclass to wire signals or configure the panel after instantiation (non-router mode)
func _on_panel_ready(_p: Control) -> void:
	pass


func _setup_pin_button() -> void:
	_pin_bg = ColorRect.new()
	_pin_bg.color = Color(0.1, 0.1, 0.15, 0.85)
	_pin_bg.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_pin_bg.custom_minimum_size = Vector2(0, _PIN_STRIP_PX)
	_pin_bg.offset_top = -_PIN_STRIP_PX
	_pin_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_pin_bg)

	_pin_strip = HBoxContainer.new()
	_pin_strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_pin_strip.custom_minimum_size = Vector2(0, _PIN_STRIP_PX)
	_pin_strip.offset_top = -_PIN_STRIP_PX
	_pin_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_strip.add_theme_constant_override("separation", 0)

	var drag_wrapper := Control.new()
	drag_wrapper.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drag_wrapper.custom_minimum_size = Vector2(0, _PIN_STRIP_PX)
	drag_wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var drag_label := Label.new()
	drag_label.text = "⠿"
	drag_label.add_theme_font_size_override("font_size", 38)
	drag_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	drag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drag_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	drag_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	drag_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drag_label.rotation_degrees = 90.0
	drag_label.resized.connect(func(): drag_label.pivot_offset = drag_label.size / 2.0)
	drag_wrapper.add_child(drag_label)
	_pin_strip.add_child(drag_wrapper)

	_pin_button = Button.new()
	_pin_button.text = ""
	_pin_button.custom_minimum_size = Vector2(_PIN_STRIP_PX, _PIN_STRIP_PX)
	_pin_button.pressed.connect(_on_pin_pressed)

	var _icon_center := CenterContainer.new()
	_icon_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pin_button.add_child(_icon_center)

	_pin_icon = TextureRect.new()
	_pin_icon.texture = load("res://ui/icon_thumbtack_outline.svg")
	_pin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_pin_icon.custom_minimum_size = Vector2(36, 36)
	_pin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_icon_center.add_child(_pin_icon)

	_pin_strip.add_child(_pin_button)

	_viewport.add_child(_pin_strip)


func _on_pin_pressed() -> void:
	_pinned = not _pinned
	_dragging = false
	_pin_icon.texture = load("res://ui/icon_thumbtack_filled.svg") if _pinned else load("res://ui/icon_thumbtack_outline.svg")


func _get_index_tip(hand: String) -> Vector3:
	var xr_origin := get_parent() as XROrigin3D
	if not xr_origin or hand.is_empty():
		return Vector3.INF
	var tracker := XRServer.get_tracker("/user/hand_tracker/" + hand)
	if not tracker or not tracker is XRHandTracker:
		return Vector3.INF
	var ht := tracker as XRHandTracker
	var flags := ht.get_hand_joint_flags(10)
	if not (flags & 4):
		return Vector3.INF
	return xr_origin.global_transform * ht.get_hand_joint_transform(10).origin


func get_panel() -> Control:
	return _panel


func _process(delta: float) -> void:
	if not _camera or not visible:
		return
	if _press_debounce > 0.0:
		_press_debounce -= delta

	_sync_quad_to_panel()

	if _dragging:
		if _drag_using_ray:
			var gm := get_parent().get_node_or_null("GestureManager") as GestureManager
			if gm and gm.ray_active[_drag_hand]:
				var ray_origin: Vector3 = gm.ray_origins[_drag_hand]
				var ray_dir: Vector3 = gm.ray_directions[_drag_hand]
				var cam_forward := -_camera.global_transform.basis.z
				_drag_depth = maxf(0.3, _drag_depth - (_drag_ray_origin_prev - ray_origin).dot(cam_forward))
				_drag_ray_origin_prev = ray_origin
				global_position = ray_origin + ray_dir * _drag_depth + _drag_offset
		else:
			var tip := _get_index_tip(_drag_hand)
			if tip != Vector3.INF:
				global_position = tip + _drag_offset
		if _camera and global_position.distance_to(_camera.global_position) > 0.01:
			var to_cam := _camera.global_position - global_position
			to_cam.y = 0.0
			if to_cam.length_squared() > 0.001:
				rotation.y = atan2(to_cam.x, to_cam.z)
				rotation.x = deg_to_rad(tilt_degrees)
	elif not _pinned:
		if world_anchored:
			if eye_level and not _eye_leveled:
				global_position.y = _camera.global_position.y
				_eye_leveled = true
			# look_at points -Z toward camera; quads face +Z so flip 180°
			var far_enough := global_position.distance_to(_camera.global_position) > 0.01
			if far_enough and (track_camera or not _camera_faced):
				look_at(_camera.global_position, Vector3.UP)
				rotate_object_local(Vector3.UP, PI)
				_camera_faced = true
		elif locked_to_head:
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


func _sync_quad_to_panel() -> void:
	if not _panel or not _placed:
		return
	var ph := _panel.size.y
	if ph <= 1.0 or is_equal_approx(ph, _last_panel_h):
		return
	_last_panel_h = ph
	_panel_height_px = ph
	var new_vp_h := maxi(int(ceil(ph)), viewport_size.y)
	_viewport.size = Vector2i(viewport_size.x, new_vp_h)
	var ratio := ph / float(viewport_size.y)
	var new_h := _initial_quad_h * ratio
	quad_size.y = new_h
	(_mesh_instance.mesh as QuadMesh).size = Vector2(quad_size.x, new_h)
	_mesh_instance.position.y = mesh_offset.y + (_initial_quad_h - new_h) * 0.5
	var mat := _mesh_instance.material_override as ShaderMaterial
	mat.set_shader_parameter("panel_size", Vector2(quad_size.x, new_h))
	mat.set_shader_parameter("content_ratio", ph / float(new_vp_h))


func _unhandled_input(event: InputEvent) -> void:
	if not _desktop_sim or not _camera or not _placed:
		return
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index not in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_LEFT, MOUSE_BUTTON_WHEEL_RIGHT]:
		return
	var hw := _ray_world_hit(_camera.global_position, -_camera.global_transform.basis.z)
	if hw == Vector3.INF:
		return
	var uv := _world_hit_to_panel_uv(hw)
	if uv.x < 0.0:
		return
	var fwd := InputEventMouseButton.new()
	fwd.position = uv
	fwd.button_index = mb.button_index
	fwd.pressed = mb.pressed
	fwd.factor = mb.factor
	_viewport.push_input(fwd)
	get_viewport().set_input_as_handled()


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
			_poke_hand = "left" if "left" in tracker_path else "right"
			break

	if hit_pos.x < 0.0:
		_poke_hand = ""

	var in_drag_area := pinnable \
		and hit_pos.x >= 0.0 \
		and hit_pos.y >= viewport_size.y - _PIN_STRIP_PX \
		and hit_pos.x < viewport_size.x - 200.0

	if hit_pos.x >= 0.0:
		if in_drag_area:
			if not _pressing:
				_pressing = true
				_dragging = true
				_drag_using_ray = false
				_pinned = false
				_drag_hand = _poke_hand
				var tip := _get_index_tip(_drag_hand)
				if tip != Vector3.INF:
					_drag_offset = global_position - tip
		else:
			var motion := InputEventMouseMotion.new()
			motion.position = hit_pos
			_viewport.push_input(motion)

			if not _pressing and _press_debounce <= 0.0:
				_pressing = true
				_press_debounce = _PRESS_DEBOUNCE_TIME
				_poke_press_start_uv = hit_pos
				_poke_scroll_mode = false
			elif _pressing:
				if not _poke_scroll_mode and abs(hit_pos.y - _poke_press_start_uv.y) > _SCROLL_DRAG_THRESHOLD_PX:
					_poke_scroll_mode = true
				if _poke_scroll_mode and _poke_prev_uv.x >= 0.0:
					var pan := InputEventPanGesture.new()
					pan.position = hit_pos
					pan.delta = Vector2(0.0, -(hit_pos.y - _poke_prev_uv.y) * _SCROLL_SPEED)
					_viewport.push_input(pan)
		_poke_prev_uv = hit_pos
	elif _pressing:
		_pressing = false
		_press_debounce = _PRESS_DEBOUNCE_TIME
		_poke_prev_uv = Vector2(-1.0, -1.0)
		if _dragging:
			_dragging = false
			_pinned = true
			if _pin_button:
				_pin_icon.texture = load("res://ui/icon_thumbtack_filled.svg")
		elif _poke_scroll_mode:
			_poke_scroll_mode = false
		else:
			_audio_player.play()
			var press := InputEventMouseButton.new()
			press.position = _poke_press_start_uv
			press.button_index = MOUSE_BUTTON_LEFT
			press.pressed = true
			_viewport.push_input(press)
			var touch := InputEventScreenTouch.new()
			touch.position = _poke_press_start_uv
			touch.pressed = true
			touch.index = 0
			_viewport.push_input(touch)
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
		if _dragging and _drag_hand == hand:
			if not gm.ray_active[hand] or not gm.is_ray_pinching(hand):
				_ray_pressing[hand] = false
				_dragging = false
				_pinned = true
				if _pin_button:
					_pin_icon.texture = load("res://ui/icon_thumbtack_filled.svg")
			continue

		if not gm.ray_active[hand]:
			_release_ray(hand)
			continue

		var hw := _ray_world_hit(gm.ray_origins[hand], gm.ray_directions[hand])
		if hw == Vector3.INF:
			_release_ray(hand)
			continue

		var expand := _RAY_HYSTERESIS_M if _ray_pressing[hand] else 0.0
		var uv := _world_hit_to_panel_uv(hw, expand)
		if uv.x < 0.0:
			_release_ray(hand)
			continue

		var raw_uv := uv
		uv = _snap_uv_to_buttons(uv) if not _ray_scroll_mode[hand] else uv

		gm.set_hit_point(hand, hw)
		gm.claim_ui(hand)

		var in_drag_area := pinnable \
			and uv.y >= viewport_size.y - _PIN_STRIP_PX \
			and uv.x < viewport_size.x - 200.0

		if in_drag_area:
			if gm.is_ray_pinching(hand) and not _ray_pressing[hand]:
				_ray_pressing[hand] = true
				_dragging = true
				_drag_using_ray = true
				_pinned = false
				_drag_hand = hand
				_drag_depth = (hw - gm.ray_origins[hand]).length()
				_drag_offset = global_position - hw
				_drag_ray_origin_prev = gm.ray_origins[hand]
			elif not gm.is_ray_pinching(hand) and _ray_pressing[hand]:
				_ray_pressing[hand] = false
				if _dragging and _drag_hand == hand:
					_dragging = false
					_pinned = true
					if _pin_button:
						_pin_icon.texture = load("res://ui/icon_thumbtack_filled.svg")
		else:
			var motion := InputEventMouseMotion.new()
			motion.position = uv
			_viewport.push_input(motion)

			if _ray_pressing[hand]:
				if not _ray_scroll_mode[hand] and abs(raw_uv.y - _ray_press_start_uv[hand].y) > _SCROLL_DRAG_THRESHOLD_PX:
					_ray_scroll_mode[hand] = true
				if _ray_scroll_mode[hand] and _ray_prev_uv[hand].x >= 0.0:
					var pan := InputEventPanGesture.new()
					pan.position = raw_uv
					pan.delta = Vector2(0.0, -(raw_uv.y - _ray_prev_uv[hand].y) * _SCROLL_SPEED)
					_viewport.push_input(pan)

			if gm.is_ray_pinching(hand) and not _ray_pressing[hand] and _press_debounce <= 0.0:
				_ray_pressing[hand] = true
				_press_debounce = _PRESS_DEBOUNCE_TIME
				_ray_press_start_uv[hand] = raw_uv
				_ray_scroll_mode[hand] = false
			elif not gm.is_ray_pinching(hand) and _ray_pressing[hand]:
				_ray_pressing[hand] = false
				if _ray_scroll_mode[hand]:
					_ray_scroll_mode[hand] = false
				else:
					_audio_player.play()
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

			_ray_prev_uv[hand] = raw_uv


func _release_ray(hand: String) -> void:
	if _ray_pressing[hand]:
		_ray_pressing[hand] = false
		_ray_scroll_mode[hand] = false
		_ray_prev_uv[hand] = Vector2(-1.0, -1.0)
		_press_debounce = _PRESS_DEBOUNCE_TIME
		if _dragging and _drag_hand == hand:
			_dragging = false
			_pinned = true
			if _pin_button:
				_pin_icon.texture = load("res://ui/icon_thumbtack_filled.svg")


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


func _world_hit_to_panel_uv(hit_world: Vector3, expand: float = 0.0) -> Vector2:
	var local := _mesh_instance.global_transform.affine_inverse() * hit_world
	var half_w := quad_size.x * 0.5
	var half_h := quad_size.y * 0.5
	if abs(local.x) > half_w + expand or abs(local.y) > half_h + expand:
		return Vector2(-1.0, -1.0)
	var uv_x := (local.x + half_w) / quad_size.x
	var uv_y := 1.0 - (local.y + half_h) / quad_size.y
	var px := clampf(uv_x * _viewport.size.x, 0.0, float(_viewport.size.x - 1))
	var py := clampf(uv_y * _panel_height_px, 0.0, _panel_height_px - 1.0)
	if expand == 0.0 and not _hit_inside_content(px, py):
		return Vector2(-1.0, -1.0)
	return Vector2(px, py)


func _snap_uv_to_buttons(uv: Vector2) -> Vector2:
	if not _panel:
		return uv
	var centers := _collect_button_centers(_panel)
	var best_dist := _RAY_SNAP_RADIUS_PX
	var best := Vector2.INF
	for c in centers:
		var d := uv.distance_to(c)
		if d < best_dist:
			best_dist = d
			best = c
	if best == Vector2.INF:
		return uv
	var t := (1.0 - best_dist / _RAY_SNAP_RADIUS_PX) * _RAY_SNAP_STRENGTH
	return uv.lerp(best, t)


func _collect_button_centers(node: Control) -> Array[Vector2]:
	var result: Array[Vector2] = []
	if not node.is_visible_in_tree():
		return result
	if node is BaseButton and not (node as BaseButton).disabled:
		result.append(node.get_global_rect().get_center())
	for child in node.get_children():
		if child is Control:
			result.append_array(_collect_button_centers(child as Control))
	return result


func _project_to_panel(tip_world: Vector3) -> Vector2:
	var local := _mesh_instance.global_transform.affine_inverse() * tip_world
	var half_w := quad_size.x * 0.5
	var half_h := quad_size.y * 0.5

	if abs(local.x) > half_w or abs(local.y) > half_h:
		return Vector2(-1.0, -1.0)

	if local.z < -0.01 or local.z > 0.15:
		return Vector2(-1.0, -1.0)

	var uv_x := (local.x + half_w) / quad_size.x
	var uv_y := 1.0 - (local.y + half_h) / quad_size.y
	var px := uv_x * _viewport.size.x
	var py := uv_y * _panel_height_px
	if not _hit_inside_content(px, py):
		return Vector2(-1.0, -1.0)
	return Vector2(px, py)


# Only accept hits within the current Control's rect, so transparent regions
# of the SubViewport (common when the Control is smaller than the viewport)
# don't block rays or poke input.
func _hit_inside_content(px: float, py: float) -> bool:
	if pinnable and py >= viewport_size.y - _PIN_STRIP_PX:
		return px >= 0.0 and px <= float(viewport_size.x)
	if not _panel:
		return false
	var r := _panel.get_rect()
	return px >= r.position.x and py >= r.position.y \
		and px <= r.position.x + r.size.x and py <= r.position.y + r.size.y
