extends Node

## Set to false to disable all Supabase calls (offline / local-only testing).
@export var enabled := true

var auth_user = null

func sign_in(email, password):
	if not enabled:
		print("SupabaseManager: offline mode — skipping sign_in")
		return false
	var auth_task = await Supabase.auth.sign_in(email, password).completed

	if auth_task.error == null:
		auth_user = auth_task.user
		print("Login Success!")
		return true
	else:
		print("Login Error: ", auth_task.error.message)
		return false


func get_procedures() -> Array[Procedure]:
	if not enabled:
		return []
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("procedures").select()
	).completed

	if task.error == null and task.data != null:
		var result: Array[Procedure] = []
		for row in task.data:
			result.append(Procedure.from_dict(row))
		return result
	else:
		if task.error != null:
			print("get_procedures error: ", task.error.message)
		else:
			print("get_procedures error: null response (check Supabase connection)")
		return []

func get_anchors() -> Array[Anchor]:
	if not enabled:
		return []
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").select()
	).completed

	if task.error == null and task.data != null:
		var result: Array[Anchor] = []
		for row in task.data:
			result.append(Anchor.from_dict(row))
		return result
	else:
		if task.error != null:
			print("get_anchors error: ", task.error.message)
		else:
			print("get_anchors error: null response (check Supabase connection)")
		return []

func get_spaces() -> Array[Space]:
	if not enabled:
		return []
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").select()
	).completed

	if task.error == null and task.data != null:
		var result: Array[Space] = []
		for row in task.data:
			result.append(Space.from_dict(row))
		return result
	else:
		if task.error != null:
			print("get_spaces error: ", task.error.message)
		else:
			print("get_spaces error: null response (check Supabase connection)")
		return []

func get_space_blob(space: Space) -> PackedByteArray:
	if not enabled:
		return PackedByteArray()
	var task = await Supabase.storage.from("spaces_bucket").download(space.blob_path).completed

	if task.error == null and task.data != null:
		return task.data
	else:
		if task.error != null:
			print("get_space_blob error: ", task.error.message)
		else:
			print("get_space_blob error: null response (check Supabase connection)")
		return PackedByteArray()

func upsert_space(space: Space) -> bool:
	if not enabled:
		return false
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").insert([{
			"id": space.id,
			"name": space.name,
			"blob_path": space.blob_path,
			"glb_path": space.glb_path,
		}], true)
	).completed

	if task.error == null:
		return true
	else:
		print("upsert_space error: ", task.error.message)
		return false


func insert_anchor(anchor: Anchor) -> bool:
	if not enabled:
		return false
	var row := {
		"name": anchor.name,
		"ml2_id": anchor.ml2_id,
		"is_reference": anchor.is_reference,
	}
	if not anchor.space_id.is_empty():
		row["space_id"] = anchor.space_id
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").insert([row])
	).completed

	if task.error == null:
		return true
	else:
		print("Error inserting anchor: ", task.error.message)
		return false

func update_anchor_glb_position(anchor_id: String, glb_position: Vector3) -> bool:
	if not enabled:
		return false
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").update({
			"glb_position": {
				"x": glb_position.x,
				"y": glb_position.y,
				"z": glb_position.z,
			}
		}).eq("id", anchor_id)
	).completed

	if task.error == null:
		print("glb_position updated for anchor ", anchor_id, " → ", glb_position)
		return true
	else:
		print("Error updating glb_position: ", task.error.message)
		return false

func update_user_glb_position(glb_position: Vector3) -> bool:
	if not enabled:
		return false
	# temp dummy user id
	var auth_user_id := '00000000-0000-0000-0000-000000000000'

	var task = await Supabase.database.query(
		SupabaseQuery.new().from("users").update({
			"glb_position": {
				"x": glb_position.x,
				"y": glb_position.y,
				"z": glb_position.z,
			}
		}).eq("id", auth_user_id)
	).completed

	if task.error == null:
		return true
	else:
		print("Error updating user glb_position: ", task.error.message)
		return false


func get_building_spaces_for_space(space_id: String) -> Array[BuildingSpace]:
	if not enabled:
		return []
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("building_spaces").select().eq("space_id", space_id)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		if task.error != null:
			print("get_building_spaces_for_space error: ", task.error.message)
		return []
	var building_id: String = task.data[0].get("building_id", "")
	if building_id.is_empty():
		return []

	var task2 = await Supabase.database.query(
		SupabaseQuery.new().from("building_spaces").select().eq("building_id", building_id)
	).completed
	if task2.error == null and task2.data != null:
		var result: Array[BuildingSpace] = []
		for row in task2.data:
			result.append(BuildingSpace.from_dict(row))
		return result
	else:
		if task2.error != null:
			print("get_building_spaces_for_space error: ", task2.error.message)
		return []


func get_buildings() -> Array[Building]:
	if not enabled:
		return []
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("buildings").select()
	).completed
	if task.error == null and task.data != null:
		var result: Array[Building] = []
		for row in task.data:
			result.append(Building.from_dict(row))
		return result
	if task.error != null:
		print("get_buildings error: ", task.error.message)
	return []


func get_spaces_for_building(building_id: String) -> Array[Space]:
	if not enabled:
		return []
	var bs_task = await Supabase.database.query(
		SupabaseQuery.new().from("building_spaces").select().eq("building_id", building_id)
	).completed
	if bs_task.error != null or bs_task.data == null or bs_task.data.is_empty():
		return []
	var ids := PackedStringArray()
	for row in bs_task.data:
		var sid: String = row.get("space_id", "")
		if not sid.is_empty():
			ids.append(sid)
	if ids.is_empty():
		return []
	# Fetch all spaces and filter client-side (plugin's In() filter has a key-case bug)
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").select()
	).completed
	if task.error == null and task.data != null:
		var result: Array[Space] = []
		for row in task.data:
			if row.get("id", "") in ids:
				result.append(Space.from_dict(row))
		return result
	if task.error != null:
		print("get_spaces_for_building error: ", task.error.message)
	return []


func get_routes() -> Array[Route]:
	if not enabled:
		return []
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("routes").select()
	).completed

	if task.error == null and task.data != null:
		var result: Array[Route] = []
		for row in task.data:
			result.append(Route.from_dict(row))
		return result
	else:
		if task.error != null:
			print("get_routes error: ", task.error.message)
		else:
			print("get_routes error: null response (check Supabase connection)")
		return []


func remove_anchor(anchor_id: String) -> bool:
	if not enabled:
		return false
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").delete().eq("id", anchor_id)
	).completed

	if task.error == null:
		print("Anchor removed: ", anchor_id)
		return true
	else:
		print("Error removing anchor: ", task.error.message)
		return false


func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
