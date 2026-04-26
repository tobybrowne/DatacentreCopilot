class_name NoteAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child

const COLOR := Color(0.95, 0.9, 0.3)   # warm yellow
const PREVIEW_LENGTH := 40


func _ready() -> void:
	if anchor.id.is_empty():
		return
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("notes").select().eq("anchor_id", anchor.id).range(0, 0)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		return

	var text: String = task.data[0].get("text", "")
	if text.length() > PREVIEW_LENGTH:
		text = text.left(PREVIEW_LENGTH) + "…"

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.04
	sphere.height = 0.08
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 0.3
	light.omni_range = 0.4
	add_child(light)

	var lbl := Label3D.new()
	lbl.text = text
	lbl.position = Vector3(0, 0.09, 0)
	lbl.font_size = 96
	lbl.pixel_size = 0.0005
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.no_depth_test = true
	lbl.modulate = COLOR
	add_child(lbl)
