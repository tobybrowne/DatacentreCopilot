extends BasePanel

@onready var _name_label: Label    = $MarginContainer/VBoxContainer/Name
@onready var _id_label: Label      = $MarginContainer/VBoxContainer/Id
@onready var _draft_label: Label   = $MarginContainer/VBoxContainer/Draft
@onready var _nav_button: Button   = $MarginContainer/VBoxContainer/Buttons/NavigateButton

var _building: Building


func init(data: Dictionary) -> void:
	_building = data.get("building")
	if not _building:
		return

	_name_label.text = _building.name if not _building.name.is_empty() else "(unnamed)"
	_id_label.text = "ID: " + _building.id
	_draft_label.text = "Draft" if _building.draft else "Published"
	_draft_label.modulate = Color(1.0, 0.6, 0.2) if _building.draft else Color(0.4, 1.0, 0.4)

	_nav_button.pressed.connect(_on_navigate_pressed)


func _on_navigate_pressed() -> void:
	_nav_button.text = "Finding location..."
	_nav_button.disabled = true
	PanelRouter.request("navigate", { "building_id": _building.id })
