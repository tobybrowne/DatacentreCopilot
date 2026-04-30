class_name SpaceLabel
extends BasePanel

@onready var _coarse_label: Label = $MarginContainer/VBoxContainer/CoarseLabel
@onready var _active_label: Label = $MarginContainer/VBoxContainer/ActiveLabel


func update_coarse(space_id: String) -> void:
	_coarse_label.text = space_id


func update_localised(space_id: String) -> void:
	_active_label.text = "active: " + space_id
