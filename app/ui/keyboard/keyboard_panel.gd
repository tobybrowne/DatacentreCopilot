class_name KeyboardPanel
extends Control

signal submitted(text: String)
signal cancelled

@onready var _prompt_label: Label = $Header/VBox/PromptLabel
@onready var _text_display: Label = $Header/VBox/TextDisplay
@onready var _keyboard: CopilotKeyboard = $CopilotKeyboard


func _ready() -> void:
	_keyboard.text_changed.connect(func(text): _text_display.text = text)
	_keyboard.submitted.connect(func(text): submitted.emit(text))
	$Header/VBox/ButtonRow/CancelButton.pressed.connect(func(): cancelled.emit())
	$Header/VBox/ButtonRow/ConfirmButton.pressed.connect(
		func(): submitted.emit(_keyboard.current_text)
	)


func init(data: Dictionary) -> void:
	_prompt_label.text = data.get("prompt", "Enter text")
	var initial: String = data.get("initial_text", "")
	_text_display.text = initial
	_keyboard.set_initial_text(initial)
