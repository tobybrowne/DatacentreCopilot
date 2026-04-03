class_name HandPoseRec

const JOINT_COUNT := 26

var timestamp_msec: int
var left_joints: Array[Transform3D]
var right_joints: Array[Transform3D]

func _init() -> void:
	left_joints.resize(JOINT_COUNT)
	right_joints.resize(JOINT_COUNT)
