class_name BasePanel
extends Control

const FONT_TITLE  := 32
const FONT_BODY   := 24
const FONT_SMALL  := 18
const COLOR_ACCENT := Color("#00d4ff")
const COLOR_BG     := Color(0.15, 0.15, 0.22, 0.95)
const COLOR_TEXT   := Color(0.9, 0.9, 1.0)
const COLOR_ROW_HOVER  := Color(1.2, 1.2, 1.2)
const COLOR_ROW_PRESS  := Color(0.6, 1.0, 0.6)

signal navigate_to(panel_id: String, data: Dictionary)
signal close_requested

const _BTN_PAD_V := 20
const _BTN_PAD_H := 14
const _BTN_RADIUS := 6
const _BACK_BTN_W := 140

func _enter_tree() -> void:
	var bg := get_node_or_null("Background") as ColorRect
	if bg:
		bg.color = COLOR_BG
	theme = _build_theme()


static func _btn_style(bg: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_corner_radius_all(_BTN_RADIUS)
	s.content_margin_top    = _BTN_PAD_V
	s.content_margin_bottom = _BTN_PAD_V
	s.content_margin_left   = _BTN_PAD_H
	s.content_margin_right  = _BTN_PAD_H
	return s


static func _build_theme() -> Theme:
	var t := Theme.new()
	t.set_stylebox("normal",   "Button", _btn_style(Color(0.22, 0.22, 0.30, 0.95)))
	t.set_stylebox("hover",    "Button", _btn_style(Color(0.30, 0.30, 0.42, 0.95)))
	t.set_stylebox("pressed",  "Button", _btn_style(Color(0.15, 0.55, 0.38, 0.95)))
	t.set_stylebox("disabled", "Button", _btn_style(Color(0.18, 0.18, 0.24, 0.55)))
	t.set_stylebox("focus",    "Button", _btn_style(Color(0.22, 0.22, 0.30, 0.95)))
	var row_style := StyleBoxFlat.new()
	row_style.bg_color = Color(0.20, 0.20, 0.28, 0.85)
	row_style.set_corner_radius_all(_BTN_RADIUS)
	row_style.content_margin_top    = _BTN_PAD_V
	row_style.content_margin_bottom = _BTN_PAD_V
	row_style.content_margin_left   = _BTN_PAD_H
	row_style.content_margin_right  = _BTN_PAD_H
	t.set_stylebox("panel", "PanelContainer", row_style)
	return t

func _ready() -> void:
	var back := find_child("BackButton", true, false) as Button
	if back:
		back.pressed.connect(func(): close_requested.emit())
		back.custom_minimum_size.x = _BACK_BTN_W
		var top_bar := back.get_parent()
		if top_bar is HBoxContainer:
			var spacer := Control.new()
			spacer.custom_minimum_size.x = _BACK_BTN_W
			top_bar.add_child(spacer)


# Override in subclasses to receive route data on navigation
func init(_data: Dictionary) -> void:
	pass
