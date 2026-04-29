# Camera-facing ring that fills clockwise from 0.0 to 1.0 (used for gesture progess)
# objects call update(pos, progress, color) each frame while a gesture is held,
# and clear() when the gesture ends or completes.

class_name ProgressIndicator
extends Node3D

const _R_IN  := 0.04
const _R_OUT := 0.08
const _SEGS  := 48
const _START := -PI / 2.0

var _bg_mesh_instance: MeshInstance3D
var _arc_mesh_instance: MeshInstance3D
var _arc_mesh: ImmediateMesh
var _bg_mat: StandardMaterial3D
var _arc_mat: StandardMaterial3D
var _built := false


func update(pos: Vector3, progress: float, color: Color) -> void:
	if not _built:
		_build()
	visible = true
	global_position = pos
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > 0.01:
		look_at(cam.global_position, Vector3.UP)

	_bg_mat.albedo_color  = Color(color.r, color.g, color.b, 0.2)
	_arc_mat.albedo_color = color

	_arc_mesh.clear_surfaces()
	if progress > 0.0:
		var n_draw: int = max(1, int(_SEGS * progress))
		_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n_draw:
			_ring_quad(_arc_mesh, i)
		_arc_mesh.surface_end()


func clear() -> void:
	visible = false
	if _arc_mesh:
		_arc_mesh.clear_surfaces()


func _build() -> void:
	_bg_mat  = _make_mat(Color(0.2, 0.8, 1.0, 0.2))
	_arc_mat = _make_mat(Color(0.2, 0.8, 1.0, 1.0))

	var bg_mesh := ImmediateMesh.new()
	bg_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in _SEGS:
		_ring_quad(bg_mesh, i)
	bg_mesh.surface_end()

	_bg_mesh_instance = MeshInstance3D.new()
	_bg_mesh_instance.mesh = bg_mesh
	_bg_mesh_instance.material_override = _bg_mat
	add_child(_bg_mesh_instance)

	_arc_mesh = ImmediateMesh.new()
	_arc_mesh_instance = MeshInstance3D.new()
	_arc_mesh_instance.mesh = _arc_mesh
	_arc_mesh_instance.material_override = _arc_mat
	add_child(_arc_mesh_instance)

	_built = true


func _make_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color  = color
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	return mat


func _ring_quad(mesh: ImmediateMesh, i: int) -> void:
	var a0 := _START - float(i)     / _SEGS * TAU
	var a1 := _START - float(i + 1) / _SEGS * TAU
	mesh.surface_add_vertex(Vector3(cos(a0) * _R_OUT, sin(a0) * _R_OUT, 0))
	mesh.surface_add_vertex(Vector3(cos(a0) * _R_IN,  sin(a0) * _R_IN,  0))
	mesh.surface_add_vertex(Vector3(cos(a1) * _R_OUT, sin(a1) * _R_OUT, 0))
	mesh.surface_add_vertex(Vector3(cos(a0) * _R_IN,  sin(a0) * _R_IN,  0))
	mesh.surface_add_vertex(Vector3(cos(a1) * _R_IN,  sin(a1) * _R_IN,  0))
	mesh.surface_add_vertex(Vector3(cos(a1) * _R_OUT, sin(a1) * _R_OUT, 0))
