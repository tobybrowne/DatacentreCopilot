extends ViewportPanel3D

const PanelScene = preload("res://step_viewer.tscn")


func _get_panel_scene() -> PackedScene:
	return PanelScene


func setup(steps: Array[String]) -> void:
	_panel.setup(steps)


func next_step() -> void:
	_panel.next_step()


func prev_step() -> void:
	_panel.prev_step()
