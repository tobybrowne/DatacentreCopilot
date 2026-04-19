extends BasePanel

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $VBoxContainer/Status
@onready var _back_button: Button = $VBoxContainer/TopBar/BackButton

var _spaces: Array[Space] = []
var _mode := ""


func init(data: Dictionary) -> void:
	_back_button.pressed.connect(func(): close_requested.emit())
	_spaces = data.get("spaces", [])
	_mode = data.get("mode", "")
	call_deferred("_populate")


func _populate() -> void:
	for child in _item_list.get_children():
		child.queue_free()

	if _spaces.is_empty():
		_status.text = "No spaces available."
		return

	_status.text = ""
	for space in _spaces:
		_add_row(space)


func _add_row(space: Space) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)

	var name_label := Label.new()
	name_label.text = space.name if not space.name.is_empty() else "(unnamed)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(name_label)

	var is_local := _is_local(space.id)

	var local_badge := Label.new()
	local_badge.text = "local" if is_local else ""
	local_badge.add_theme_font_size_override("font_size", FONT_SMALL)
	local_badge.modulate = Color(0.4, 1.0, 0.4)
	row.add_child(local_badge)

	var pin_btn := Button.new()
	pin_btn.text = "📍"
	pin_btn.add_theme_font_size_override("font_size", FONT_BODY)
	pin_btn.pressed.connect(_on_localise_pressed.bind(space, pin_btn))
	row.add_child(pin_btn)

	_item_list.add_child(row)


func _on_localise_pressed(space: Space, btn: Button) -> void:
	btn.disabled = true
	btn.text = "…"
	if _mode == "navigate":
		PanelRouter.request("start_nav_for_space", { "space": space })
	elif _mode == "procedure":
		PanelRouter.request("start_nav_for_procedure", { "space": space })
	else:
		PanelRouter.request("localise_space", { "space": space })


func _is_local(space_id: String) -> bool:
	if not Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return false
	var maps: Array = Engine.get_singleton("OpenXRMlLocalizationMapExtension").get_localization_maps()
	for m in maps:
		if m.get("uuid", "") == space_id:
			return true
	return false
