class_name StepViewer
extends BasePanel

@onready var _counter: Label = $MarginContainer/VBoxContainer/StepCounter
@onready var _text: Label = $MarginContainer/VBoxContainer/StepText
@onready var _timer_display: PanelContainer = $MarginContainer/VBoxContainer/TimerDisplay
@onready var _timer_label: Label = $MarginContainer/VBoxContainer/TimerDisplay/TimerLabel
@onready var _replay_btn: Button = $MarginContainer/VBoxContainer/ReplayButton
@onready var _countdown: Timer = $CountdownTimer

signal step_changed(prev_step: Step, next_step: Step)
signal replay_requested

var _steps: Array[Step] = []
var _current: int = 0
var _active_goto := false

var _timer_remaining: float = 0.0
var _timer_target_uuid: String = ""
var _timer_expired: bool = false
var _flash_accum: float = 0.0


func _ready() -> void:
	_replay_btn.pressed.connect(replay_requested.emit)


func show_replay_button(has_log: bool) -> void:
	_replay_btn.visible = has_log


func init(data: Dictionary) -> void:
	var procedure: Procedure = data.get("procedure")
	if procedure:
		_steps = procedure.steps
		_current = 0
		_stop_timer()
		_refresh(null)


func next_step() -> void:
	if _current < _steps.size() - 1:
		var prev := _steps[_current]
		_current += 1
		_refresh(prev)


func prev_step() -> void:
	if _current > 0:
		var prev := _steps[_current]
		_current -= 1
		_refresh(prev)


func _refresh(prev_step: Step) -> void:
	if _steps.is_empty():
		_counter.text = ""
		_text.text = ""
		return

	var step: Step = _steps[_current]
	step_changed.emit(prev_step, step)
	_counter.text = "Step %d / %d" % [_current + 1, _steps.size()]
	_text.text = step.text
	SpeakManager.speak("Step %d: %s" % [_current + 1, step.text])

	if step.type == Step.TYPE_GOTO:
		_active_goto = true
		PanelRouter.request("goto_step", {"anchor_id": step.anchor_id})
	elif _active_goto:
		_active_goto = false
		PanelRouter.request("goto_cleared", {})

	# Dismiss timer if we've reached its target step
	if not _timer_target_uuid.is_empty() and step.id == _timer_target_uuid:
		_stop_timer()

	# Start a new timer if this step has one
	if step.has_timer():
		_start_timer(step.timer_duration, step.timer_target_uuid)


func _process(delta: float) -> void:
	if _countdown.is_stopped() or _timer_expired:
		if _timer_expired:
			_flash_accum += delta
			_timer_display.modulate = Color.RED if fmod(_flash_accum, 0.6) < 0.3 else Color.WHITE
		return

	_timer_remaining = _countdown.time_left
	_timer_label.text = _format_time(_timer_remaining)


func _start_timer(duration: float, target_uuid: String) -> void:
	_timer_target_uuid = target_uuid
	_timer_remaining = duration
	_timer_expired = false
	_flash_accum = 0.0
	_timer_display.modulate = Color.WHITE
	_timer_display.visible = true
	_timer_label.text = _format_time(duration)
	_countdown.start(duration)
	_countdown.timeout.connect(_on_timer_expired, CONNECT_ONE_SHOT)


func _stop_timer() -> void:
	_countdown.stop()
	_timer_target_uuid = ""
	_timer_expired = false
	_timer_display.visible = false
	_timer_label.text = ""


func _on_timer_expired() -> void:
	_timer_expired = true
	_timer_label.text = "Time ran out"
	SpeakManager.speak("Time ran out")


func _format_time(seconds: float) -> String:
	var s := int(seconds)
	return "%d:%02d" % [s / 60, s % 60]


func _exit_tree() -> void:
	SpeakManager.stop()
	_stop_timer()
	if _active_goto:
		_active_goto = false
		PanelRouter.request("goto_cleared", {})
