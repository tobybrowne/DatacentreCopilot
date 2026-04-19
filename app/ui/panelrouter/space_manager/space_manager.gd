extends BasePanel

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $VBoxContainer/Status
@onready var _back_button: Button = $VBoxContainer/TopBar/BackButton


func init(_data: Dictionary) -> void:
	_back_button.pressed.connect(func(): close_requested.emit())
	call_deferred("_load_spaces")


func _load_spaces() -> void:
	_status.text = "Loading..."
	_item_list.visible = false

	var spaces: Array[Space] = await SupabaseManager.get_spaces()

	_status.text = ""
	_item_list.visible = true

	for child in _item_list.get_children():
		child.queue_free()

	if spaces.is_empty():
		_status.text = "No spaces found."
		return

	for space in spaces:
		_add_row(space)


func _on_row_input(event: InputEvent, space: Space, row: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		row.modulate = COLOR_ROW_PRESS
		navigate_to.emit("space_info", { "space": space })


func _add_row(space: Space) -> void:
	var row := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)

	var name_label := Label.new()
	name_label.text = space.name if not space.name.is_empty() else "(unnamed)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	hbox.add_child(name_label)

	var id_label := Label.new()
	id_label.text = space.id.substr(0, 8) + "…"
	id_label.add_theme_font_size_override("font_size", FONT_SMALL)
	id_label.modulate = Color(0.6, 0.6, 0.6)
	hbox.add_child(id_label)

	row.mouse_entered.connect(func(): row.modulate = COLOR_ROW_HOVER)
	row.mouse_exited.connect(func(): row.modulate = Color.WHITE)
	row.gui_input.connect(_on_row_input.bind(space, row))
	_item_list.add_child(row)
