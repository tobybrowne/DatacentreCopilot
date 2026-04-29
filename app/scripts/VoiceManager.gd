# Voice manager wraps the MLVoiceIntentManager GDExtension (native ML2 voice API).
# Register phrases via the `intents` export, then connect to the typed signals below.
# Falls back to no-op gracefully when the GDExtension is unavailable (e.g. in-editor).

# NOTE: this code is currently unused (we use the LLM copilot for voice commands)

class_name VoiceManager
extends Node

@export var intents: PackedStringArray = ["confirm", "cancel", "start recording", "stop recording", "go home"]

signal confirm
signal cancel
signal start_recording
signal stop_recording
signal go_home
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

	_voice.intents = intents
	_voice.voice_intent.connect(_on_intent)
	_voice.voice_error.connect(_on_error)


func stop() -> void:
	if _voice:
		_voice.stop()


func _on_intent(intent_name: String, _intent_id: int) -> void:
	var lower := intent_name.to_lower()
	match lower:
		"confirm":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			confirm.emit()
		"cancel":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			cancel.emit()
		"start recording":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			start_recording.emit()
		"stop recording":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			stop_recording.emit()
		"go home":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			go_home.emit()
		_:
			push_warning("VoiceManager: unhandled intent '%s'" % intent_name)


func _on_error(error: String) -> void:
	print("VoiceManager: voice error '%s'" % error)
	voice_error.emit(error)
