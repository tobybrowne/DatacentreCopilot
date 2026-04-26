class_name ContentAnchorMarker
extends Node3D

var anchor: Anchor       # set before add_child
var other_space := false # set before add_child — true for anchors in a different space

const COLOR_SAME  := Color(1.0, 0.55, 0.0)   # orange — current space
const COLOR_OTHER := Color(0.5, 0.3,  1.0)   # purple — other space


func _ready() -> void:
	var color := COLOR_OTHER if other_space else COLOR_SAME

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
		lbl.modulate = color
		add_child(lbl)
