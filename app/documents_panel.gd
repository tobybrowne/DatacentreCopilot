extends Control

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList


func _ready() -> void:
	call_deferred("load_documents", "documents")


func load_documents(table: String) -> void:
	var docs: Array[Dictionary] = await SupabaseManager.get_documents(table)
	_populate(docs)


func _populate(docs: Array[Dictionary]) -> void:
	for child in _item_list.get_children():
		child.queue_free()
	for doc in docs:
		_add_row(doc)


func _add_row(doc: Dictionary) -> void:
	var row := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 16)
	row.add_child(hbox)

	var title := Label.new()
	title.text = str(doc.get("title", "Untitled"))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 26)
	hbox.add_child(title)

	var time := Label.new()
	time.text = _format_time(str(doc.get("created_at", "")))
	time.add_theme_font_size_override("font_size", 22)
	hbox.add_child(time)

	_item_list.add_child(row)


func _format_time(iso: String) -> String:
	if iso.is_empty():
		return ""
	var parts := iso.split("T")
	if parts.size() < 2:
		return iso
	return parts[0] + "  " + parts[1].substr(0, 5)
