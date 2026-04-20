extends Control

signal prev_requested
signal next_requested

const _CONFIRM_TIMEOUT := 3.0

var _pending: String = ""  # "prev" or "next"
var _timer := 0.0
var _nav_view: HBoxContainer
var _confirm_view: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_nav_view = HBoxContainer.new()
	_nav_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nav_view.add_theme_constant_override("separation", 8)
	add_child(_nav_view)

	var prev_btn := Button.new()
	prev_btn.text = "◀"
	prev_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prev_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	prev_btn.add_theme_font_size_override("font_size", 80)
	prev_btn.pressed.connect(_on_prev_pressed)
	_nav_view.add_child(prev_btn)

	var next_btn := Button.new()
	next_btn.text = "▶"
	next_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	next_btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	next_btn.add_theme_font_size_override("font_size", 80)
	next_btn.pressed.connect(_on_next_pressed)
	_nav_view.add_child(next_btn)

	_confirm_view = Button.new()
	_confirm_view.text = "Confirm?"
	_confirm_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_view.add_theme_font_size_override("font_size", 60)
	_confirm_view.visible = false
	_confirm_view.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_view)


func _process(delta: float) -> void:
	if not _pending.is_empty():
		_timer -= delta
		if _timer <= 0.0:
			_reset()


func _on_prev_pressed() -> void:
	_pending = "prev"
	_timer = _CONFIRM_TIMEOUT
	_nav_view.visible = false
	_confirm_view.visible = true


func _on_next_pressed() -> void:
	_pending = "next"
	_timer = _CONFIRM_TIMEOUT
	_nav_view.visible = false
	_confirm_view.visible = true


func _on_confirm_pressed() -> void:
	var action := _pending
	_reset()
	if action == "prev":
		prev_requested.emit()
	else:
		next_requested.emit()


func _reset() -> void:
	_pending = ""
	_timer = 0.0
	_confirm_view.visible = false
	_nav_view.visible = true
