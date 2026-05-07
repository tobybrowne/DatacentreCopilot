class_name AssetFab
extends BasePanel

signal info_requested

const _ICON_BASE := "res://ui/standalone/asset_fab/icons/"

var _btn: Button
var _alarm_ring: Control = null
var _alarm := false
var _pulse_t := 0.0


func _ready() -> void:
	var circle_style := StyleBoxFlat.new()
	circle_style.bg_color = Color(0.22, 0.22, 0.30, 0.95)
	circle_style.set_corner_radius_all(60)

	var hover_style := StyleBoxFlat.new()
	hover_style.bg_color = Color(0.30, 0.30, 0.42, 0.95)
	hover_style.set_corner_radius_all(60)

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = Color(0.18, 0.18, 0.26, 0.95)
	pressed_style.set_corner_radius_all(60)

	_btn = Button.new()
	_btn.add_theme_stylebox_override("normal", circle_style)
	_btn.add_theme_stylebox_override("hover", hover_style)
	_btn.add_theme_stylebox_override("pressed", pressed_style)
	_btn.add_theme_stylebox_override("focus", circle_style)
	_btn.expand_icon = false
	_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_btn.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	_btn.add_theme_constant_override("icon_max_width", 72)
	_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_btn.pressed.connect(info_requested.emit)
	add_child(_btn)

	# Added after button so it renders on top
	_alarm_ring = Control.new()
	_alarm_ring.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_alarm_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_alarm_ring.visible = false
	_alarm_ring.draw.connect(_draw_ring)
	add_child(_alarm_ring)


func _process(delta: float) -> void:
	if _alarm:
		_pulse_t += delta
		_alarm_ring.queue_redraw()


func _draw_ring() -> void:
	var cx    := _alarm_ring.size.x * 0.5
	var cy    := _alarm_ring.size.y * 0.5
	var r     := minf(cx, cy) - 3.0
	var alpha := 0.5 + 0.5 * sin(_pulse_t * TAU * 1.2)
	_alarm_ring.draw_arc(Vector2(cx, cy), r, 0.0, TAU, 64, Color(1.0, 0.15, 0.15, alpha), 4.0, true)


func set_alarm(active: bool) -> void:
	_alarm = active
	_alarm_ring.visible = active
	if not active:
		_pulse_t = 0.0
	_alarm_ring.queue_redraw()


func setup(asset_type: String) -> void:
	var path := AssetTypes.icon_path(asset_type)
	if not path.is_empty() and ResourceLoader.exists(path):
		_btn.icon = load(path)
	else:
		var lbl := Label.new()
		lbl.text = "ℹ"
		lbl.add_theme_font_size_override("font_size", 48)
		lbl.add_theme_color_override("font_color", Color.WHITE)
		lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_btn.add_child(lbl)
