extends ViewportPanel3D

const PanelScene = preload("res://procedure_panel.tscn")

signal procedure_selected(procedure: Procedure)


func _get_panel_scene() -> PackedScene:
	return PanelScene


func _on_panel_ready(panel: Control) -> void:
	panel.procedure_selected.connect(procedure_selected.emit)
