class_name OcclusionManager
extends Node3D

# Fallback depth occluders built from loc_bounding_box polygon edges.
# Each edge becomes a wall quad rendered at render_priority=-50, after WorldMeshManager
# (-100). Standard GPU depth testing ensures world mesh wins where scanned; the
# fallback wall writes depth only where the depth buffer still shows the far plane.

@export var enabled: bool = true:
	set(v):
		enabled = v
		for mi: MeshInstance3D in _wall_nodes.values():
			if is_instance_valid(mi):
				mi.visible = v

# When true, renders translucent orange walls instead of depth-only — useful for
# verifying wall placement without putting on the headset.
@export var debug_visible: bool = false
@export var tof_range: float = 4

var _anchor_manager: AnchorManager
var _wall_nodes: Dictionary = {}  # space_id -> MeshInstance3D


func _ready() -> void:
	_anchor_manager = get_parent().get_node_or_null("AnchorManager")
	if not _anchor_manager:
		push_warning("OcclusionManager: AnchorManager not found")
		return
	_anchor_manager.calibrated.connect(_rebuild_walls)


func _rebuild_walls() -> void:
	for mi: MeshInstance3D in _wall_nodes.values():
		if is_instance_valid(mi):
			mi.queue_free()
	_wall_nodes.clear()

	for space: Space in _anchor_manager.get_building_spaces():
		if not space.loc_bounding_box.is_empty():
			_build_walls_for_space(space)


func _build_walls_for_space(space: Space) -> void:
	var bbox: Dictionary = space.loc_bounding_box
	var verts: Array = bbox.get("vertices_2d", [])
	if verts.size() < 2:
		return

	var y_min: float = bbox.get("y_min", 0.0)
	var y_max: float = bbox.get("y_max", 3.0)

	var vertices := PackedVector3Array()
	var indices := PackedInt32Array()
	var idx := 0

	var n := verts.size()
	for i in n:
		var j := (i + 1) % n
		var p0 := _anchor_manager.world_to_local(Vector3(verts[i][0], y_min, verts[i][1]))
		var p1 := _anchor_manager.world_to_local(Vector3(verts[j][0], y_min, verts[j][1]))
		var p2 := _anchor_manager.world_to_local(Vector3(verts[j][0], y_max, verts[j][1]))
		var p3 := _anchor_manager.world_to_local(Vector3(verts[i][0], y_max, verts[i][1]))
		vertices.append_array([p0, p1, p2, p3])
		# Two triangles, wound both ways so the wall occludes from either side.
		indices.append_array([idx, idx+1, idx+2, idx, idx+2, idx+3])
		indices.append_array([idx+2, idx+1, idx, idx+3, idx+2, idx])
		idx += 4

	var arr_mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat: Material = _debug_material() if debug_visible else _occluder_material()

	var mi := MeshInstance3D.new()
	mi.mesh = arr_mesh
	mi.material_override = mat
	mi.visible = enabled
	add_child(mi)
	_wall_nodes[space.id] = mi


func _occluder_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/depth_occluder_ranged.gdshader")
	mat.set_shader_parameter("tof_range", tof_range)
	mat.render_priority = -50
	return mat


func _debug_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.5, 0.0, 0.25)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	return mat
