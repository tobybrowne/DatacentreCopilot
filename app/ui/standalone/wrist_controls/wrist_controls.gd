extends Control

signal prev_requested
signal next_requested

const _CONFIRM_TIMEOUT := 3.0

var _state: String = "hold"
var _pending: String = ""
var _confirm_timer := 0.0

var _hold_view: Control
var _progress: Control
var _nav_view: HBoxContainer
var _confirm_view: Button


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_hold_view()
	_build_nav_view()
	_build_confirm_view()


func _build_hold_view() -> void:
	_hold_view = Control.new()
	_hold_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hold_view)

	var btn := Button.new()
	btn.icon = load("res://icons/foreground_192x192.png")
	btn.expand_icon = false
	btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	btn.add_theme_constant_override("icon_max_width", 85)
	btn.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	btn.offset_left = -60.0
	btn.offset_top = -60.0
	btn.offset_right = 60.0
	btn.offset_bottom = 60.0
	var style := StyleBoxFlat.new()
	style.corner_radius_top_left = 60
	style.corner_radius_top_right = 60
	style.corner_radius_bottom_left = 60
	style.corner_radius_bottom_right = 60
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
	_progress.offset_left = -66.0
	_progress.offset_top = -66.0
	_progress.offset_right = 66.0
	_progress.offset_bottom = 66.0
	_hold_view.add_child(_progress)


func _build_nav_view() -> void:
	_nav_view = HBoxContainer.new()
	_nav_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_nav_view.add_theme_constant_override("separation", 8)
	_nav_view.visible = false
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


func _build_confirm_view() -> void:
	_confirm_view = Button.new()
	_confirm_view.text = "Confirm?"
	_confirm_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_confirm_view.add_theme_font_size_override("font_size", 60)
	_confirm_view.visible = false
	_confirm_view.pressed.connect(_on_confirm_pressed)
	add_child(_confirm_view)


func _process(delta: float) -> void:
	if _state == "confirm":
		_confirm_timer -= delta
		if _confirm_timer <= 0.0:
			_reset()


func set_hold_progress(t: float) -> void:
	if _state != "hold":
		return
	_progress.progress = t
	if t >= 1.0:
		_show_nav()


func _on_prev_pressed() -> void:
	_pending = "prev"
	_confirm_timer = _CONFIRM_TIMEOUT
	_state = "confirm"
	_nav_view.visible = false
	_confirm_view.visible = true


func _on_next_pressed() -> void:
	_pending = "next"
	_confirm_timer = _CONFIRM_TIMEOUT
	_state = "confirm"
	_nav_view.visible = false
	_confirm_view.visible = true


func _on_confirm_pressed() -> void:
	var action := _pending
	_reset()
	if action == "prev":
		prev_requested.emit()
	else:
		next_requested.emit()


func _show_nav() -> void:
	_state = "nav"
	_hold_view.visible = false
	_nav_view.visible = true
	_confirm_view.visible = false


func reset() -> void:
	_reset()


func _reset() -> void:
	_pending = ""
	_confirm_timer = 0.0
	_confirm_view.visible = false
	_hold_view.visible = true
	_nav_view.visible = false
	_state = "hold"
	_progress.progress = 0.0
