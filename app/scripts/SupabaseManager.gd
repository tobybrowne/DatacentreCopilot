# Pretty boring, mainly implements getters/setters for Supabase, plus the sign_in function

extends Node

var auth_user = null

func sign_in(email, password):
	var auth_task = await Supabase.auth.sign_in(email, password).completed

	if auth_task.error == null:
		auth_user = auth_task.user
		print("Login Success! access_token: ", auth_task.user.access_token.substr(0, 40), "...")
		print("Supabase._auth after login: ", Supabase.auth._auth.substr(0, 40) if not Supabase.auth._auth.is_empty() else "EMPTY")
		return true
	else:
		print("Login Error: ", auth_task.error.message)
		return false


func get_procedures() -> Array[Procedure]:
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

func get_space(space_id: String) -> Space:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").select().eq("id", space_id).range(0, 0)
	).completed

	if task.error == null and task.data != null and not task.data.is_empty():
		return Space.from_dict(task.data[0])
	else:
		if task.error != null:
			print("get_space error: ", task.error.message)
		else:
			print("get_space error: null response (check Supabase connection)")
		return null

func get_space_blob(space: Space) -> PackedByteArray:
	var task = await Supabase.storage.from("spaces_bucket").download(space.blob_path, "", true).completed

	if task.error == null and task.data != null:
		return task.data
	else:
		if task.error != null:
			print("get_space_blob error: ", task.error.message)
		else:
			print("get_space_blob error: null response (check Supabase connection)")
		return PackedByteArray()

func get_user_site_id() -> String:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("users").select(["site_id"]).eq("id", auth_user.id if auth_user else "")
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		if task.error != null:
			print("get_user_site_id error: ", task.error.message)
		return ""
	return task.data[0].get("site_id", "")


func upsert_space(space: Space) -> bool:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").insert([{
			"id": space.id,
			"name": space.name,
			"site_id": space.site_id,
			"blob_path": space.blob_path,
			"glb_path": space.glb_path,
		}], true)
	).completed

	if task.error == null:
		return true
	else:
		print("upsert_space error: ", task.error.message)
		return false


func insert_anchor(anchor: Anchor) -> Anchor:
	var row := {
		"name": anchor.name,
		"anchor_type": anchor.anchor_type,
	}
	if anchor.ml2_id != null:
		row["ml2_id"] = anchor.ml2_id
	if not anchor.space_id.is_empty():
		row["space_id"] = anchor.space_id
	if anchor.glb_position != null:
		row["glb_position"] = {
			"x": anchor.glb_position.x,
			"y": anchor.glb_position.y,
			"z": anchor.glb_position.z,
		}
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").insert([row])
	).completed

	if task.error == null and task.data != null and not task.data.is_empty():
		anchor.id = task.data[0].get("id", "")
		return anchor
	else:
		if task.error != null:
			print("Error inserting anchor: ", task.error.message)
		return null

func update_anchor_glb_position(anchor_id: String, glb_position: Vector3) -> bool:
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


func get_sibling_spaces(space_id: String) -> Array[Space]:
	# First get the space to find its building_id
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").select().eq("id", space_id)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		if task.error != null:
			print("get_sibling_spaces error: ", task.error.message)
		return []
	var building_id: String = task.data[0].get("building_id", "")
	if building_id.is_empty():
		return []
	return await get_spaces_for_building(building_id)


func get_building_site_id(building_id: String) -> String:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("buildings").select(["site_id"]).eq("id", building_id)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		if task.error != null:
			print("get_building_site_id error: ", task.error.message)
		return ""
	return task.data[0].get("site_id", "")


func get_buildings() -> Array[Building]:
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
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("spaces").select().eq("building_id", building_id)
	).completed
	if task.error == null and task.data != null:
		var result: Array[Space] = []
		for row in task.data:
			result.append(Space.from_dict(row))
		return result
	if task.error != null:
		print("get_spaces_for_building error: ", task.error.message)
	return []


func get_routes() -> Array[Route]:
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


func insert_note(note: StickyNote) -> StickyNote:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("notes").insert([{"text": note.text, "anchor_id": note.anchor_id}])
	).completed
	if task.error == null and task.data != null and not task.data.is_empty():
		note.id = task.data[0].get("id", "")
		return note
	if task.error != null:
		print("insert_note error: ", task.error.message)
	return null


func get_notes_for_space(space_id: String) -> Array[StickyNote]:
	# Fetch note-type anchors for this space, then load the text from the notes table.
	var anchors_task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").select().eq("space_id", space_id).eq("anchor_type", "note")
	).completed
	if anchors_task.error != null or anchors_task.data == null:
		if anchors_task.error != null:
			print("get_notes_for_space anchors error: ", anchors_task.error.message)
		return []

	var result: Array[StickyNote] = []
	for anchor_row in anchors_task.data:
		var anchor_id: String = anchor_row.get("id", "")
		if anchor_id.is_empty():
			continue
		var pos = anchor_row.get("glb_position", null)
		if not pos is Dictionary:
			continue

		var notes_task = await Supabase.database.query(
			SupabaseQuery.new().from("notes").select().eq("anchor_id", anchor_id)
		).completed
		if notes_task.error != null or notes_task.data == null:
			continue
		for row in notes_task.data:
			var note := StickyNote.from_dict(row)
			note.glb_position = Vector3(pos.get("x", 0.0), pos.get("y", 0.0), pos.get("z", 0.0))
			result.append(note)
	return result


func remove_anchor(anchor_id: String) -> bool:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").delete().eq("id", anchor_id)
	).completed

	if task.error == null:
		print("Anchor removed: ", anchor_id)
		return true
	else:
		print("Error removing anchor: ", task.error.message)
		return false


func insert_procedure_run(procedure_id: String) -> String:
	var user_id: String = auth_user.id if auth_user else ""
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("procedure_runs").insert([{
			"procedure_id": procedure_id,
			"user_id": user_id,
		}])
	).completed
	if task.error != null:
		print("insert_procedure_run error: ", task.error.message)
		return ""
	if task.data == null or task.data.is_empty():
		print("insert_procedure_run error: no data returned")
		return ""
	return task.data[0].get("id", "")


func insert_log(step_id: String, site_id: String, procedure_run_id: String, geometry_path: String, camera_path: String) -> String:
	var user_id: String = auth_user.id if auth_user else ""
	var row := {
		"step_id": step_id,
		"site_id": site_id,
		"user_id": user_id,
	}
	if not procedure_run_id.is_empty():
		row["procedure_run_id"] = procedure_run_id
	if not geometry_path.is_empty():
		row["geometry_recording_path"] = geometry_path
	if not camera_path.is_empty():
		row["camera_recording_path"] = camera_path
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("logs").insert([row])
	).completed
	if task.error != null:
		print("insert_log error: ", task.error.message)
		return ""
	if task.data == null or task.data.is_empty():
		return ""
	return task.data[0].get("id", "")


func insert_log_assets(log_id: String, asset_ids: Array[String]) -> void:
	var rows := []
	for asset_id in asset_ids:
		rows.append({"log_id": log_id, "asset_id": asset_id})
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("log_assets").insert(rows)
	).completed
	if task.error != null:
		print("insert_log_assets error: ", task.error.message)


func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
