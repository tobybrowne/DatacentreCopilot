class_name Procedure

var id: String
var title: String
var steps: Array[String]
var created_at: String
var updated_at: String

static func from_dict(data: Dictionary) -> Procedure:
	var procedure := Procedure.new()
	procedure.id = data.get("id", "")
	procedure.title = data.get("title", "")
	procedure.steps.assign(data.get("steps", []))
	procedure.created_at = data.get("created_at", "")
	procedure.updated_at = data.get("updated_at", "")
	return procedure
