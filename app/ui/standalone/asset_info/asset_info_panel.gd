class_name AssetInfoPanel
extends BasePanel


func _ready() -> void:
	super._ready()
	var close_btn := get_node_or_null("VBoxContainer/TopBar/CloseButton") as Button
	if close_btn:
		close_btn.pressed.connect(func(): close_requested.emit())


func init(data: Dictionary) -> void:
	var name_label := get_node_or_null("VBoxContainer/TopBar/Title") as Label
	if name_label:
		name_label.text = data.get("asset_name", "Asset")

	var type_label := get_node_or_null("VBoxContainer/TypeLabel") as Label
	if type_label:
		var asset_type: String = data.get("asset_type", "")
		type_label.text = asset_type
		type_label.visible = not asset_type.is_empty()
