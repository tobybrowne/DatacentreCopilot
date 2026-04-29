class_name AssetFab
extends BasePanel

signal info_requested

const _ICON_BASE := "res://ui/standalone/asset_fab/icons/"

var _btn: Button


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


func setup(asset_type: String) -> void:
	var path := _ICON_BASE + asset_type + ".svg"
	if ResourceLoader.exists(path):
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
