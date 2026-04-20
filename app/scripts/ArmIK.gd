extends Node3D

const UPPER_ARM = 0.38
const LOWER_ARM = 0.34
const SHOULDER_SIDE = 0.18
const SHOULDER_DOWN = 0.18
const SHOULDER_BACK = 0.05

@onready var head: XRCamera3D = $"../XRCamera3D"
@onready var left_wrist: XRNode3D = $"../LeftHand"
@onready var right_wrist: XRNode3D = $"../RightHand"

var _mesh: ImmediateMesh
var _mat: StandardMaterial3D
var _left_elbow_ball: MeshInstance3D
var _right_elbow_ball: MeshInstance3D

func _ready() -> void:
	_mesh = ImmediateMesh.new()
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.albedo_color = Color.WHITE
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	add_child(mi)
	_left_elbow_ball = _make_ball()
	_right_elbow_ball = _make_ball()

func _make_ball() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.03
	sphere.height = 0.06
	mi.mesh = sphere
	mi.material_override = _mat
	add_child(mi)
	return mi

func _process(_delta: float) -> void:
	_mesh.clear_surfaces()
	_left_elbow_ball.visible = left_wrist.visible
	_right_elbow_ball.visible = right_wrist.visible
	if left_wrist.visible:
		_draw_arm(left_wrist, -1.0, _left_elbow_ball)
	if right_wrist.visible:
		_draw_arm(right_wrist, 1.0, _right_elbow_ball)

func _shoulder(side: float) -> Vector3:
	var b := head.global_transform.basis
	return head.global_position \
		+ b.x * side * SHOULDER_SIDE \
		- b.y * SHOULDER_DOWN \
		- b.z * SHOULDER_BACK

func _elbow(shoulder: Vector3, wrist_pos: Vector3, wrist_basis: Basis, side: float) -> Vector3:
	var to_tip := wrist_pos - shoulder
	var dist: float = clamp(to_tip.length(), absf(UPPER_ARM - LOWER_ARM) + 0.001, UPPER_ARM + LOWER_ARM - 0.001)
	var cos_a: float = (UPPER_ARM * UPPER_ARM + dist * dist - LOWER_ARM * LOWER_ARM) / (2.0 * UPPER_ARM * dist)
	var angle := acos(clamp(cos_a, -1.0, 1.0))
	var dir := to_tip / dist
	# Blend wrist back-of-hand axis with gravity for swivel hint
	var wrist_hint := -wrist_basis.y
	var gravity_hint := Vector3(side * 0.2, -1.0, 0.0).normalized()
	var swivel := wrist_hint.lerp(gravity_hint, 0.0).normalized()
	var bend_dir := swivel - dir * dir.dot(swivel)
	if bend_dir.length_squared() < 0.0001:
		bend_dir = gravity_hint - dir * dir.dot(gravity_hint)
	bend_dir = bend_dir.normalized()
	return shoulder + dir * (UPPER_ARM * cos(angle)) + bend_dir * (UPPER_ARM * sin(angle))

func _draw_arm(wrist_node: XRNode3D, side: float, elbow_ball: MeshInstance3D) -> void:
	var shoulder := _shoulder(side)
	var elbow := _elbow(shoulder, wrist_node.global_position, wrist_node.global_transform.basis, side)
	elbow_ball.global_position = elbow
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_mesh.surface_add_vertex(shoulder)
	_mesh.surface_add_vertex(elbow)
	_mesh.surface_add_vertex(elbow)
	_mesh.surface_add_vertex(wrist_node.global_position)
	_mesh.surface_end()
