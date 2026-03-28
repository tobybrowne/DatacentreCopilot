# Gesture manager checks hand trackers for certain events
# when detected, it emits signals with relevant data for other nodes to react to

class_name GestureManager
extends Node

@export var pinch_threshold: float = 0.02
@export var hold_time: float = 3.0

# signals emitted
signal pinch_started(hand: String, position: Vector3)
signal pinch_ended(hand: String)
signal pinch_held(hand: String, position: Vector3, duration: float)
signal pinch_completed(hand: String, position: Vector3)

const _TRACKERS := {
	"left": "/user/hand_tracker/left",
	"right": "/user/hand_tracker/right",
}

var _pinching := {"left": false, "right": false}
var _hold_time := {"left": 0.0, "right": 0.0}
var _fired := {"left": false, "right": false}


func _process(delta: float) -> void:
	for hand in _TRACKERS:
		_check_hand(hand, delta)


func _check_hand(hand: String, delta: float) -> void:
	var tracker := XRServer.get_tracker(_TRACKERS[hand])
	if not tracker or not tracker is XRHandTracker:
		_end(hand)
		return

	var ht := tracker as XRHandTracker
	if not (ht.get_hand_joint_flags(5) & 4) or not (ht.get_hand_joint_flags(10) & 4):
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
		pinch_started.emit(hand, pinch_pos)

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
		pinch_ended.emit(hand)
