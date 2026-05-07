# Gesture manager checks hand trackers for certain events
# when detected, it emits signals with relevant data for other nodes to react to
#
# Also owns the hand ray: smoothed ray from the palm, with line + reticle visuals.
# Consumers (e.g. ViewportPanel3D) call set_hit_point() each frame when they detect
# a hit, which positions the reticle. Ray data is available via ray_origin,
# ray_direction, ray_is_active, and is_ray_pinching().

class_name GestureManager
extends Node

@export var pinch_threshold: float = 0.01
@export var hold_time: float = 3.0
@export var ray_smooth_speed: float = 18.0
@export var ray_back_offset: float = 0.12
@export var shoulder_blend: float = 0.5
@export var shoulder_side: float = 0.2
@export var shoulder_drop: float = 0.2

# signals emitted
signal pinch_started(hand: String, position: Vector3)
signal pinch_ended(hand: String)
signal pinch_held(hand: String, position: Vector3, duration: float)
signal pinch_completed(hand: String, position: Vector3)

# Home gesture: thumbs up (thumb tip above wrist, all fingers curled)
signal home_gesture_held(hand: String, position: Vector3, duration: float)
signal home_gesture_completed(hand: String)
signal home_gesture_ended(hand: String)

const _TRACKERS := {
	"left": "/user/hand_tracker/left",
	"right": "/user/hand_tracker/right",
}

var _pinching := {"left": false, "right": false}
var _hold_time := {"left": 0.0, "right": 0.0}
var _fired := {"left": false, "right": false}
var _pinch_suppressed := {"left": false, "right": false}

# Set each frame by UI surfaces (e.g. ViewportPanel3D) when their ray hits.
# Consumed by pinch detection below to suppress signals so pinches on panels
# don't also trigger context menus / step nav / anchor gestures.
var _ui_claimed := {"left": false, "right": false}

var _home_pinching := {"left": false, "right": false}
var _home_hold_time := {"left": 0.0, "right": 0.0}
var _home_fired := {"left": false, "right": false}

var _recording := false
var _recording_origin := Transform3D()
var _frames: Array[PoseRec] = []

# Ray state — read by consumers each frame (keyed by "left"/"right")
var ray_origins := {"left": Vector3.ZERO, "right": Vector3.ZERO}
var ray_directions := {"left": Vector3.ZERO, "right": Vector3.ZERO}
var ray_active := {"left": false, "right": false}

var _ray_dir_smooth := {"left": Vector3.ZERO, "right": Vector3.ZERO}
var _ray_visual_origins := {"left": Vector3.ZERO, "right": Vector3.ZERO}
var _hit_points := {"left": Vector3.INF, "right": Vector3.INF}

var _ray_line: MeshInstance3D
var _ray_immediate: ImmediateMesh
var _reticles := {}


func _ready() -> void:
	set_process_priority(-1)

	_ray_immediate = ImmediateMesh.new()
	var ray_mat := StandardMaterial3D.new()
	ray_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ray_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ray_mat.vertex_color_use_as_albedo = true
	_ray_line = MeshInstance3D.new()
	_ray_line.mesh = _ray_immediate
	_ray_line.material_override = ray_mat
	_ray_line.top_level = true
	add_child(_ray_line)

	for hand in _TRACKERS:
		var reticle_mesh := SphereMesh.new()
		reticle_mesh.radius = 0.006
		reticle_mesh.height = 0.012
		reticle_mesh.radial_segments = 8
		reticle_mesh.rings = 4
		var reticle_mat := StandardMaterial3D.new()
		reticle_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		reticle_mat.albedo_color = Color(1.0, 1.0, 1.0, 1.0)
		var reticle := MeshInstance3D.new()
		reticle.mesh = reticle_mesh
		reticle.material_override = reticle_mat
		reticle.top_level = true
		reticle.visible = false
		add_child(reticle)
		_reticles[hand] = reticle


func _process(delta: float) -> void:
	# Draw visuals using last frame's hit_points, then reset for this frame's consumers
	_update_ray_visuals()
	for hand in _TRACKERS:
		_hit_points[hand] = Vector3.INF

	# Pinch detection reads _ui_claimed from last frame (panels run after us),
	# so check pinches first, then reset for this frame's panel updates.
	for hand in _TRACKERS:
		_check_hand(hand, delta)
		_check_home_gesture(hand, delta)

	for hand in _TRACKERS:
		_ui_claimed[hand] = false

	_update_ray(delta)

	if _recording:
		_record_frame()


# Called by consumers (e.g. ViewportPanel3D) when their intersection test hits
func set_hit_point(hand: String, world_pos: Vector3) -> void:
	_hit_points[hand] = world_pos


# Called each frame by UI panels when their ray is hovering them. Suppresses
# pinch signals starting this frame so panel clicks don't double as gestures.
func claim_ui(hand: String) -> void:
	_ui_claimed[hand] = true


func is_ray_pinching(hand: String) -> bool:
	return _pinching.get(hand, false)


func _update_ray(delta: float) -> void:
	var xr_origin := get_parent() as XROrigin3D
	var camera := get_viewport().get_camera_3d()

	for hand in _TRACKERS:
		ray_active[hand] = false
		var tracker := XRServer.get_tracker(_TRACKERS[hand])
		if not xr_origin or not tracker or not tracker is XRHandTracker:
			_ray_dir_smooth[hand] = Vector3.ZERO
			continue
		var ht := tracker as XRHandTracker
		if not ht.has_tracking_data or not (ht.get_hand_joint_flags(0) & 4):
			_ray_dir_smooth[hand] = Vector3.ZERO
			continue

		var xr_tf := xr_origin.global_transform
		var palm_xform := xr_tf * ht.get_hand_joint_transform(0)

		var raw_dir: Vector3
		var blend_origin: Vector3

		# Joint 1 = wrist, joint 7 = index proximal knuckle (stable during pinch)
		var has_wrist := bool(ht.get_hand_joint_flags(1) & 4)
		var has_index_prox := bool(ht.get_hand_joint_flags(7) & 4)

		if has_wrist and has_index_prox and camera:
			var wrist_pos := (xr_tf * ht.get_hand_joint_transform(1)).origin
			var aim_point := (xr_tf * ht.get_hand_joint_transform(7)).origin
			var side := 1.0 if hand == "right" else -1.0
			var shoulder := camera.global_position + camera.global_basis * Vector3(side * shoulder_side, -shoulder_drop, 0.0)
			blend_origin = wrist_pos.lerp(shoulder, shoulder_blend)
			raw_dir = (aim_point - blend_origin).normalized()
			_ray_visual_origins[hand] = wrist_pos
		else:
			raw_dir = palm_xform.basis.z
			blend_origin = palm_xform.origin - palm_xform.basis.z * ray_back_offset
			_ray_visual_origins[hand] = palm_xform.origin

		if raw_dir.length_squared() < 0.001:
			continue

		if _ray_dir_smooth[hand] == Vector3.ZERO:
			_ray_dir_smooth[hand] = raw_dir
		else:
			_ray_dir_smooth[hand] = _ray_dir_smooth[hand].lerp(raw_dir, ray_smooth_speed * delta).normalized()

		ray_directions[hand] = _ray_dir_smooth[hand]
		ray_origins[hand] = blend_origin
		ray_active[hand] = true


func _update_ray_visuals() -> void:
	_ray_immediate.clear_surfaces()

	for hand in _TRACKERS:
		if not ray_active[hand]:
			_reticles[hand].visible = false
			continue

		var has_hit: bool = _hit_points[hand] != Vector3.INF
		var pinching := is_ray_pinching(hand)

		if has_hit:
			var ray_color := Color(0.4, 0.85, 1.0, 1.0) if pinching else Color(1.0, 1.0, 1.0, 0.7)
			_ray_immediate.surface_begin(Mesh.PRIMITIVE_LINES)
			_ray_immediate.surface_set_color(Color(ray_color.r, ray_color.g, ray_color.b, 0.0))
			_ray_immediate.surface_add_vertex(_ray_visual_origins[hand])
			_ray_immediate.surface_set_color(ray_color)
			_ray_immediate.surface_add_vertex(_hit_points[hand])
			_ray_immediate.surface_end()

		_reticles[hand].visible = has_hit
		if has_hit:
			_reticles[hand].global_position = _hit_points[hand]
			var reticle_mat := _reticles[hand].material_override as StandardMaterial3D
			reticle_mat.albedo_color = Color(0.4, 0.85, 1.0, 1.0) if pinching else Color(1.0, 1.0, 1.0, 0.9)
			_reticles[hand].scale = Vector3.ONE * (0.7 if pinching else 1.0)


func _check_hand(hand: String, delta: float) -> void:
	var tracker := XRServer.get_tracker(_TRACKERS[hand])
	if not tracker or not tracker is XRHandTracker:
		_end(hand)
		return

	var ht := tracker as XRHandTracker
	if not ht.has_tracking_data or not (ht.get_hand_joint_flags(5) & 4) or not (ht.get_hand_joint_flags(10) & 4):
		_end(hand)
		return

	var thumb_pos := ht.get_hand_joint_transform(5).origin
	var index_pos := ht.get_hand_joint_transform(10).origin
	var pinch_pos := (thumb_pos + index_pos) * 0.5

	if thumb_pos.distance_to(index_pos) >= pinch_threshold:
		_end(hand)
		return

	if not _pinching[hand]:
		_pinching[hand] = true
		_hold_time[hand] = 0.0
		_fired[hand] = false
		_pinch_suppressed[hand] = _ui_claimed[hand]
		if not _pinch_suppressed[hand]:
			pinch_started.emit(hand, pinch_pos)

	if _pinch_suppressed[hand]:
		return

	if not _fired[hand]:
		_hold_time[hand] += delta
		pinch_held.emit(hand, pinch_pos, _hold_time[hand])
		if _hold_time[hand] >= hold_time:
			_fired[hand] = true
			pinch_completed.emit(hand, pinch_pos)


func _end(hand: String) -> void:
	if _pinching[hand]:
		_pinching[hand] = false
		_hold_time[hand] = 0.0
		_fired[hand] = false
		var was_suppressed: bool = _pinch_suppressed[hand]
		_pinch_suppressed[hand] = false
		if not was_suppressed:
			pinch_ended.emit(hand)


func _check_home_gesture(hand: String, delta: float) -> void:
	# Thumbs up: thumb tip (5) above wrist (1), all fingers curled (tips near proximal knuckles)
	# Joints: index tip=10 proximal=7, middle tip=15 proximal=12, ring tip=20 proximal=17, pinky tip=25 proximal=22
	const THUMB_UP_THRESHOLD  := 0.04  # thumb tip must be this far above wrist in Y
	const CURL_THRESHOLD      := 0.05  # fingertip-to-proximal distance for a curled finger

	var tracker := XRServer.get_tracker(_TRACKERS[hand])
	if not tracker or not tracker is XRHandTracker:
		_end_home(hand)
		return
	var ht := tracker as XRHandTracker

	var required_joints := [1, 5, 7, 10, 12, 15, 17, 20, 22, 25]
	for j in required_joints:
		if not (ht.get_hand_joint_flags(j) & 4):
			_end_home(hand)
			return

	var wrist_y     := ht.get_hand_joint_transform(1).origin.y
	var thumb_tip_y := ht.get_hand_joint_transform(5).origin.y
	if thumb_tip_y - wrist_y < THUMB_UP_THRESHOLD:
		_end_home(hand)
		return

	var finger_pairs := [[10, 7], [15, 12], [20, 17], [25, 22]]
	for pair in finger_pairs:
		var tip     := ht.get_hand_joint_transform(pair[0]).origin
		var proximal := ht.get_hand_joint_transform(pair[1]).origin
		if tip.distance_to(proximal) > CURL_THRESHOLD:
			_end_home(hand)
			return

	var thumb_pos := ht.get_hand_joint_transform(5).origin

	if not _home_pinching[hand]:
		_home_pinching[hand] = true
		_home_hold_time[hand] = 0.0
		_home_fired[hand] = false

	if not _home_fired[hand]:
		_home_hold_time[hand] += delta
		home_gesture_held.emit(hand, thumb_pos, _home_hold_time[hand])
		if _home_hold_time[hand] >= hold_time:
			_home_fired[hand] = true
			home_gesture_completed.emit(hand)


func _end_home(hand: String) -> void:
	if _home_pinching[hand]:
		_home_pinching[hand] = false
		_home_hold_time[hand] = 0.0
		_home_fired[hand] = false
		home_gesture_ended.emit(hand)


# ---- Hand pose recording ----

func start_recording(origin: Transform3D = Transform3D.IDENTITY) -> void:
	_frames.clear()
	# origin should be the GLB→world calibration transform from LocationManager.
	# Storing its inverse maps all poses into building space at record time.
	_recording_origin = origin
	_recording = true

func stop_recording() -> Array[PoseRec]:
	_recording = false
	var result := _frames.duplicate()
	_frames.clear()
	return result

func is_recording() -> bool:
	return _recording

func _record_frame() -> void:
	var pose := PoseRec.new()
	pose.timestamp_msec = Time.get_ticks_msec()
	var inv_origin := _recording_origin.affine_inverse()
	var camera := get_viewport().get_camera_3d()
	if camera:
		pose.head_transform = inv_origin * camera.global_transform
	pose.left_tracked  = _capture_hand_joints("left",  pose.left_joints,  inv_origin)
	pose.right_tracked = _capture_hand_joints("right", pose.right_joints, inv_origin)
	_frames.append(pose)

func _capture_hand_joints(hand: String, joints: Array[Transform3D], inv_origin: Transform3D) -> bool:
	var tracker := XRServer.get_tracker(_TRACKERS[hand])
	if not tracker or not tracker is XRHandTracker:
		return false
	var ht := tracker as XRHandTracker
	if not ht.has_tracking_data or not (ht.get_hand_joint_flags(1) & 4):
		return false
	for joint_idx in PoseRec.JOINT_COUNT:
		if ht.get_hand_joint_flags(joint_idx) & 4:
			joints[joint_idx] = inv_origin * ht.get_hand_joint_transform(joint_idx)
	return true
