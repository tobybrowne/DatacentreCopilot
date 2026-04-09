class_name Building

var id: String
var name: String
var created_at: String
var draft: bool


static func from_dict(data: Dictionary) -> Building:
	var b := Building.new()
	b.id = data.get("id", "")
	b.name = data.get("name", "")
	b.created_at = data.get("created_at", "")
	b.draft = data.get("draft", true)
	return b
