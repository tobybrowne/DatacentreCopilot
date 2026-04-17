extends Node
class_name RouteManager

## Renders routes from Supabase once LocationManager has calibrated.
## Also handles on-demand GOTO route: fetching from the nav API and displaying
## a temporary route for the currently active GOTO step.
##
## Waypoints are stored in building world-space and converted to headset local
## space via LocationManager.world_to_local().

@export var nav_api_url: String = "https://room-finder.tobybrowne.co.uk"

const GOTO_COLOR := Color(0.2, 0.85, 1.0)
const ROUTE_Y_OFFSET := 0.08  # float above floor

# The single on-demand route shown for the active GOTO step.
var _goto_route_node: Node3D = null


# ── Stored routes (shown after calibration) ───────────────────────────────────

func _ready() -> void:
	pass



# ── On-demand GOTO route ──────────────────────────────────────────────────────

## Call the nav API to compute a path, then display it as the active GOTO route.
## anchor_a_id — Supabase UUID of the start anchor (created at user's position)
## anchor_b_id — Supabase UUID of the destination anchor
## lm          — LocationManager for world→local coordinate conversion
## Returns the waypoints on success, or [] on failure.
func fetch_and_display_goto(anchor_a_id: String, anchor_b_id: String, lm: LocationManager) -> Array[Vector3]:
	var waypoints := await request_path(anchor_a_id, anchor_b_id)
	if waypoints.is_empty():
		return []
	display_goto_route(waypoints, lm)
	return waypoints


## Display already-computed waypoints as the active GOTO route.
func display_goto_route(waypoints: Array[Vector3], lm: LocationManager) -> void:
	clear_goto_route()
	if waypoints.size() < 2:
		return
	_goto_route_node = Node3D.new()
	get_parent().add_child(_goto_route_node)
	_build_route_line(_goto_route_node, waypoints, lm, GOTO_COLOR)


## Remove the active GOTO route from the scene.
func clear_goto_route() -> void:
	if _goto_route_node:
		_goto_route_node.queue_free()
		_goto_route_node = null


## HTTP POST to /nav/path — returns Array[Vector3] in building world-space, or [].
func request_path(anchor_a_id: String, anchor_b_id: String) -> Array[Vector3]:
	var http := HTTPRequest.new()
	add_child(http)

	var body    := JSON.stringify({"anchor_a_id": anchor_a_id, "anchor_b_id": anchor_b_id})
	var headers := PackedStringArray(["Content-Type: application/json"])
	var err     := http.request(nav_api_url + "/nav/path", headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_warning("RouteManager: HTTPRequest.request() failed err=", err)
		http.queue_free()
		return []

	var result: Array       = await http.request_completed
	http.queue_free()

	var response_code: int          = result[1]
	var body_bytes: PackedByteArray = result[3]

	if response_code != 200:
		push_warning("RouteManager: server returned ", response_code,
				" — ", body_bytes.get_string_from_utf8())
		return []

	var json := JSON.new()
	if json.parse(body_bytes.get_string_from_utf8()) != OK:
		push_warning("RouteManager: failed to parse response JSON")
		return []

	var data = json.get_data()
	var waypoints: Array[Vector3] = []
	for wp in data.get("waypoints", []):
		if wp is Dictionary:
			waypoints.append(Vector3(
				wp.get("x", 0.0),
				wp.get("y", 0.0),
				wp.get("z", 0.0)
			))

	print("RouteManager: ", waypoints.size(), " waypoints for ",
			anchor_a_id, " → ", anchor_b_id)
	return waypoints


# ── Shared rendering helpers ──────────────────────────────────────────────────

func _build_route_line(parent: Node3D, waypoints: Array[Vector3], lm: LocationManager, color: Color) -> void:
	var local_pts: Array[Vector3] = []
	for wp in waypoints:
		local_pts.append(lm.world_to_local(wp) + Vector3(0, ROUTE_Y_OFFSET, 0))

	var mesh := ImmediateMesh.new()
	var mat  := StandardMaterial3D.new()
	mat.albedo_color               = color
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test              = true

	var mi := MeshInstance3D.new()
	mi.mesh              = mesh
	mi.material_override = mat
	parent.add_child(mi)

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(local_pts.size() - 1):
		mesh.surface_add_vertex(local_pts[i])
		mesh.surface_add_vertex(local_pts[i + 1])
	mesh.surface_end()

	_add_endpoint(parent, local_pts[0],                    Color(0.0, 1.0, 0.5))
	_add_endpoint(parent, local_pts[local_pts.size() - 1], Color(1.0, 0.2, 0.2))


func _add_endpoint(parent: Node3D, pos: Vector3, color: Color) -> void:
	var mi     := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color               = color
	mat.emission_enabled           = true
	mat.emission                   = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode               = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test              = true
	mi.material_override = mat
	mi.position          = pos
	parent.add_child(mi)
