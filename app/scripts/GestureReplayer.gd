class_name GestureReplayer
extends Node3D

const LEFT_HAND_SCENE := preload("res://assets/hands/LeftHandHumanoid.gltf")
const RIGHT_HAND_SCENE := preload("res://assets/hands/RightHandHumanoid.gltf")

# XRHandTracker joint index -> skeleton bone name.
# Joint 0 (Palm) has no bone. Joint 1 (Wrist) maps to the hand root bone.
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

# Parent joint index for each joint. -1 = skip (Palm) or root (Wrist).
const JOINT_PARENTS := [
	-1, -1,
	1, 2, 3, 4,
	1, 6, 7, 8, 9,
	1, 11, 12, 13, 14,
	1, 16, 17, 18, 19,
	1, 21, 22, 23, 24,
]

signal playback_finished

var _frames: Array[HandPoseRec] = []
var _playing := false
var _looping := false
var _start_time_msec: int
var _base_time_msec: int
var _frame_idx: int = 0

var _left_skeleton: Skeleton3D
var _right_skeleton: Skeleton3D
var _left_bone_map: PackedInt32Array
var _right_bone_map: PackedInt32Array


func _ready() -> void:
	var left_inst := LEFT_HAND_SCENE.instantiate()
	var right_inst := RIGHT_HAND_SCENE.instantiate()
	add_child(left_inst)
	add_child(right_inst)

	_left_skeleton = _find_skeleton(left_inst)
	_right_skeleton = _find_skeleton(right_inst)
	_left_bone_map = _build_bone_map(_left_skeleton, JOINT_BONES_LEFT)
	_right_bone_map = _build_bone_map(_right_skeleton, JOINT_BONES_RIGHT)


func play(frames: Array[HandPoseRec], loop := false) -> void:
	_frames = frames
	_looping = loop
	_frame_idx = 0
	if _frames.is_empty():
		return
	_base_time_msec = _frames[0].timestamp_msec
	_start_time_msec = Time.get_ticks_msec()
	_playing = true


func stop() -> void:
	_playing = false


func is_playing() -> bool:
	return _playing


func _process(_delta: float) -> void:
	if not _playing or _frames.is_empty():
		return

	var elapsed := Time.get_ticks_msec() - _start_time_msec
	var target_time := _base_time_msec + elapsed

	# Advance to the correct frame.
	while _frame_idx < _frames.size() - 1 and _frames[_frame_idx + 1].timestamp_msec <= target_time:
		_frame_idx += 1

	if target_time > _frames[_frames.size() - 1].timestamp_msec:
		if _looping:
			_frame_idx = 0
			_start_time_msec = Time.get_ticks_msec()
		else:
			_playing = false
			playback_finished.emit()
			return

	var pose := _frames[_frame_idx]
	_apply_joints(_left_skeleton, _left_bone_map, pose.left_joints)
	_apply_joints(_right_skeleton, _right_bone_map, pose.right_joints)


func _apply_joints(skeleton: Skeleton3D, bone_map: PackedInt32Array, joints: Array[Transform3D]) -> void:
	if skeleton == null:
		return

	# Convert recorded transforms (XR origin space) into skeleton model space.
	# The GestureReplayer's transform acts as the recording's origin.
	var to_model := skeleton.global_transform.affine_inverse() * global_transform

	var model_xforms: Array[Transform3D] = []
	model_xforms.resize(HandPoseRec.JOINT_COUNT)
	for i in HandPoseRec.JOINT_COUNT:
		model_xforms[i] = to_model * joints[i]

	for joint_idx in HandPoseRec.JOINT_COUNT:
		var bone_idx := bone_map[joint_idx]
		if bone_idx < 0:
			continue

		# Skip joints with no tracking data (identity transform).
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
	map.resize(HandPoseRec.JOINT_COUNT)
	for i in HandPoseRec.JOINT_COUNT:
		if bone_names[i] == "":
			map[i] = -1
		else:
			map[i] = skeleton.find_bone(bone_names[i])
	return map
