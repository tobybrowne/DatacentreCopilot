class_name AssetInfoPanel
extends BasePanel

signal logs_requested


func _ready() -> void:
	super._ready()
	var close_btn := get_node_or_null("VBoxContainer/TopBar/CloseButton") as Button
	if close_btn:
		close_btn.pressed.connect(func(): close_requested.emit())
	var logs_btn := get_node_or_null("VBoxContainer/ContentArea/ViewLogsButton") as Button
	if logs_btn:
		logs_btn.pressed.connect(func(): logs_requested.emit())


func init(data: Dictionary) -> void:
	var name_label := get_node_or_null("VBoxContainer/TopBar/Title") as Label
	if name_label:
		name_label.text = data.get("asset_name", "Asset")

	var icon_rect := get_node_or_null("VBoxContainer/TopBar/AssetIcon") as TextureRect
	if icon_rect:
		var asset_type: String = data.get("asset_type", "")
		var path := "res://ui/standalone/asset_fab/icons/" + asset_type + ".svg"
		if not asset_type.is_empty() and ResourceLoader.exists(path):
			icon_rect.texture = load(path)
			icon_rect.visible = true
		else:
			icon_rect.visible = false

	var logs_btn := get_node_or_null("VBoxContainer/ContentArea/ViewLogsButton") as Button
	if logs_btn:
		logs_btn.visible = data.get("has_logs", false)
