class_name LogBrowserPanel
extends BasePanel

@onready var _item_list: VBoxContainer = $VBoxContainer/ScrollContainer/ItemList
@onready var _status: Label = $VBoxContainer/Status

signal play_requested(log_id: String, geo_path: String, ogv_path: String)
signal stop_requested

var _active_log_id: String = ""
var _active_btn:    Button = null
var _loading_btn:   Button = null
var _spinner_time:  float  = 0.0

const _SPINNER := ["◐", "◓", "◑", "◒"]


func _process(delta: float) -> void:
	if not _loading_btn:
		return
	_spinner_time += delta
	_loading_btn.text = _SPINNER[int(_spinner_time * 8) % _SPINNER.size()]


func init(data: Dictionary) -> void:
	_clear()
	_status.text = "Loading…"
	var step_id: String = data.get("step_id", "")
	var asset_id: String = data.get("asset_id", "")
	if not step_id.is_empty():
		_load_logs(step_id)
	elif not asset_id.is_empty():
		_load_logs_for_asset(asset_id)


func _clear() -> void:
	for child in _item_list.get_children():
		child.queue_free()
	_active_log_id = ""
	_active_btn    = null
	_loading_btn   = null
	_spinner_time  = 0.0


func _load_logs(step_id: String) -> void:
	var task = await Supabase.database.query(
		SupabaseQuery.new()
			.from("logs")
			.select(["id", "created_at", "geometry_recording_path", "camera_recording_path_ogv", "user_id"])
			.eq("step_id", step_id)
			.order("created_at", SupabaseQuery.Directions.Descending)
	).completed

	_clear()

	if task.error != null or task.data == null or task.data.is_empty():
		_status.text = "No logs for this step."
		return

	var rows: Array = task.data.filter(func(r):
		var has_geo: bool = r.get("geometry_recording_path") != null and not r.get("geometry_recording_path", "").is_empty()
		var has_ogv: bool = r.get("camera_recording_path_ogv") != null and not r.get("camera_recording_path_ogv", "").is_empty()
		return has_geo or has_ogv
	)
	if rows.is_empty():
		_status.text = "No playable logs for this step."
		return

	var user_ids := PackedStringArray()
	for row in rows:
		var uid: String = row.get("user_id", "")
		if not uid.is_empty() and uid not in user_ids:
			user_ids.append(uid)

	var email_map: Dictionary = {}
	if user_ids.size() > 0:
		var utask = await Supabase.database.query(
			SupabaseQuery.new().from("users").select(["id", "contact_email"]).In("id", user_ids)
		).completed
		if utask.data:
			for u in utask.data:
				email_map[u.get("id", "")] = u.get("contact_email", "Unknown")

	_status.text = ""
	for row in rows:
		_add_row(row, email_map)
		await get_tree().process_frame


func _load_logs_for_asset(asset_id: String) -> void:
	var la_task = await Supabase.database.query(
		SupabaseQuery.new().from("log_assets").select(["log_id"]).eq("asset_id", asset_id)
	).completed

	_clear()

	if la_task.error != null or la_task.data == null or la_task.data.is_empty():
		_status.text = "No logs for this asset."
		return

	var log_ids := PackedStringArray()
	for row in la_task.data:
		var lid: String = row.get("log_id", "")
		if not lid.is_empty():
			log_ids.append(lid)

	if log_ids.is_empty():
		_status.text = "No logs for this asset."
		return

	var task = await Supabase.database.query(
		SupabaseQuery.new()
			.from("logs")
			.select(["id", "created_at", "geometry_recording_path", "camera_recording_path_ogv", "user_id"])
			.In("id", log_ids)
			.order("created_at", SupabaseQuery.Directions.Descending)
	).completed

	_clear()

	if task.error != null or task.data == null or task.data.is_empty():
		_status.text = "No playable logs for this asset."
		return

	var rows: Array = task.data.filter(func(r):
		var has_geo: bool = r.get("geometry_recording_path") != null and not r.get("geometry_recording_path", "").is_empty()
		var has_ogv: bool = r.get("camera_recording_path_ogv") != null and not r.get("camera_recording_path_ogv", "").is_empty()
		return has_geo or has_ogv
	)
	if rows.is_empty():
		_status.text = "No playable logs for this asset."
		return

	var user_ids := PackedStringArray()
	for row in rows:
		var uid: String = row.get("user_id", "")
		if not uid.is_empty() and uid not in user_ids:
			user_ids.append(uid)

	var email_map: Dictionary = {}
	if user_ids.size() > 0:
		var utask = await Supabase.database.query(
			SupabaseQuery.new().from("users").select(["id", "contact_email"]).In("id", user_ids)
		).completed
		if utask.data:
			for u in utask.data:
				email_map[u.get("id", "")] = u.get("contact_email", "Unknown")

	_status.text = ""
	for row in rows:
		_add_row(row, email_map)
		await get_tree().process_frame


func _add_row(row: Dictionary, email_map: Dictionary) -> void:
	var log_id: String = row.get("id", "")
	var geo_path: String = row.get("geometry_recording_path", "") if row.get("geometry_recording_path") != null else ""
	var ogv_path: String = row.get("camera_recording_path_ogv", "") if row.get("camera_recording_path_ogv") != null else ""
	var email: String = email_map.get(row.get("user_id", ""), "Unknown")
	var created_at: String = row.get("created_at", "")

	var panel := PanelContainer.new()

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 12)
	panel.add_child(hbox)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 2)
	hbox.add_child(info)

	var email_lbl := Label.new()
	email_lbl.text = email
	email_lbl.add_theme_font_size_override("font_size", FONT_BODY)
	email_lbl.clip_text = true
	info.add_child(email_lbl)

	var time_lbl := Label.new()
	time_lbl.text = _format_datetime(created_at)
	time_lbl.add_theme_font_size_override("font_size", FONT_SMALL)
	time_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
	info.add_child(time_lbl)

	var icons := VBoxContainer.new()
	icons.add_theme_constant_override("separation", 2)
	icons.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(icons)
	_add_availability_icon(icons, "Pose", not geo_path.is_empty())
	_add_availability_icon(icons, "Video", not ogv_path.is_empty())

	var play_btn := Button.new()
	play_btn.text = "▶"
	play_btn.custom_minimum_size = Vector2(72, 0)
	play_btn.add_theme_font_size_override("font_size", FONT_BODY)
	play_btn.pressed.connect(func(): _on_play_pressed(log_id, geo_path, ogv_path, play_btn))
	hbox.add_child(play_btn)

	_item_list.add_child(panel)


func _on_play_pressed(log_id: String, geo_path: String, ogv_path: String, btn: Button) -> void:
	if _active_log_id == log_id:
		_clear_all()
		stop_requested.emit()
	else:
		if not _active_log_id.is_empty():
			stop_requested.emit()
		_clear_all()
		_active_log_id = log_id
		_loading_btn = btn
		_spinner_time = 0.0
		btn.disabled = true
		play_requested.emit(log_id, geo_path, ogv_path)


func notify_playback_started() -> void:
	if _loading_btn:
		_loading_btn.disabled = false
		_loading_btn.text = "■"
		_active_btn = _loading_btn
		_loading_btn = null


func notify_playback_finished() -> void:
	_clear_all()


func _clear_all() -> void:
	if _active_btn:
		_active_btn.text = "▶"
		_active_btn.disabled = false
		_active_btn = null
	if _loading_btn:
		_loading_btn.text = "▶"
		_loading_btn.disabled = false
		_loading_btn = null
	_active_log_id = ""
	_spinner_time = 0.0


func _add_availability_icon(parent: Control, label: String, available: bool) -> void:
	var lbl := Label.new()
	lbl.text = ("● " if available else "○ ") + label
	lbl.add_theme_font_size_override("font_size", FONT_SMALL)
	lbl.add_theme_color_override("font_color",
		Color(0.35, 0.85, 0.45) if available else Color(0.40, 0.40, 0.50))
	parent.add_child(lbl)


func _format_datetime(iso: String) -> String:
	if iso.is_empty():
		return ""
	var parts := iso.split("T")
	if parts.size() < 2:
		return iso
	var time_part := parts[1].split(".")[0]
	if time_part.length() >= 5:
		time_part = time_part.substr(0, 5)
	return "%s  %s" % [parts[0], time_part]
