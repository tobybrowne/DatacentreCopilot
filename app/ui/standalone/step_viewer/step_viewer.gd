class_name StepViewer
extends BasePanel

@onready var _counter: Label = $MarginContainer/VBoxContainer/StepCounter
@onready var _text: Label = $MarginContainer/VBoxContainer/StepText

var _steps: Array[Step] = []
var _current: int = 0
var _active_goto := false


func init(data: Dictionary) -> void:
	var procedure: Procedure = data.get("procedure")
	if procedure:
		_steps = procedure.steps
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

	var step: Step = _steps[_current]
	_counter.text = "Step %d / %d" % [_current + 1, _steps.size()]
	_text.text = step.text
	SpeakManager.speak("Step %d: %s" % [_current + 1, step.text])

	if step.type == Step.TYPE_GOTO:
		_active_goto = true
		PanelRouter.request("goto_step", {"anchor_id": step.anchor_id})
	elif _active_goto:
		_active_goto = false
		PanelRouter.request("goto_cleared", {})


func _exit_tree() -> void:
	SpeakManager.stop()
	if _active_goto:
		_active_goto = false
		PanelRouter.request("goto_cleared", {})
