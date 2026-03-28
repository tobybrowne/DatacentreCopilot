extends Control

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList

signal procedure_selected(procedure: Procedure)


func _ready() -> void:
	call_deferred("load_procedures")


func load_procedures() -> void:
	var procedures: Array[Procedure] = await SupabaseManager.get_procedures()
	_populate(procedures)


func _populate(procedures: Array[Procedure]) -> void:
	for child in _item_list.get_children():
		child.queue_free()
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
	title.add_theme_font_size_override("font_size", 26)
	hbox.add_child(title)

	var time := Label.new()
	time.text = _format_time(procedure.created_at)
	time.add_theme_font_size_override("font_size", 22)
	hbox.add_child(time)

	# Visual feedback
	row.mouse_entered.connect(func(): row.modulate = Color(1.4, 1.4, 1.4))
	row.mouse_exited.connect(func(): row.modulate = Color(1.0, 1.0, 1.0))
	row.gui_input.connect(_on_row_input.bind(procedure, row))
	_item_list.add_child(row)


func _on_row_input(event: InputEvent, procedure: Procedure, row: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		row.modulate = Color(0.6, 1.0, 0.6)
		procedure_selected.emit(procedure)


func _format_time(iso: String) -> String:
	if iso.is_empty():
		return ""
	var parts := iso.split("T")
	if parts.size() < 2:
		return iso
	return parts[0] + "  " + parts[1].substr(0, 5)
