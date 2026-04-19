extends BasePanel

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $VBoxContainer/Status


func init(_data: Dictionary) -> void:
	call_deferred("_load_buildings")


func _load_buildings() -> void:
	_status.text = "Loading..."
	_item_list.visible = false

	var buildings: Array[Building] = await SupabaseManager.get_buildings()

	_status.text = ""
	_item_list.visible = true

	for child in _item_list.get_children():
		child.queue_free()

	if buildings.is_empty():
		_status.text = "No buildings found."
		return

	for building in buildings:
		_add_row(building)


func _add_row(building: Building) -> void:
	var row := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)

	var name_label := Label.new()
	name_label.text = building.name if not building.name.is_empty() else "(unnamed)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	hbox.add_child(name_label)

	if building.draft:
		var draft_label := Label.new()
		draft_label.text = "draft"
		draft_label.add_theme_font_size_override("font_size", FONT_SMALL)
		draft_label.modulate = Color(1.0, 0.6, 0.2)
		hbox.add_child(draft_label)

	row.mouse_entered.connect(func(): row.modulate = COLOR_ROW_HOVER)
	row.mouse_exited.connect(func(): row.modulate = Color.WHITE)
	row.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed:
			row.modulate = COLOR_ROW_PRESS
			navigate_to.emit("building_info", { "building": building }))
	_item_list.add_child(row)
