class_name AssetInfoPanel
extends BasePanel

signal logs_requested


func _ready() -> void:
	super._ready()
	var close_btn := get_node_or_null("VBoxContainer/TopBar/CloseButton") as Button
	if close_btn:
		close_btn.pressed.connect(func(): close_requested.emit())
	var logs_btn := get_node_or_null("VBoxContainer/ActionRow/ViewLogsButton") as Button
	if logs_btn:
		logs_btn.pressed.connect(func(): logs_requested.emit())


func init(data: Dictionary) -> void:
	var name_label := get_node_or_null("VBoxContainer/TopBar/Title") as Label
	if name_label:
		name_label.text = data.get("asset_name", "Asset")

	var icon_rect := get_node_or_null("VBoxContainer/TopBar/AssetIcon") as TextureRect
	if icon_rect:
		var asset_type: String = data.get("asset_type", "")
		var path := AssetTypes.icon_path(asset_type)
		if not path.is_empty() and ResourceLoader.exists(path):
			icon_rect.texture = load(path)
			icon_rect.visible = true
		else:
			icon_rect.visible = false

	var model_label := get_node_or_null("VBoxContainer/ContentArea/ModelLabel") as Label
	if model_label:
		model_label.text = data.get("model_name", "")
		model_label.visible = not model_label.text.is_empty()

	var mfr_label := get_node_or_null("VBoxContainer/ContentArea/ManufacturerLabel") as Label
	if mfr_label:
		mfr_label.text = data.get("manufacturer", "")
		mfr_label.visible = not mfr_label.text.is_empty()

	var manuals_container := get_node_or_null("VBoxContainer/ActionRow/ManualsContainer") as HBoxContainer
	if manuals_container:
		for child in manuals_container.get_children():
			child.queue_free()
		for manual in data.get("manuals", []):
			var url: String = manual.get("url", "")
			if url.is_empty():
				continue
			var btn := Button.new()
			btn.text = manual.get("title", "View Manual")
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.add_theme_font_size_override("font_size", 22)
			btn.pressed.connect(func(): OS.shell_open(url))
			manuals_container.add_child(btn)

	update_live_data(data.get("live_data", null))

	var logs_btn := get_node_or_null("VBoxContainer/ActionRow/ViewLogsButton") as Button
	if logs_btn:
		logs_btn.visible = data.get("has_logs", false)


func update_live_data(live_data: Object) -> void:
	var gauge_spacer := get_node_or_null("VBoxContainer/ContentArea/GaugeSpacer") as Control
	var gauge_row    := get_node_or_null("VBoxContainer/ContentArea/GaugeRow") as HBoxContainer
	if not gauge_row:
		return
	for child in gauge_row.get_children():
		child.queue_free()
	if live_data is PowerAssetLiveData:
		gauge_row.visible = true
		if gauge_spacer: gauge_spacer.visible = true
		gauge_row.add_child(Gauge.make("Load",   live_data.load_percent, 100.0, "%"))
		gauge_row.add_child(Gauge.make("Input",  live_data.input_volt,   250.0, "V"))
		gauge_row.add_child(Gauge.make("Output", live_data.output_volt,  250.0, "V"))
	elif live_data is CoolingAssetLiveData:
		gauge_row.visible = true
		if gauge_spacer: gauge_spacer.visible = true
		gauge_row.add_child(Gauge.make("Temp", live_data.temperature,  40.0,  "°C"))
		gauge_row.add_child(Gauge.make("Load", live_data.load_percent, 100.0, "%"))
	else:
		gauge_row.visible = false
		if gauge_spacer: gauge_spacer.visible = false
