extends Node

var enabled := true

var _voice := ""


func _ready() -> void:
	for v in DisplayServer.tts_get_voices():
		if (v.get("language", "") as String).begins_with("en"):
			_voice = v.get("id", "")
			break


func speak(text: String) -> void:
	if not enabled or _voice.is_empty() or text.is_empty():
		return
	DisplayServer.tts_speak(text, _voice, 80, 1.0, 1.0, 0, true)


func stop() -> void:
	DisplayServer.tts_stop()
