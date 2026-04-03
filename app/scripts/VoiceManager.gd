# Voice manager wraps the MLVoiceIntentManager GDExtension (native ML2 voice API).
# Register phrases via the `intents` export, then connect to the typed signals below.
# Falls back to no-op gracefully when the GDExtension is unavailable (e.g. in-editor).

class_name VoiceManager
extends Node

@export var intents: PackedStringArray = ["next step", "previous step", "confirm", "cancel"]

signal next_step
signal previous_step
signal confirm
signal cancel
signal voice_error(error: String)

var _voice: MLVoiceIntentManager = null


func _ready() -> void:
	_voice = MLVoiceIntentManager.new()
	add_child(_voice)

	if not _voice.is_available():
		push_warning("VoiceManager: ML2 voice API not available")
		return

	_voice.intents = intents
	_voice.voice_intent.connect(_on_intent)
	_voice.voice_error.connect(_on_error)
	_voice.configure_and_start()


func stop() -> void:
	if _voice:
		_voice.stop()


func _on_intent(intent_name: String, intent_id: int) -> void:
	var lower := intent_name.to_lower()
	match lower:
		"next step":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			next_step.emit()
		"previous step":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			previous_step.emit()
		"confirm":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			confirm.emit()
		"cancel":
			print("VoiceManager: recognized intent '%s'" % intent_name)
			cancel.emit()
		_:
			push_warning("VoiceManager: unhandled intent '%s'" % intent_name)


func _on_error(error: String) -> void:
	print("VoiceManager: voice error '%s'" % error)
	voice_error.emit(error)
