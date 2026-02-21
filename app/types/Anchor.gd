class_name Anchor

var id: String
var name: String

static func from_dict(data: Dictionary) -> Anchor:
	var anchor := Anchor.new()
	anchor.id = data.get("id", "")
	anchor.name = data.get("name", "")
	return anchor
