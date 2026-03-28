class_name StepViewer
extends Control

@onready var _counter: Label = $MarginContainer/VBoxContainer/StepCounter
@onready var _text: Label = $MarginContainer/VBoxContainer/StepText

var _steps: Array[String] = []
var _current: int = 0


func setup(steps: Array[String]) -> void:
	_steps = steps
	_current = 0
	_refresh()


func next_step() -> void:
	if _current < _steps.size() - 1:
		_current += 1
		_refresh()


func prev_step() -> void:
	if _current > 0:
		_current -= 1
		_refresh()


func _refresh() -> void:
	if _steps.is_empty():
		_counter.text = ""
		_text.text = ""
		return
	_counter.text = "Step %d / %d" % [_current + 1, _steps.size()]
	_text.text = _steps[_current]
