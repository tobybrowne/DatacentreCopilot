class_name CalibrationValidationMarker
extends Node3D

## Visualises calibration prediction error for a held-out reference anchor.
## Shows the ML2-tracked position (green), the GLB-predicted position (red),
## a connecting line, and the distance between them in metres.
##
## Must be added as a child of XROrigin3D at position Vector3.ZERO so that
## local-space coordinates match the tracked nodes' local-space positions.

var actual_node: Node3D       # the ML2-tracked node for this anchor
var glb_position: Vector3     # the anchor's stored GLB-space position
var anchor_name: String = ""
var anchor_mgr: AnchorManager

const COLOR_ACTUAL    := Color(0.0, 1.0, 0.3)
const COLOR_PREDICTED := Color(1.0, 0.2, 0.2)

var _actual_mi: MeshInstance3D
var _predicted_mi: MeshInstance3D
var _dist_label: Label3D
var _line_mesh: ImmediateMesh
var _line_mat: StandardMaterial3D


func _ready() -> void:
	_actual_mi = _make_sphere(COLOR_ACTUAL, 0.06)
	add_child(_actual_mi)

	_predicted_mi = _make_sphere(COLOR_PREDICTED, 0.06)
	add_child(_predicted_mi)

	_dist_label = Label3D.new()
	_dist_label.font_size = 128
	_dist_label.pixel_size = 0.0005
	_dist_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_dist_label.no_depth_test = true
	add_child(_dist_label)

	_line_mat = StandardMaterial3D.new()
	_line_mat.albedo_color = Color.WHITE
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.no_depth_test = true

	_line_mesh = ImmediateMesh.new()
	var line_mi := MeshInstance3D.new()
	line_mi.mesh = _line_mesh
	add_child(line_mi)


func _process(_delta: float) -> void:
	if not is_instance_valid(actual_node) or anchor_mgr == null:
		return

	var actual_pos := actual_node.position
	var predicted_pos := anchor_mgr.glb_to_world(glb_position)

	_actual_mi.position = actual_pos
	_predicted_mi.position = predicted_pos

	var dist := actual_pos.distance_to(predicted_pos)
	var label := anchor_name + "\n" if anchor_name != "" else ""
	_dist_label.text = label + "%.3f m" % dist
	_dist_label.position = (actual_pos + predicted_pos) * 0.5 + Vector3(0, 0.12, 0)

	_line_mesh.clear_surfaces()
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_mat)
	_line_mesh.surface_add_vertex(actual_pos)
	_line_mesh.surface_add_vertex(predicted_pos)
	_line_mesh.surface_end()


func _make_sphere(color: Color, radius: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	return mi
