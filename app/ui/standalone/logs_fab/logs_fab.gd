class_name LogsFab
extends BasePanel

signal logs_requested


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

	var btn := Button.new()
	btn.text = "≡"
	btn.add_theme_font_size_override("font_size", 48)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_color_override("font_hover_color", Color.WHITE)
	btn.add_theme_color_override("font_pressed_color", Color.WHITE)
	btn.add_theme_color_override("font_focus_color", Color.WHITE)
	btn.add_theme_stylebox_override("normal", circle_style)
	btn.add_theme_stylebox_override("hover", hover_style)
	btn.add_theme_stylebox_override("pressed", pressed_style)
	btn.add_theme_stylebox_override("focus", circle_style)
	btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	btn.pressed.connect(logs_requested.emit)
	add_child(btn)
