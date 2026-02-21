extends Control

signal prev_requested
signal next_requested


func _ready() -> void:
	$HBoxContainer/PrevButton.pressed.connect(prev_requested.emit)
	$HBoxContainer/NextButton.pressed.connect(next_requested.emit)
