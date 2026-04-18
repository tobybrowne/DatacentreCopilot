class_name ContextMenu
extends Control

signal item_selected(index: int, label: String)

@onready var _add_note: Button = $VBoxContainer/AddNote


func _ready() -> void:
	_add_note.pressed.connect(func() -> void: item_selected.emit(0, "Add Sticky Note"))
