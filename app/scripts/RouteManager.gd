extends Node

## Renders all routes from Supabase once LocationManager has calibrated.
## Waypoints are stored in building world space and converted to headset local
## space via LocationManager.world_to_local().

const ROUTE_COLOR  := Color(1.0, 0.55, 0.0)
const ROUTE_Y_OFFSET := 0.08  # float above floor

var _route_nodes: Array[Node3D] = []


func _ready() -> void:
	var lm := get_parent().get_node_or_null("LocationManager") as LocationManager
	if not lm:
		push_warning("RouteManager: LocationManager not found")
		return
	lm.calibrated.connect(_on_calibrated.bind(lm))


func _on_calibrated(lm: LocationManager) -> void:
	var routes: Array[Route] = await SupabaseManager.get_routes()
	_render_routes(routes, lm)


func _render_routes(routes: Array[Route], lm: LocationManager) -> void:
	for node in _route_nodes:
		node.queue_free()
	_route_nodes.clear()

	for route in routes:
		if route.waypoints.size() < 2:
			continue
		var root := Node3D.new()
		get_parent().add_child(root)
		_route_nodes.append(root)
		_build_route_line(root, route.waypoints, lm)


func _build_route_line(parent: Node3D, waypoints: Array[Vector3], lm: LocationManager) -> void:
	var local_pts: Array[Vector3] = []
	for wp in waypoints:
		local_pts.append(lm.world_to_local(wp) + Vector3(0, ROUTE_Y_OFFSET, 0))

	var mesh := ImmediateMesh.new()
	var mat  := StandardMaterial3D.new()
	mat.albedo_color              = ROUTE_COLOR
	mat.emission_enabled          = true
	mat.emission                  = ROUTE_COLOR
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test             = true

	var mi := MeshInstance3D.new()
	mi.mesh              = mesh
	mi.material_override = mat
	parent.add_child(mi)

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(local_pts.size() - 1):
		mesh.surface_add_vertex(local_pts[i])
		mesh.surface_add_vertex(local_pts[i + 1])
	mesh.surface_end()

	_add_endpoint(parent, local_pts[0],                      Color(0.0, 1.0, 0.5))
	_add_endpoint(parent, local_pts[local_pts.size() - 1],   Color(1.0, 0.2, 0.2))


func _add_endpoint(parent: Node3D, pos: Vector3, color: Color) -> void:
	var mi     := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color              = color
	mat.emission_enabled          = true
	mat.emission                  = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode              = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test             = true
	mi.material_override = mat
	mi.position          = pos
	parent.add_child(mi)
