class_name PoseReplayer
extends Node3D

const LEFT_HAND_SCENE := preload("res://assets/hands/LeftHandHumanoid.gltf")
const RIGHT_HAND_SCENE := preload("res://assets/hands/RightHandHumanoid.gltf")

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

# Approximate distances in metres used for skeleton estimation.
const _SHOULDER_HALF_WIDTH := 0.20
const _SHOULDER_DROP      := 0.15   # below head origin
const _ELBOW_HANG         := 0.10   # additional downward bias for natural elbow droop
const _HIP_DROP           := 0.55   # below neck

signal playback_finished
signal initialized

var skeleton_enabled: bool = false:
	set(v):
		skeleton_enabled = v
		_set_skeleton_visible(_playing and v)

var _frames: Array[PoseRec] = []
var _playing := false
var _looping := false
var _start_time_msec: int
var _base_time_msec: int
var _frame_idx: int = 0
var _initialized := false

var _left_skeleton:   Skeleton3D
var _right_skeleton:  Skeleton3D
var _left_bone_map:   PackedInt32Array
var _right_bone_map:  PackedInt32Array
var _left_hand_inst:  Node3D
var _right_hand_inst: Node3D

var _head_mesh: MeshInstance3D

# Skeleton nodes (only used when skeleton_enabled)
var _left_shoulder:    MeshInstance3D
var _right_shoulder:   MeshInstance3D
var _left_elbow:       MeshInstance3D
var _right_elbow:      MeshInstance3D
var _left_upper_arm:   MeshInstance3D
var _right_upper_arm:  MeshInstance3D
var _left_forearm:     MeshInstance3D
var _right_forearm:    MeshInstance3D
var _clavicle:         MeshInstance3D
var _torso:            MeshInstance3D


func _ready() -> void:
	_init_async()

# instantiates, spread over several frames - cos this instantiation is very heavy this stops us from hanging the app
func _init_async() -> void:
	var left_inst := LEFT_HAND_SCENE.instantiate()
	_left_hand_inst = left_inst
	add_child(left_inst)

	# waits for the next frame to be processed
	await get_tree().process_frame

	var right_inst := RIGHT_HAND_SCENE.instantiate()
	_right_hand_inst = right_inst
	add_child(right_inst)

	# waits for the next frame to be processed
	await get_tree().process_frame

	_left_skeleton = _find_skeleton(left_inst)
	_right_skeleton = _find_skeleton(right_inst)
	_left_bone_map = _build_bone_map(_left_skeleton, JOINT_BONES_LEFT)
	_right_bone_map = _build_bone_map(_right_skeleton, JOINT_BONES_RIGHT)

	var ghost_mat := StandardMaterial3D.new()
	ghost_mat.albedo_color = Color(0.8, 0.85, 1.0, 0.45)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_head_mesh = _make_sphere(0.12, ghost_mat)
	_head_mesh.visible = false

	var joint_mat := StandardMaterial3D.new()
	joint_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.55)
	joint_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var limb_mat := StandardMaterial3D.new()
	limb_mat.albedo_color = Color(0.7, 0.85, 1.0, 0.35)
	limb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	_left_shoulder   = _make_sphere(0.035, joint_mat)
	_right_shoulder  = _make_sphere(0.035, joint_mat)
	_left_elbow      = _make_sphere(0.030, joint_mat)
	_right_elbow     = _make_sphere(0.030, joint_mat)
	_left_upper_arm  = _make_cylinder(0.025, limb_mat)
	_right_upper_arm = _make_cylinder(0.025, limb_mat)
	_left_forearm    = _make_cylinder(0.022, limb_mat)
	_right_forearm   = _make_cylinder(0.022, limb_mat)
	_clavicle        = _make_cylinder(0.020, limb_mat)
	_torso           = _make_cylinder(0.070, limb_mat)

	_set_skeleton_visible(false)
	_initialized = true
	initialized.emit()


func play(frames: Array[PoseRec], loop := false) -> void:
	_frames = frames
	_looping = loop
	_frame_idx = 0
	if _frames.is_empty():
		return
	if not _initialized:
		await initialized
	_base_time_msec = _frames[0].timestamp_msec
	_start_time_msec = Time.get_ticks_msec()
	_playing = true
	_head_mesh.visible = true
	_set_skeleton_visible(skeleton_enabled)


func stop() -> void:
	_playing = false
	_head_mesh.visible = false
	_set_skeleton_visible(false)


func is_playing() -> bool:
	return _playing


func _process(_delta: float) -> void:
	if not _playing or _frames.is_empty():
		return

	var elapsed := Time.get_ticks_msec() - _start_time_msec
	var target_time := _base_time_msec + elapsed

	while _frame_idx < _frames.size() - 1 and _frames[_frame_idx + 1].timestamp_msec <= target_time:
		_frame_idx += 1

	if target_time > _frames[_frames.size() - 1].timestamp_msec:
		if _looping:
			_frame_idx = 0
			_start_time_msec = Time.get_ticks_msec()
		else:
			_playing = false
			_head_mesh.visible = false
			_set_skeleton_visible(false)
			playback_finished.emit()
			return

	var pose := _frames[_frame_idx]
	var left_tracked  := pose.left_tracked
	var right_tracked := pose.right_tracked
	if _left_hand_inst:
		_left_hand_inst.visible = left_tracked
	if _right_hand_inst:
		_right_hand_inst.visible = right_tracked
	_apply_joints(_left_skeleton, _left_bone_map, pose.left_joints)
	_apply_joints(_right_skeleton, _right_bone_map, pose.right_joints)

	var head_world := global_transform * pose.head_transform
	_head_mesh.global_transform = head_world

	if skeleton_enabled:
		_update_skeleton(pose, head_world)


# ── Skeleton estimation ───────────────────────────────────────────────────────

func _update_skeleton(pose: PoseRec, head_world: Transform3D) -> void:
	var head_pos   := head_world.origin
	var head_basis := head_world.basis

	var neck               := head_pos + head_basis.y * -(_SHOULDER_DROP * 0.4)
	var left_shoulder_pos  := neck + head_basis.x * -_SHOULDER_HALF_WIDTH + Vector3.DOWN * (_SHOULDER_DROP * 0.6)
	var right_shoulder_pos := neck + head_basis.x *  _SHOULDER_HALF_WIDTH + Vector3.DOWN * (_SHOULDER_DROP * 0.6)
	var hip                := neck + Vector3.DOWN * _HIP_DROP

	_orient_limb(_clavicle, left_shoulder_pos, right_shoulder_pos)
	_orient_limb(_torso, neck, hip)

	var left_tracked  := pose.left_tracked
	var right_tracked := pose.right_tracked

	if left_tracked:
		var left_wrist    := (global_transform * pose.left_joints[1]).origin
		var left_elbow_pos := _estimate_elbow(left_shoulder_pos, left_wrist, -1.0)
		_left_shoulder.global_position = left_shoulder_pos
		_left_elbow.global_position    = left_elbow_pos
		_orient_limb(_left_upper_arm, left_shoulder_pos, left_elbow_pos)
		_orient_limb(_left_forearm,   left_elbow_pos,    left_wrist)

	if right_tracked:
		var right_wrist    := (global_transform * pose.right_joints[1]).origin
		var right_elbow_pos := _estimate_elbow(right_shoulder_pos, right_wrist, 1.0)
		_right_shoulder.global_position = right_shoulder_pos
		_right_elbow.global_position    = right_elbow_pos
		_orient_limb(_right_upper_arm, right_shoulder_pos, right_elbow_pos)
		_orient_limb(_right_forearm,   right_elbow_pos,    right_wrist)

	_left_shoulder.visible  = left_tracked
	_left_elbow.visible     = left_tracked
	_left_upper_arm.visible = left_tracked
	_left_forearm.visible   = left_tracked
	_right_shoulder.visible  = right_tracked
	_right_elbow.visible     = right_tracked
	_right_upper_arm.visible = right_tracked
	_right_forearm.visible   = right_tracked


func _estimate_elbow(shoulder: Vector3, wrist: Vector3, side: float) -> Vector3:
	var mid := (shoulder + wrist) * 0.5
	# Pull the elbow down (gravity bias) and very slightly outward.
	var sw := wrist - shoulder
	var lateral := sw.cross(Vector3.UP).normalized() * side * -0.04
	return mid + Vector3.DOWN * _ELBOW_HANG + lateral


func _orient_limb(node: MeshInstance3D, from: Vector3, to: Vector3) -> void:
	var dir := to - from
	var length := dir.length()
	if length < 0.001:
		return
	node.global_position = (from + to) * 0.5
	var y := dir / length
	var ref := Vector3.FORWARD if abs(y.dot(Vector3.UP)) > 0.9 else Vector3.UP
	var x := ref.cross(y).normalized()
	var z := y.cross(x)
	node.global_transform.basis = Basis(x, y, z)
	(node.mesh as CylinderMesh).height = length


# ── Hand joint application ────────────────────────────────────────────────────

func _apply_joints(skeleton: Skeleton3D, bone_map: PackedInt32Array, joints: Array[Transform3D]) -> void:
	if skeleton == null:
		return

	# Convert recorded transforms (calibration space) into skeleton model space.
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

func _set_skeleton_visible(v: bool) -> void:
	for node in [
		_left_shoulder, _right_shoulder, _left_elbow, _right_elbow,
		_left_upper_arm, _right_upper_arm, _left_forearm, _right_forearm,
		_clavicle, _torso
	]:
		if node:
			node.visible = v


func _make_sphere(radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


func _make_cylinder(radius: float, mat: StandardMaterial3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.1  # updated per-frame by _orient_limb
	mi.mesh = mesh
	mi.material_override = mat
	add_child(mi)
	return mi


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
