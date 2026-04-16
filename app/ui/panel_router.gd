extends Node

# Register all panel IDs and their 2D scene paths here
const SCENES: Dictionary = {
	"start_menu":    "res://ui/start_menu/start_menu.tscn",
	"procedures":    "res://ui/procedure_panel/procedure_panel.tscn",
	"step_viewer":   "res://ui/step_viewer/step_viewer.tscn",
	"map":            "res://ui/building_manager/building_manager.tscn",
	"building_info":  "res://ui/building_info/building_info.tscn",
	"space_manager": "res://ui/space_manager/space_manager.tscn",
	"space_info":    "res://ui/space_info/space_info.tscn",
	"space_picker":  "res://ui/space_picker/space_picker.tscn",
}

signal panel_changed(panel_id: String, data: Dictionary)
signal action_requested(action: String, data: Dictionary)

var _stack: Array[String] = []
var _data_stack: Array[Dictionary] = []


func push(panel_id: String, data: Dictionary = {}) -> void:
	_stack.push_back(panel_id)
	_data_stack.push_back(data)
	panel_changed.emit(panel_id, data)


func pop() -> void:
	if _stack.size() > 1:
		_stack.pop_back()
		_data_stack.pop_back()
		panel_changed.emit(_stack.back(), _data_stack.back())


func pop_to_root() -> void:
	if _stack.size() > 1:
		_stack.resize(1)
		_data_stack.resize(1)
		panel_changed.emit(_stack.back(), _data_stack.back())


func current() -> String:
	return _stack.back() if not _stack.is_empty() else ""

# for some reason (i forget) the ui panels can't access the scene tree, therefore they request actions through here
# main.gd listens for these requests and performs them in _on_panel_action
func request(action: String, data: Dictionary = {}) -> void:
	action_requested.emit(action, data)


func get_scene(panel_id: String) -> PackedScene:
	var path: String = SCENES.get(panel_id, "")
	if path.is_empty():
		push_error("PanelRouter: unknown panel '%s'" % panel_id)
		return null
	return load(path)
