extends Node3D

@export var test_distance: float = 3.0
# Half-FOV angles in degrees, calibrated empirically for ML2
@export var half_fov_h: float = 22.8
@export var half_fov_v: float = 24.7

var _camera: XRCamera3D
var _mesh: ImmediateMesh


func _ready() -> void:
	_camera = get_parent().get_node_or_null("XRCamera3D")

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1, 0, 0, 1)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true

	_mesh = ImmediateMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = mat
	add_child(mi)


func _process(_delta: float) -> void:
	if not _camera:
		return

	var cam := _camera.global_transform
	var D   := test_distance

	var hw := tan(deg_to_rad(half_fov_h)) * D
	var hv := tan(deg_to_rad(half_fov_v)) * D

	var center := cam.origin - cam.basis.z * D
	var right  := cam.basis.x
	var up     := cam.basis.y

	var tl := center + right * -hw + up *  hv
	var tr := center + right *  hw + up *  hv
	var br := center + right *  hw + up * -hv
	var bl := center + right * -hw + up * -hv

	var cs := D * 0.03

	_mesh.clear_surfaces()
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)

	# Border
	_mesh.surface_add_vertex(tl); _mesh.surface_add_vertex(tr)
	_mesh.surface_add_vertex(tr); _mesh.surface_add_vertex(br)
	_mesh.surface_add_vertex(br); _mesh.surface_add_vertex(bl)
	_mesh.surface_add_vertex(bl); _mesh.surface_add_vertex(tl)

	# Crosshair
	_mesh.surface_add_vertex(center - right * cs)
	_mesh.surface_add_vertex(center + right * cs)
	_mesh.surface_add_vertex(center - up * cs)
	_mesh.surface_add_vertex(center + up * cs)

	_mesh.surface_end()
