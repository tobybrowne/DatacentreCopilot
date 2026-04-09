class_name BasePanel
extends Control

const FONT_TITLE  := 32
const FONT_BODY   := 24
const FONT_SMALL  := 18
const COLOR_ACCENT := Color("#00d4ff")
const COLOR_BG     := Color(0.08, 0.08, 0.15, 0.95)
const COLOR_TEXT   := Color(0.9, 0.9, 1.0)
const COLOR_ROW_HOVER  := Color(1.2, 1.2, 1.2)
const COLOR_ROW_PRESS  := Color(0.6, 1.0, 0.6)

signal navigate_to(panel_id: String, data: Dictionary)
signal close_requested

# Override in subclasses to receive route data on navigation
func init(_data: Dictionary) -> void:
	pass
