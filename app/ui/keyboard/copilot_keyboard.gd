class_name CopilotKeyboard
extends XRToolsVirtualKeyboard2D

signal text_changed(text: String)
signal submitted(text: String)

var current_text: String = ""


func set_initial_text(text: String) -> void:
	current_text = text
	text_changed.emit(current_text)


func on_key_pressed(scan_code_text: String, unicode: int, shift: bool) -> void:
	var scan_code := OS.find_keycode_from_string(scan_code_text)

	match scan_code:
		KEY_BACKSPACE:
			if current_text.length() > 0:
				current_text = current_text.left(current_text.length() - 1)
		KEY_ENTER, KEY_KP_ENTER:
			submitted.emit(current_text)
			if _shift_down:
				_shift_down = false
				_update_visible()
			return
		_:
			if unicode > 0:
				current_text += char(unicode)

	text_changed.emit(current_text)

	if _shift_down:
		_shift_down = false
		_update_visible()
