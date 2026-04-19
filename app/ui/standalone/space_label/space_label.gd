class_name SpaceLabel
extends BasePanel

@onready var _coarse_label: Label = $MarginContainer/VBoxContainer/CoarseLabel
@onready var _active_label: Label = $MarginContainer/VBoxContainer/ActiveLabel


func update(coarse_id: String, active_id: String) -> void:
	_coarse_label.text = coarse_id
	_active_label.text = "active: " + active_id
