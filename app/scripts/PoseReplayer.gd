# Takes an array of PoseRec frames, and overlays them onto a humanoid model for playback
# Performs IK to infer shoulder and elbow positions

class_name PoseReplayer
extends Node3D

const LEFT_HAND_SCENE  := preload("res://assets/hands/LeftHandHumanoid.gltf")
const RIGHT_HAND_SCENE := preload("res://assets/hands/RightHandHumanoid.gltf")
# Body model uses Mannequiny
# Loaded at runtime so the editor can reimport without breaking preload.
const BODY_SCENE_PATH  := "res://assets/body/Mannequin.glb"

# Bone names in the body model (Mannequiny / Blender rigify convention)
const B_LEFT_SHOULDER  := "upperarm.l"
const B_RIGHT_SHOULDER := "upperarm.r"
const B_LEFT_HAND      := "hand.l"
const B_RIGHT_HAND     := "hand.r"

const JOINT_BONES_LEFT := [
	"", "LeftHand",
	"LeftThumbMetacarpal", "LeftThumbProximal", "LeftThumbDistal", "LeftThumbTip",
	"LeftIndexMetacarpal", "LeftIndexProximal", "LeftIndexIntermediate", "LeftIndexDistal", "LeftIndexTip",
	"LeftMiddleMetacarpal", "LeftMiddleProximal", "LeftMiddleIntermediate", "LeftMiddleDistal", "LeftMiddleTip",
	"LeftRingMetacarpal", "LeftRingProximal", "LeftRingIntermediate", "LeftRingDistal", "LeftRingTip",
	"LeftLittleMetacarpal", "LeftLittleProximal", "LeftLittleIntermediate", "LeftLittleDistal", "LeftLittleTip",
]

const JOINT_BONES_RIGHT := [
	"", "RightHand",
	"RightThumbMetacarpal", "RightThumbProximal", "RightThumbDistal", "RightThumbTip",
	"RightIndexMetacarpal", "RightIndexProximal", "RightIndexIntermediate", "RightIndexDistal", "RightIndexTip",
	"RightMiddleMetacarpal", "RightMiddleProximal", "RightMiddleIntermediate", "RightMiddleDistal", "RightMiddleTip",
	"RightRingMetacarpal", "RightRingProximal", "RightRingIntermediate", "RightRingDistal", "RightRingTip",
	"RightLittleMetacarpal", "RightLittleProximal", "RightLittleIntermediate", "RightLittleDistal", "RightLittleTip",
]

const JOINT_PARENTS := [
	-1, -1,
	1, 2, 3, 4,
	1, 6, 7, 8, 9,
	1, 11, 12, 13, 14,
	1, 16, 17, 18, 19,
	1, 21, 22, 23, 24,
]

# Computed at init from the body model's actual head bone rest position.
# Falls back to a reasonable average if the bone isn't found.
var _head_bone_height: float = 1.65

signal playback_finished
signal initialized

# Kept for API compatibility – body always shows during playback regardless of this value
var skeleton_enabled: bool = false

var _frames: Array[PoseRec] = []
var _playing     := false
var _looping     := false
var _start_time_msec: int
var _base_time_msec:  int
var _frame_idx:  int = 0
var _initialized := false

# Hand models – provide precise finger detail
var _left_skeleton:   Skeleton3D
var _right_skeleton:  Skeleton3D
var _left_bone_map:   PackedInt32Array
var _right_bone_map:  PackedInt32Array
var _left_hand_inst:  Node3D
var _right_hand_inst: Node3D

# Body model – torso + arm IK
var _body_inst:     Node3D
var _body_skeleton: Skeleton3D
var _left_arm_ik:   SkeletonIK3D
var _right_arm_ik:  SkeletonIK3D
var _left_wrist_target:  Node3D
var _right_wrist_target: Node3D
var _left_arm_bones:  PackedInt32Array
var _right_arm_bones: PackedInt32Array
var _head_bone_idx: int = -1
var _neck_bone_idx: int = -1

# When true, untracked arms glide to a natural rest pose instead of vanishing.
var rest_arms_on_lost_tracking: bool = false

const _LEFT_REST_LOCAL  := Vector3( 0.3, 0.9, 0.05)
const _RIGHT_REST_LOCAL := Vector3(-0.3, 0.9, 0.05)
const _REST_LERP_SPEED  := 2.0   # seconds to reach rest position

var _left_untracked_t:  float = 1.0
var _right_untracked_t: float = 1.0
var _left_wrist_from:   Vector3 = Vector3.ZERO
var _right_wrist_from:  Vector3 = Vector3.ZERO


func _ready() -> void:
	_init_async()


func _init_async() -> void:
	# Hand models
	var left_inst := LEFT_HAND_SCENE.instantiate()
	_left_hand_inst = left_inst
	add_child(left_inst)
	await get_tree().process_frame # wait a frame to stop hanging

	var right_inst := RIGHT_HAND_SCENE.instantiate()
	_right_hand_inst = right_inst
	add_child(right_inst)
	await get_tree().process_frame # wait a frame to stop hanging

	_left_skeleton  = _find_skeleton(left_inst)
	_right_skeleton = _find_skeleton(right_inst)
	_left_bone_map  = _build_bone_map(_left_skeleton,  JOINT_BONES_LEFT)
	_right_bone_map = _build_bone_map(_right_skeleton, JOINT_BONES_RIGHT)

	# Body model
	var body_scene := load(BODY_SCENE_PATH) as PackedScene
	if body_scene:
		var body_inst := body_scene.instantiate()
		_body_inst = body_inst
		add_child(body_inst)
		await get_tree().process_frame

		_body_skeleton = _find_skeleton(body_inst)

		# Measure how high the head bone sits above the model root so we can
		# place the model root such that the head bone aligns with the tracked head.
		if _body_skeleton:
			_head_bone_idx = _body_skeleton.find_bone("head")
			_neck_bone_idx = _body_skeleton.find_bone("neck_01")
			var head_idx := _head_bone_idx
			if head_idx >= 0:
				var sk_y_in_body: float = body_inst.to_local(_body_skeleton.global_position).y
				var head_rest_y: float  = _body_skeleton.get_bone_global_rest(head_idx).origin.y
				_head_bone_height = sk_y_in_body + head_rest_y

			# Zero-scale bones that should never appear: fingers on the body mesh,
			# and the entire leg chains (no tracking data). Pelvis is left at scale 1
			# because it is the spine root — zeroing it collapses the whole torso.
			for bone_name in ["hand.l", "hand.r"]:
				var idx := _body_skeleton.find_bone(bone_name)
				if idx >= 0:
					_body_skeleton.set_bone_pose_scale(idx, Vector3(0.001, 0.001, 0.001))

			for bone_name in [
				"thigh.l", "calf.l", "foot.l", "ball.l",
				"thigh.r", "calf.r", "foot.r", "ball.r",
				"thumb_01.l", "thumb_02.l", "thumb_03.l",
				"index_01.l", "index_02.l", "index_03.l",
				"middle_01.l","middle_02.l","middle_03.l",
				"ring_01.l",  "ring_02.l",  "ring_03.l",
				"thumb_01.r", "thumb_02.r", "thumb_03.r",
				"index_01.r", "index_02.r", "index_03.r",
				"middle_01.r","middle_02.r","middle_03.r",
				"ring_01.r",  "ring_02.r",  "ring_03.r",
			]:
				var idx := _body_skeleton.find_bone(bone_name)
				if idx >= 0:
					_body_skeleton.set_bone_pose_scale(idx, Vector3.ZERO)

		# IK wrist target markers (world-space, siblings of the body)
		_left_wrist_target  = Node3D.new()
		_right_wrist_target = Node3D.new()
		add_child(_left_wrist_target)
		add_child(_right_wrist_target)

		if _body_skeleton:
			_left_arm_ik  = _make_arm_ik(B_LEFT_SHOULDER,  B_LEFT_HAND,  _left_wrist_target,
										  Vector3(-0.1, -0.3, 0.0))
			_right_arm_ik = _make_arm_ik(B_RIGHT_SHOULDER, B_RIGHT_HAND, _right_wrist_target,
										  Vector3( 0.1, -0.3, 0.0))
			_left_arm_bones  = PackedInt32Array([
				_body_skeleton.find_bone("upperarm.l"),
				_body_skeleton.find_bone("lowerarm.l"),
			])
			_right_arm_bones = PackedInt32Array([
				_body_skeleton.find_bone("upperarm.r"),
				_body_skeleton.find_bone("lowerarm.r"),
			])

		body_inst.visible = false
	else:
		push_warning("PoseReplayer: body model not found at %s – open editor to import" % BODY_SCENE_PATH)

	# Ghost material – fresnel rim shader gives edge definition without external lighting.
	# Edges are bright, centres are dim, producing a hologram silhouette.
	var ghost_shader := Shader.new()
	ghost_shader.code = """
shader_type spatial;
render_mode unshaded, cull_back;

uniform vec3 rim_color  : source_color = vec3(0.25, 0.5, 0.85);
uniform vec3 fill_color : source_color = vec3(0.03, 0.07, 0.18);
uniform float rim_power  : hint_range(0.5, 8.0) = 2.5;
void fragment() {
	float fresnel = 1.0 - abs(dot(NORMAL, VIEW));
	fresnel = pow(fresnel, rim_power);
	ALBEDO = mix(fill_color, rim_color, fresnel);
}
"""
	var ghost_mat := ShaderMaterial.new()
	ghost_mat.shader = ghost_shader

	_apply_material_recursive(left_inst,  ghost_mat)
	_apply_material_recursive(right_inst, ghost_mat)
	if _body_inst:
		_apply_material_recursive(_body_inst, ghost_mat)

	left_inst.visible  = false
	right_inst.visible = false

	_initialized = true
	initialized.emit()


func _make_arm_ik(root: String, tip: String, target: Node3D, magnet: Vector3) -> SkeletonIK3D:
	var ik := SkeletonIK3D.new()
	ik.root_bone    = root
	ik.tip_bone     = tip
	ik.use_magnet   = true
	ik.magnet       = magnet
	ik.interpolation = 0.0
	_body_skeleton.add_child(ik)
	ik.target_node  = ik.get_path_to(target)
	ik.start()
	return ik


func play(frames: Array[PoseRec], loop := false) -> void:
	_frames  = frames
	_looping = loop
	_frame_idx = 0
	if _frames.is_empty():
		return
	if not _initialized:
		await initialized
	_base_time_msec  = _frames[0].timestamp_msec
	_start_time_msec = Time.get_ticks_msec()
	_playing = true
	if _body_inst:
		_body_inst.visible = true


func stop() -> void:
	_playing = false
	if _body_inst:       _body_inst.visible      = false
	if _left_hand_inst:  _left_hand_inst.visible  = false
	if _right_hand_inst: _right_hand_inst.visible = false


func is_playing() -> bool:
	return _playing


func _process(delta: float) -> void:
	if not _playing or _frames.is_empty():
		return

	var elapsed     := Time.get_ticks_msec() - _start_time_msec
	var target_time := _base_time_msec + elapsed

	while _frame_idx < _frames.size() - 1 and _frames[_frame_idx + 1].timestamp_msec <= target_time:
		_frame_idx += 1

	if target_time > _frames[_frames.size() - 1].timestamp_msec:
		if _looping:
			_frame_idx       = 0
			_start_time_msec = Time.get_ticks_msec()
		else:
			_playing = false
			if _body_inst:       _body_inst.visible      = false
			if _left_hand_inst:  _left_hand_inst.visible  = false
			if _right_hand_inst: _right_hand_inst.visible = false
			playback_finished.emit()
			return

	var pose := _frames[_frame_idx]
	var next := _frames[min(_frame_idx + 1, _frames.size() - 1)]

	# Interpolation factor for sub-frame smoothing
	var t := 0.0
	var t0 := float(_frames[_frame_idx].timestamp_msec)
	var t1 := float(next.timestamp_msec)
	if t1 > t0:
		t = clamp(float(target_time) - t0, 0.0, t1 - t0) / (t1 - t0)

	# Interpolated head transform
	var head_a := global_transform * pose.head_transform
	var head_b := global_transform * next.head_transform
	var head_pos := head_a.origin.lerp(head_b.origin, t)
	var head_rot := head_a.basis.get_rotation_quaternion().slerp(
		head_b.basis.get_rotation_quaternion(), t)

	# Place body root so the head bone aligns with the tracked head position,
	# then yaw the body to match the head's horizontal facing direction.
	if _body_inst:
		_body_inst.global_position = head_pos + Vector3.DOWN * _head_bone_height
		# Mannequiny faces +Z at rest, so pass the head's +Z (not -Z) to look_at.
		var fwd_flat := Vector3(Basis(head_rot).z.x, 0.0, Basis(head_rot).z.z)
		if fwd_flat.length_squared() > 0.0001:
			_body_inst.look_at(_body_inst.global_position + fwd_flat, Vector3.UP)

		# Drive head bone to match full tracked head rotation (pitch + roll + yaw).
		# Converts world-space head rotation into the neck bone's local space.
		if _head_bone_idx >= 0 and _neck_bone_idx >= 0:
			var corrected_rot := head_rot * Quaternion(Vector3.UP, PI)
			var head_world := Transform3D(Basis(corrected_rot), head_pos)
			var head_skel  := _body_skeleton.global_transform.affine_inverse() * head_world
			var neck_pose  := _body_skeleton.get_bone_global_pose(_neck_bone_idx)
			var head_local := neck_pose.affine_inverse() * head_skel
			_body_skeleton.set_bone_pose_rotation(_head_bone_idx, head_local.basis.get_rotation_quaternion())

	var left_tracked  := pose.left_tracked
	var right_tracked := pose.right_tracked

	var left_show  := left_tracked  or rest_arms_on_lost_tracking
	var right_show := right_tracked or rest_arms_on_lost_tracking
	if _left_hand_inst:  _left_hand_inst.visible  = left_show
	if _right_hand_inst: _right_hand_inst.visible = right_show

	if _left_arm_ik:
		if left_tracked:
			var wa := (global_transform * pose.left_joints[1]).origin
			var wb := (global_transform * next.left_joints[1]).origin if next.left_tracked else wa
			_left_wrist_from = wa.lerp(wb, t)
			_left_untracked_t = 0.0
			_left_wrist_target.global_position = _left_wrist_from
			_left_arm_ik.interpolation = 1.0
			for idx in _left_arm_bones:
				if idx >= 0: _body_skeleton.set_bone_pose_scale(idx, Vector3.ONE)
		elif rest_arms_on_lost_tracking and _body_inst:
			_left_untracked_t = minf(_left_untracked_t + delta * _REST_LERP_SPEED, 1.0)
			var rest := _body_inst.to_global(_LEFT_REST_LOCAL)
			_left_wrist_target.global_position = _left_wrist_from.lerp(rest, _left_untracked_t)
			_left_arm_ik.interpolation = 1.0
			for idx in _left_arm_bones:
				if idx >= 0: _body_skeleton.set_bone_pose_scale(idx, Vector3.ONE)
		else:
			_left_arm_ik.interpolation = 0.0
			for idx in _left_arm_bones:
				if idx >= 0: _body_skeleton.set_bone_pose_scale(idx, Vector3(0.001, 0.001, 0.001))

	if _right_arm_ik:
		if right_tracked:
			var wa := (global_transform * pose.right_joints[1]).origin
			var wb := (global_transform * next.right_joints[1]).origin if next.right_tracked else wa
			_right_wrist_from = wa.lerp(wb, t)
			_right_untracked_t = 0.0
			_right_wrist_target.global_position = _right_wrist_from
			_right_arm_ik.interpolation = 1.0
			for idx in _right_arm_bones:
				if idx >= 0: _body_skeleton.set_bone_pose_scale(idx, Vector3.ONE)
		elif rest_arms_on_lost_tracking and _body_inst:
			_right_untracked_t = minf(_right_untracked_t + delta * _REST_LERP_SPEED, 1.0)
			var rest := _body_inst.to_global(_RIGHT_REST_LOCAL)
			_right_wrist_target.global_position = _right_wrist_from.lerp(rest, _right_untracked_t)
			_right_arm_ik.interpolation = 1.0
			for idx in _right_arm_bones:
				if idx >= 0: _body_skeleton.set_bone_pose_scale(idx, Vector3.ONE)
		else:
			_right_arm_ik.interpolation = 0.0
			for idx in _right_arm_bones:
				if idx >= 0: _body_skeleton.set_bone_pose_scale(idx, Vector3(0.001, 0.001, 0.001))

	if left_tracked:
		_apply_joints(_left_skeleton, _left_bone_map, pose.left_joints)
	elif rest_arms_on_lost_tracking and _left_skeleton:
		_relax_hand(_left_skeleton, _left_bone_map, _left_untracked_t, _left_wrist_target.global_position)

	if right_tracked:
		_apply_joints(_right_skeleton, _right_bone_map, pose.right_joints)
	elif rest_arms_on_lost_tracking and _right_skeleton:
		_relax_hand(_right_skeleton, _right_bone_map, _right_untracked_t, _right_wrist_target.global_position)


# ── Hand joint application ────────────────────────────────────────────────────

func _relax_hand(skeleton: Skeleton3D, bone_map: PackedInt32Array, t: float, wrist_world: Vector3) -> void:
	var wrist_bone := bone_map[1]
	if wrist_bone >= 0:
		var skel_inv := skeleton.global_transform.affine_inverse()
		var wrist_local := (skel_inv * Transform3D(Basis.IDENTITY, wrist_world)).origin
		skeleton.set_bone_pose_position(wrist_bone, wrist_local)
		# Lerp wrist rotation toward fingers-pointing-down in world space.
		var fingers_down_local := skeleton.global_transform.basis.get_rotation_quaternion().inverse() \
			* Quaternion(Vector3.RIGHT, PI)
		skeleton.set_bone_pose_rotation(wrist_bone,
			skeleton.get_bone_pose_rotation(wrist_bone).slerp(fingers_down_local, t))
	for i in bone_map.size():
		var bone_idx := bone_map[i]
		if bone_idx < 0 or bone_idx == wrist_bone:
			continue
		skeleton.set_bone_pose_rotation(bone_idx, skeleton.get_bone_pose_rotation(bone_idx).slerp(Quaternion.IDENTITY, t))


func _apply_joints(skeleton: Skeleton3D, bone_map: PackedInt32Array, joints: Array[Transform3D]) -> void:
	if skeleton == null:
		return

	var to_model := skeleton.global_transform.affine_inverse() * global_transform

	var model_xforms: Array[Transform3D] = []
	model_xforms.resize(PoseRec.JOINT_COUNT)
	for i in PoseRec.JOINT_COUNT:
		model_xforms[i] = to_model * joints[i]

	for joint_idx in PoseRec.JOINT_COUNT:
		var bone_idx := bone_map[joint_idx]
		if bone_idx < 0:
			continue
		if joints[joint_idx] == Transform3D():
			continue

		var parent_joint: int = JOINT_PARENTS[joint_idx]
		var bone_local: Transform3D
		if parent_joint <= 0 or bone_map[parent_joint] < 0:
			bone_local = model_xforms[joint_idx]
		else:
			bone_local = model_xforms[parent_joint].affine_inverse() * model_xforms[joint_idx]

		skeleton.set_bone_pose_position(bone_idx, bone_local.origin)
		skeleton.set_bone_pose_rotation(bone_idx, bone_local.basis.get_rotation_quaternion())


# ── Helpers ───────────────────────────────────────────────────────────────────

func _apply_material_recursive(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).material_override = mat
	for child in node.get_children():
		_apply_material_recursive(child, mat)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result:
			return result
	return null


func _build_bone_map(skeleton: Skeleton3D, bone_names: Array) -> PackedInt32Array:
	var map := PackedInt32Array()
	map.resize(PoseRec.JOINT_COUNT)
	for i in PoseRec.JOINT_COUNT:
		if bone_names[i] == "":
			map[i] = -1
		else:
			map[i] = skeleton.find_bone(bone_names[i])
	return map
