class_name TrackingIndicator
extends Node3D

const _POSITION   := Vector3(0.086, 0.07, -0.3)
const _SPIN_SPEED := 2.2  # radians per second

# dot
var _dot:     MeshInstance3D
var _dot_mat: StandardMaterial3D

# spinner — a static arc mesh inside a rotating parent
var _spinner_pivot: Node3D
var _spinner_mat:   StandardMaterial3D

var _spinning := false


func _ready() -> void:
	position = _POSITION
	_build_dot()
	_build_spinner()


func _process(delta: float) -> void:
	if _spinning and _spinner_pivot:
		_spinner_pivot.rotation.z -= _SPIN_SPEED * delta


# ── Public API ────────────────────────────────────────────────────────────────

func set_confidence(confidence: int) -> void:
	if not _dot_mat:
		return
	match confidence:
		3: _dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # EXCELLENT
		2: _dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # GOOD
		1: _dot_mat.albedo_color = Color(1.0, 0.55, 0.0)  # FAIR
		0: _dot_mat.albedo_color = Color(1.0, 0.2, 0.2)   # POOR
		_: _dot_mat.albedo_color = Color(0.5, 0.5, 0.5)   # unknown


func set_spinning(spinning: bool) -> void:
	_spinning = spinning
	if _dot:
		_dot.visible = not spinning
	if _spinner_pivot:
		_spinner_pivot.visible = spinning


# ── Build helpers ─────────────────────────────────────────────────────────────

func _build_dot() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 0.004
	sphere.height = 0.008
	_dot_mat = StandardMaterial3D.new()
	_dot_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dot_mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
	_dot_mat.albedo_color  = Color(0.5, 0.5, 0.5)
	_dot = MeshInstance3D.new()
	_dot.mesh = sphere
	_dot.material_override = _dot_mat
	add_child(_dot)


func _build_spinner() -> void:
	_spinner_mat = StandardMaterial3D.new()
	_spinner_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
	_spinner_mat.transparency  = BaseMaterial3D.TRANSPARENCY_DISABLED
	_spinner_mat.albedo_color  = Color(0.5, 0.5, 0.5)
	_spinner_mat.no_depth_test = true
	_spinner_mat.cull_mode     = BaseMaterial3D.CULL_DISABLED

	var arc := ImmediateMesh.new()
	_draw_arc(arc, 0.003, 0.006, 270.0, 32)

	var mi := MeshInstance3D.new()
	mi.mesh = arc
	mi.material_override = _spinner_mat

	_spinner_pivot = Node3D.new()
	_spinner_pivot.add_child(mi)
	_spinner_pivot.visible = false
	add_child(_spinner_pivot)


func _draw_arc(mesh: ImmediateMesh, r_in: float, r_out: float, degrees: float, segs: int) -> void:
	var start := -PI / 2.0
	var sweep := deg_to_rad(degrees)
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in segs:
		var a0 := start + float(i)     / segs * sweep
		var a1 := start + float(i + 1) / segs * sweep
		mesh.surface_add_vertex(Vector3(cos(a0) * r_out, sin(a0) * r_out, 0))
		mesh.surface_add_vertex(Vector3(cos(a0) * r_in,  sin(a0) * r_in,  0))
		mesh.surface_add_vertex(Vector3(cos(a1) * r_out, sin(a1) * r_out, 0))
		mesh.surface_add_vertex(Vector3(cos(a0) * r_in,  sin(a0) * r_in,  0))
		mesh.surface_add_vertex(Vector3(cos(a1) * r_in,  sin(a1) * r_in,  0))
		mesh.surface_add_vertex(Vector3(cos(a1) * r_out, sin(a1) * r_out, 0))
	mesh.surface_end()
