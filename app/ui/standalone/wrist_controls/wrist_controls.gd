extends Control

signal home_requested

var _state: String = "hold"
var _hold_view: Control
var _progress: Control


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hold_view()


func _build_hold_view() -> void:
	_hold_view = Control.new()
	_hold_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hold_view)

	var btn := Button.new()
	btn.icon = load("res://icons/foreground_192x192.png")
	btn.expand_icon = false
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", 105)
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	btn.offset_left = -75.0
	btn.offset_top = -75.0
	btn.offset_right = 75.0
	btn.offset_bottom = 75.0
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 75
	style.corner_radius_top_right = 75
	style.corner_radius_bottom_left = 75
	style.corner_radius_bottom_right = 75
	style.bg_color = Color(0.25, 0.25, 0.25, 1.0)
	btn.add_theme_stylebox_override("normal", style)
	btn.add_theme_stylebox_override("hover", style)
	btn.add_theme_stylebox_override("focus", style)
	var style_pressed := style.duplicate()
	style_pressed.bg_color = Color(0.45, 0.45, 0.45, 1.0)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	btn.add_theme_stylebox_override("hover_pressed", style_pressed)
	_hold_view.add_child(btn)

	_progress = load("res://ui/standalone/wrist_controls/arc_progress.gd").new()
	_progress.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_progress.offset_left = -82.0
	_progress.offset_top = -82.0
	_progress.offset_right = 82.0
	_progress.offset_bottom = 82.0
	_hold_view.add_child(_progress)


func set_hold_progress(t: float) -> void:
	if _state != "hold":
		return
	_progress.progress = t
	if t >= 1.0:
		_reset()
		home_requested.emit()


func reset() -> void:
	_reset()


func _reset() -> void:
	_state = "hold"
	_progress.progress = 0.0
