class_name BoundingBoxVisual
extends Node3D

# Assign before adding to the scene tree.
var bbox: Dictionary         # {vertices_2d: [[x,z],...], y_min, y_max} in building coords
var color: Color
var anchor_manager: AnchorManager

const COLORS = [
	Color(0.0, 1.0, 0.8),   # cyan
	Color(1.0, 0.55, 0.0),  # orange
	Color(0.6, 0.0, 1.0),   # violet
	Color(1.0, 1.0, 0.0),   # yellow
	Color(0.0, 1.0, 0.3),   # green
	Color(1.0, 0.0, 0.5),   # pink
	Color(0.3, 0.7, 1.0),   # sky
	Color(1.0, 0.3, 0.3),   # red
]

var _mi: MeshInstance3D


func _ready() -> void:
	_build()


# Tear down and rebuild geometry (call after calibration changes).
func rebuild() -> void:
	if _mi:
		_mi.queue_free()
		_mi = null
	_build()


func _build() -> void:
	var verts: Array = bbox.get("vertices_2d", [])
	if verts.size() < 2 or not anchor_manager:
		return

	var y_min: float = bbox.get("y_min", 0.0)
	var y_max: float = bbox.get("y_max", 0.0)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.no_depth_test = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED

	var mesh := ImmediateMesh.new()
	_mi = MeshInstance3D.new()
	_mi.mesh = mesh
	_mi.material_override = mat
	add_child(_mi)

	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	var n := verts.size()
	for i in n:
		var j := (i + 1) % n
		var b0 := anchor_manager.world_to_local(Vector3(verts[i][0], y_min, verts[i][1]))
		var b1 := anchor_manager.world_to_local(Vector3(verts[j][0], y_min, verts[j][1]))
		var t0 := anchor_manager.world_to_local(Vector3(verts[i][0], y_max, verts[i][1]))
		var t1 := anchor_manager.world_to_local(Vector3(verts[j][0], y_max, verts[j][1]))
		mesh.surface_add_vertex(b0); mesh.surface_add_vertex(b1)  # bottom edge
		mesh.surface_add_vertex(t0); mesh.surface_add_vertex(t1)  # top edge
		mesh.surface_add_vertex(b0); mesh.surface_add_vertex(t0)  # vertical
	mesh.surface_end()
