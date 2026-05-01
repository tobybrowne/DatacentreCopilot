class_name SpaceLabel
extends BasePanel

@onready var _coarse_label: Label = $MarginContainer/VBoxContainer/CoarseLabel
@onready var _active_label: Label = $MarginContainer/VBoxContainer/ActiveLabel


func update_coarse(space_name: String) -> void:
	_coarse_label.text = "coarse: " + space_name


func update_localised(space_name: String) -> void:
	_active_label.text = "fine: " + space_name
