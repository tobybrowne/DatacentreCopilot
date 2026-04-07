class_name BuildingSpace

var id: String
var building_id: String
var space_id: String
var index: int
var offset_transformation: Transform3D  # identity for index 0 (reference space)

static func from_dict(data: Dictionary) -> BuildingSpace:
	var bs := BuildingSpace.new()
	bs.id = data.get("id", "")
	bs.building_id = data.get("building_id", "")
	bs.space_id = data.get("space_id", "")
	bs.index = data.get("index", 0)
	var ot = data.get("offset_transformation", null)
	if ot is Dictionary:
		var p = ot.get("position", {})
		var q = ot.get("quaternion", {})
		var origin := Vector3(p.get("x", 0.0), p.get("y", 0.0), p.get("z", 0.0))
		var quat := Quaternion(q.get("x", 0.0), q.get("y", 0.0), q.get("z", 0.0), q.get("w", 1.0))
		bs.offset_transformation = Transform3D(Basis(quat), origin)
	else:
		bs.offset_transformation = Transform3D.IDENTITY
	return bs
