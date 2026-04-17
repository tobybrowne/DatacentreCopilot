extends Node

var _keyboard_3d: Node3D = null
var _current_callback: Callable


func register(keyboard_3d: Node3D) -> void:
	_keyboard_3d = keyboard_3d
	_keyboard_3d.visible = false


func open(prompt: String, initial_text: String, on_submit: Callable) -> void:
	if not _keyboard_3d:
		push_error("KeyboardManager: call KeyboardManager.register() from main.gd first")
		return

	_current_callback = on_submit

	var panel = _keyboard_3d.get_panel()
	if panel and panel.has_method("init"):
		panel.init({"prompt": prompt, "initial_text": initial_text})

	if panel:
		if panel.submitted.is_connected(_on_submitted):
			panel.submitted.disconnect(_on_submitted)
		if panel.cancelled.is_connected(_on_cancelled):
			panel.cancelled.disconnect(_on_cancelled)
		panel.submitted.connect(_on_submitted, CONNECT_ONE_SHOT)
		panel.cancelled.connect(_on_cancelled, CONNECT_ONE_SHOT)

	_keyboard_3d.visible = true


func close() -> void:
	if _keyboard_3d:
		_keyboard_3d.visible = false


func _on_submitted(text: String) -> void:
	close()
	if _current_callback.is_valid():
		_current_callback.call(text)


func _on_cancelled() -> void:
	close()
