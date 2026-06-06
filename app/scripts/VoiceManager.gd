# Voice manager wraps the MLVoiceIntentManager GDExtension (native ML2 voice API).
# Register phrases via the `intents` export, then connect to the typed signals below.
# Falls back to no-op gracefully when the GDExtension is unavailable (e.g. in-editor).

class_name VoiceManager
extends Node

@export var intents: PackedStringArray = ["copilot"]

signal copilot
signal show_map
signal voice_error(error: String)

var _voice: Node = null


func _ready() -> void:
	if not ClassDB.class_exists("MLVoiceIntentManager"):
		push_warning("VoiceManager: ML2 voice API not available (desktop/simulator)")
		return
	_voice = ClassDB.instantiate("MLVoiceIntentManager")
	add_child(_voice)

	if not _voice.is_available():
		push_warning("VoiceManager: ML2 voice API not available")
		return

	if DevConfig.DOLLHOUSE_MAP_VOICE_SHORTCUT and "show map" not in intents:
		intents.append("show map")

	_voice.intents = intents
	_voice.voice_intent.connect(_on_intent)
	_voice.voice_error.connect(_on_error)
	_voice.configure_and_start()


func stop() -> void:
	if _voice:
		_voice.stop()


func _on_intent(intent_name: String, _intent_id: int) -> void:
	print("VoiceManager: _on_intent called intent='%s'" % intent_name)
	var lower := intent_name.to_lower()
	match lower:
		"copilot":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			copilot.emit()
		"show map":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			show_map.emit()
		_:
			push_warning("VoiceManager: unhandled intent '%s'" % intent_name)


func _on_error(error: String) -> void:
	print("VoiceManager: voice error '%s'" % error)
	voice_error.emit(error)
