class_name Asset

var id: String = ""
var name: String = ""
var asset_type: String = ""

static func from_dict(data: Dictionary) -> Asset:
	var asset := Asset.new()
	asset.id = data.get("id", "")
	asset.name = data.get("name", "")
	asset.asset_type = data.get("asset_type", "")
	return asset
