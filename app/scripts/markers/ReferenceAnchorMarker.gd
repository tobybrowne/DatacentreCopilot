class_name ReferenceAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child

const COLOR_COMPLETE   := Color(1.0, 0.85, 0.0)   # yellow - has glb_position
const COLOR_INCOMPLETE := Color(0.2, 0.8,  1.0)   # cyan   - newly placed, no glb_position yet


func _ready() -> void:
	var color := COLOR_COMPLETE if anchor.glb_position != null else COLOR_INCOMPLETE
	var label_color := color

	# In calibration-validation mode, draw the pure (calibration) reference anchors
	# green to match the actual-position spheres of the held-out validation markers.
	# The label keeps the default white so it matches the other markers' text.
	if DevConfig.CALIBRATION_VALIDATION and anchor.glb_position != null:
		color = CalibrationValidationMarker.COLOR_ACTUAL
		label_color = Color.WHITE

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.10
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.5
	light.omni_range = 0.5
	add_child(light)

	if anchor.name != "":
		var lbl := Label3D.new()
		lbl.text = anchor.name
		lbl.position = Vector3(0, 0.10, 0)
		lbl.font_size = 128
		lbl.pixel_size = 0.0005
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.no_depth_test = true
		lbl.modulate = label_color
		add_child(lbl)
