extends BasePanel

@onready var _item_list: VBoxContainer = $MarginContainer/VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $MarginContainer/VBoxContainer/Status
@onready var _pull_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/PullButton
@onready var _push_btn: Button = $MarginContainer/VBoxContainer/ButtonRow/PushButton

var _space_manager: SpaceManager
var _remote_spaces: Array[Space] = []
var _local_only: Array[Space] = []


func init(data: Dictionary) -> void:
	_space_manager = data.get("space_manager")
	call_deferred("_load_spaces")


func _ready() -> void:
	super._ready()
	_pull_btn.pressed.connect(_on_pull_pressed)
	_push_btn.pressed.connect(_on_push_pressed)


func _load_spaces() -> void:
	_set_busy(true, "Loading...")

	_remote_spaces = await SupabaseManager.get_spaces()

	var remote_ids: Dictionary = {}
	for space in _remote_spaces:
		remote_ids[space.id] = true

	_local_only.clear()
	if _space_manager:
		for local_space in _space_manager.get_all_local_spaces():
			if not remote_ids.has(local_space.id):
				_local_only.append(local_space)

	_set_busy(false)
	_rebuild_list()


func _rebuild_list() -> void:
	for child in _item_list.get_children():
		child.queue_free()

	if _remote_spaces.is_empty() and _local_only.is_empty():
		_status.text = "No spaces found."
		return

	_status.text = ""
	for space in _remote_spaces:
		var is_local := _space_manager.is_space_local(space.id) if _space_manager else false
		_add_row(space, true, is_local)
	for space in _local_only:
		_add_row(space, false, true)


func _on_pull_pressed() -> void:
	if not _space_manager:
		return
	var to_import: Array[Space] = []
	for space in _remote_spaces:
		if not space.blob_path.is_empty() and not _space_manager.is_space_local(space.id):
			to_import.append(space)

	if to_import.is_empty():
		_status.text = "Nothing to pull."
		return

	_set_busy(true, "Pulling 0 / %d…" % to_import.size())
	_pull_btn.disabled = true
	_push_btn.disabled = true

	var done := 0
	for space in to_import:
		_status.text = "Pulling %d / %d: %s" % [done + 1, to_import.size(), space.name]
		await _space_manager.import_space(space)
		done += 1

	await _load_spaces()
	_status.text = "Pulled %d space(s)." % done
	_pull_btn.disabled = false
	_push_btn.disabled = false


func _on_push_pressed() -> void:
	if not _space_manager:
		return
	if _local_only.is_empty():
		_status.text = "Nothing to push."
		return

	var site_id := await SupabaseManager.get_user_site_id()
	if site_id.is_empty():
		_status.text = "Push failed: no site assigned to your account."
		return

	_set_busy(true, "Pushing 0 / %d…" % _local_only.size())
	_pull_btn.disabled = true
	_push_btn.disabled = true

	var done := 0
	for space in _local_only:
		space.site_id = site_id
		_status.text = "Pushing %d / %d: %s" % [done + 1, _local_only.size(), space.name]
		await _space_manager.export_space(space)
		done += 1

	await _load_spaces()
	_status.text = "Pushed %d space(s)." % done
	_pull_btn.disabled = false
	_push_btn.disabled = false


func _set_busy(busy: bool, msg: String = "") -> void:
	_status.text = msg
	_item_list.visible = not busy
	_pull_btn.disabled = busy
	_push_btn.disabled = busy


func _on_row_input(event: InputEvent, space: Space, row: PanelContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		row.modulate = COLOR_ROW_PRESS
		navigate_to.emit("space_info", { "space": space })


func _add_row(space: Space, is_remote: bool, is_local: bool) -> void:
	var row := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	row.add_child(hbox)

	var name_label := Label.new()
	name_label.text = space.name if not space.name.is_empty() else "(unnamed)"
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", FONT_BODY)
	hbox.add_child(name_label)

	var badges := HBoxContainer.new()
	badges.add_theme_constant_override("separation", 6)
	badges.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(badges)

	if is_local:
		badges.add_child(_make_badge("● LOCAL", Color(0.2, 0.85, 0.4)))
	if is_remote:
		badges.add_child(_make_badge("● CLOUD", COLOR_ACCENT))

	row.mouse_entered.connect(func(): row.modulate = COLOR_ROW_HOVER)
	row.mouse_exited.connect(func(): row.modulate = Color.WHITE)
	row.gui_input.connect(_on_row_input.bind(space, row))
	_item_list.add_child(row)


func _make_badge(text: String, color: Color) -> PanelContainer:
	var container := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.18)
	style.set_corner_radius_all(4)
	style.content_margin_left   = 8
	style.content_margin_right  = 8
	style.content_margin_top    = 4
	style.content_margin_bottom = 4
	container.add_theme_stylebox_override("panel", style)

	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", FONT_SMALL)
	label.add_theme_color_override("font_color", color)
	container.add_child(label)
	return container
