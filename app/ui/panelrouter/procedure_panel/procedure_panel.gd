extends BasePanel

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $VBoxContainer/Status


func _ready() -> void:
	super._ready()
	_status.text = "Loading..."
	call_deferred("load_procedures")


func load_procedures() -> void:
	var procedures: Array[Procedure] = await SupabaseManager.get_procedures()
	_populate(procedures)


func _populate(procedures: Array[Procedure]) -> void:
	for child in _item_list.get_children():
		child.queue_free()
	if procedures.is_empty():
		_status.text = "No procedures found."
		return
	_status.text = ""
	for procedure in procedures:
		_add_row(procedure)


func _add_row(procedure: Procedure) -> void:
	var row := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)

	var title := Label.new()
	title.text = procedure.title
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", FONT_BODY)
	hbox.add_child(title)

	var time := Label.new()
	time.text = _format_time(procedure.created_at)
	time.add_theme_font_size_override("font_size", FONT_SMALL)
	hbox.add_child(time)

	row.mouse_entered.connect(func(): row.modulate = COLOR_ROW_HOVER)
	row.mouse_exited.connect(func(): row.modulate = Color.WHITE)
	row.gui_input.connect(_on_row_input.bind(procedure, row))
	_item_list.add_child(row)


func _on_row_input(event: InputEvent, procedure: Procedure, row: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		row.modulate = COLOR_ROW_PRESS
		PanelRouter.request("start_procedure", { "procedure": procedure })


func _format_time(iso: String) -> String:
	if iso.is_empty():
		return ""
	var parts := iso.split("T")
	if parts.size() < 2:
		return iso
	return parts[0] + "  " + parts[1].substr(0, 5)
