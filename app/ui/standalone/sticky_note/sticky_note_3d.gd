class_name StickyNote3D
extends Node3D

const NOTE_W     := 0.12
const NOTE_H     := 0.10
const NOTE_COLOR := Color(1.0, 0.94, 0.35, 1.0)
const TEXT_COLOR := Color(0.15, 0.10, 0.0, 1.0)


func init(text: String) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(NOTE_W, NOTE_H)

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = NOTE_COLOR
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA

	var bg := MeshInstance3D.new()
	bg.mesh = quad
	bg.material_override = mat
	add_child(bg)

	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 52
	lbl.pixel_size = 0.00055
	lbl.modulate = TEXT_COLOR
	lbl.position = Vector3(0.0, 0.0, 0.001)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lbl.width = 200
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	add_child(lbl)


