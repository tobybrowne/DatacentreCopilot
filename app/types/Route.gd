class_name Route

var id: String
var start_anchor_id: String
var end_anchor_id: String
var waypoints: Array[Vector3]

static func from_dict(data: Dictionary) -> Route:
	var route := Route.new()
	route.id = data.get("id", "")
	route.start_anchor_id = data.get("start_anchor_id", "")
	route.end_anchor_id = data.get("end_anchor_id", "")
	for wp in data.get("waypoints", []):
		if wp is Dictionary:
			route.waypoints.append(Vector3(
				wp.get("x", 0.0),
				wp.get("y", 0.0),
				wp.get("z", 0.0)
			))
	return route
