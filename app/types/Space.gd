class_name Space

var id: String
var name: String
var building_id: String
var site_id: String
var blob_path: String
var glb_path: String
var offset_transformation: Transform3D
var loc_bounding_box: Dictionary   # {vertices_2d: [[x,z],...], y_min: float, y_max: float} in building coords
var tight_bounding_box: Dictionary # tighter hull from room segmentation; preferred over loc_bounding_box for occlusion
var created_at: String
var updated_at: String

static func from_dict(data: Dictionary) -> Space:
	var space := Space.new()
	space.id = data.get("id", "")
	space.name = data.get("name", "")
	var _bid = data.get("building_id")
	space.building_id = _bid if _bid is String else ""
	space.site_id = data.get("site_id", "")
	space.blob_path = data.get("blob_path", "")
	space.glb_path = data.get("glb_path", "")
	var ot = data.get("offset_transformation", null)
	if ot is Dictionary:
		var p = ot.get("position", {})
		var q = ot.get("quaternion", {})
		var origin := Vector3(p.get("x", 0.0), p.get("y", 0.0), p.get("z", 0.0))
		var quat := Quaternion(q.get("x", 0.0), q.get("y", 0.0), q.get("z", 0.0), q.get("w", 1.0))
		space.offset_transformation = Transform3D(Basis(quat), origin)
	else:
		space.offset_transformation = Transform3D.IDENTITY
	var lbb = data.get("loc_bounding_box", null)
	space.loc_bounding_box = lbb if lbb is Dictionary else {}
	var tbb = data.get("tight_bounding_box", null)
	space.tight_bounding_box = tbb if tbb is Dictionary else {}
	space.created_at = data.get("created_at", "")
	space.updated_at = data.get("updated_at", "")
	return space
