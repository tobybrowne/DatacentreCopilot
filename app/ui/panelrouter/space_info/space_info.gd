extends BasePanel

@onready var _name_label: Label      = $MarginContainer/VBoxContainer/Name
@onready var _id_label: Label        = $MarginContainer/VBoxContainer/Id
@onready var _local_label: Label     = $MarginContainer/VBoxContainer/Local
@onready var _created_label: Label   = $MarginContainer/VBoxContainer/Created
@onready var _updated_label: Label   = $MarginContainer/VBoxContainer/Updated
@onready var _update_button: Button  = $MarginContainer/VBoxContainer/Buttons/UpdateButton
@onready var _calibrate_button: Button = $MarginContainer/VBoxContainer/Buttons/CalibrateButton

var _space: Space


func init(data: Dictionary) -> void:
	_space = data.get("space")
	if not _space:
		return

	_name_label.text = _space.name if not _space.name.is_empty() else "(unnamed)"
	_id_label.text = "ID: " + _space.id
	_created_label.text = "Created: " + _format_time(_space.created_at)
	_updated_label.text = "Updated: " + _format_time(_space.updated_at)

	var is_local := _check_local(_space.id)
	_local_label.text = "Local: " + ("Yes" if is_local else "No")
	_local_label.modulate = Color("#00ff88") if is_local else Color("#ff4444")

	_update_button.pressed.connect(_on_update_pressed)
	_calibrate_button.pressed.connect(_on_calibrate_pressed)


func _on_calibrate_pressed() -> void:
	_calibrate_button.text = "Loading..."
	_calibrate_button.disabled = true
	PanelRouter.request("localise_space_load_anchors", { "space": _space })


func _on_update_pressed() -> void:
	PanelRouter.request("update_space", { "space": _space })


func _check_local(space_id: String) -> bool:
	if not Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return false
	var ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension")
	for map in ext.get_localization_maps():
		if map.get("uuid", "") == space_id:
			return true
	return false


func _format_time(iso: String) -> String:
	if iso.is_empty():
		return "Unknown"
	var parts := iso.split("T")
	if parts.size() < 2:
		return iso
	return parts[0] + "  " + parts[1].substr(0, 5)
