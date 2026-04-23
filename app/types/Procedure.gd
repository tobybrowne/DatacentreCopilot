class_name Procedure

var id: String
var title: String
var building_id: String
var steps: Array[Step]
var log_type: String  # "FULL" | "CAMERA_ONLY" | "GEOMETRY_ONLY" | "NONE"
var created_at: String
var updated_at: String

static func from_dict(data: Dictionary) -> Procedure:
	var procedure := Procedure.new()
	procedure.id = data.get("id", "")
	procedure.title = data.get("title", "")
	procedure.building_id = data.get("building_id", "")
	procedure.log_type = data.get("log_type", "NONE")
	for raw in data.get("steps", []):
		procedure.steps.append(Step.from_value(raw))
	procedure.created_at = data.get("created_at", "")
	procedure.updated_at = data.get("updated_at", "")
	return procedure
