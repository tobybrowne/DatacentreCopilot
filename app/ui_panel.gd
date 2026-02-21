extends ViewportPanel3D

const PanelScene = preload("res://ui_panel.tscn")


func _get_panel_scene() -> PackedScene:
	return PanelScene


func _on_panel_ready(panel: Control) -> void:
	var toggle_btn := panel.get_node("ColorRect/ToggleButton") as Button
	toggle_btn.toggled.connect(_on_toggle)


func _on_toggle(pressed: bool) -> void:
	var btn := _panel.get_node("ColorRect/ToggleButton") as Button
	btn.text = "Right >" if pressed else "< Left"
