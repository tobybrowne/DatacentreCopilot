class_name FpsIndicator
extends Node3D

const _POSITION      := Vector3(0.114, 0.07, -0.3)
const _UPDATE_INTERVAL := 0.25

var _label: Label3D
var _timer := 0.0


func _ready() -> void:
	position = _POSITION
	_label = Label3D.new()
	_label.font_size  = 8
	_label.pixel_size = 0.001
	_label.billboard  = BaseMaterial3D.BILLBOARD_DISABLED
	_label.no_depth_test = true
	_label.modulate   = Color(0.5, 0.5, 0.5)
	_label.text       = "--"
	add_child(_label)


func _process(delta: float) -> void:
	_timer += delta
	if _timer < _UPDATE_INTERVAL:
		return
	_timer = 0.0
	var fps := Engine.get_frames_per_second()
	_label.text = "%d" % fps
	if fps >= 50:
		_label.modulate = Color(0.0, 1.0, 0.2)
	elif fps >= 30:
		_label.modulate = Color(1.0, 0.55, 0.0)
	else:
		_label.modulate = Color(1.0, 0.2, 0.2)
