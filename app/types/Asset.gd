class_name Asset

var id: String = ""
var name: String = ""
var asset_type: String = ""
var model_name: String = ""
var manufacturer: String = ""

static func from_dict(data: Dictionary) -> Asset:
	var asset := Asset.new()
	asset.id = data.get("id", "")
	asset.name = data.get("name", "")
	asset.asset_type = data.get("asset_type", "")
	var model = data.get("asset_models", null)
	if model is Dictionary:
		asset.model_name = model.get("name", "")
		asset.manufacturer = model.get("manufacturer", "")
	return asset
