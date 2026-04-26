class_name AssetAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child

const COLOR := Color(0.2, 0.5, 1.0)


func _ready() -> void:
	if anchor.id.is_empty():
		return
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("assets").select().eq("anchor_id", anchor.id).range(0, 0)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		return

	var row: Dictionary = task.data[0]
	var name: String = row.get("name", "")
	var asset_type: String = row.get("asset_type", "")

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.10
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = COLOR
	mat.emission_enabled = true
	mat.emission = COLOR
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = COLOR
	light.light_energy = 0.5
	light.omni_range = 0.5
	add_child(light)

	var lbl := Label3D.new()
	lbl.text = name if asset_type.is_empty() else "%s\n(%s)" % [name, asset_type]
	lbl.position = Vector3(0, 0.10, 0)
	lbl.font_size = 128
	lbl.pixel_size = 0.0005
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.no_depth_test = true
	lbl.modulate = COLOR
	add_child(lbl)
