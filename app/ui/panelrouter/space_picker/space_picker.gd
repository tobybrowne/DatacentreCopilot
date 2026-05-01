extends BasePanel

@onready var _scroll: ScrollContainer = $MarginContainer/VBoxContainer/ScrollContainer
@onready var _item_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $MarginContainer/VBoxContainer/Status

var _spaces: Array[Space] = []
var _mode := ""
var _space_manager: SpaceManager


func init(data: Dictionary) -> void:
	_spaces = data.get("spaces", [])
	_mode = data.get("mode", "")
	_space_manager = data.get("space_manager")
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
	var row := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	row.add_child(hbox)

	var name_label := Label.new()
	name_label.text = space.name if not space.name.is_empty() else "(unnamed)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	hbox.add_child(name_label)

	var is_local := _space_manager.is_space_local(space.id) if _space_manager else false

	var local_badge := Label.new()
	local_badge.text = "local" if is_local else ""
	local_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	local_badge.add_theme_font_size_override("font_size", FONT_SMALL)
	local_badge.modulate = Color(0.4, 1.0, 0.4)
	hbox.add_child(local_badge)

	var pin_btn := Button.new()
	pin_btn.text = ""
	pin_btn.icon = load("res://ui/panelrouter/space_picker/icon_pin.svg")
	pin_btn.pressed.connect(_on_localise_pressed.bind(space))
	hbox.add_child(pin_btn)

	_item_list.add_child(row)


func _on_localise_pressed(space: Space) -> void:
	_scroll.visible = false
	_back_button.disabled = true
	_status.text = "Localising…"

	if _mode == "start_navigate":
		PanelRouter.request("start_nav_for_space", { "space": space })
	elif _mode == "procedure":
		PanelRouter.request("start_nav_for_procedure", { "space": space })
	else:
		PanelRouter.request("localise_space", { "space": space })
