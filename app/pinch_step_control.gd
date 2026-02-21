class_name PinchStepControl
extends Node

## Distance in metres below which a pinch is registered
@export var pinch_threshold: float = 0.02

signal prev_requested
signal next_requested

var _left_pinching := false
var _right_pinching := false


func _process(_delta: float) -> void:
	_check_hand("/user/hand_tracker/left", true)
	_check_hand("/user/hand_tracker/right", false)


func _check_hand(tracker_path: String, is_left: bool) -> void:
	var tracker := XRServer.get_tracker(tracker_path)
	if not tracker or not tracker is XRHandTracker:
		return

	var ht := tracker as XRHandTracker
	# HAND_JOINT_THUMB_TIP = 5, HAND_JOINT_INDEX_TIP = 10
	# HAND_JOINT_FLAG_POSITION_VALID = 4
	if not (ht.get_hand_joint_flags(5) & 4) or not (ht.get_hand_joint_flags(10) & 4):
		return

	var thumb_pos := ht.get_hand_joint_transform(5).origin
	var index_pos := ht.get_hand_joint_transform(10).origin
	var is_pinching := thumb_pos.distance_to(index_pos) < pinch_threshold

	if is_left:
		if is_pinching and not _left_pinching:
			prev_requested.emit()
		_left_pinching = is_pinching
	else:
		if is_pinching and not _right_pinching:
			next_requested.emit()
		_right_pinching = is_pinching
