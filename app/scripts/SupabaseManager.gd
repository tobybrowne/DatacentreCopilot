extends Node

var auth_user = null

func sign_in(email, password):
	var auth_task = await Supabase.auth.sign_in(email, password).completed

	if auth_task.error == null:
		auth_user = auth_task.user
		print("Login Success!")
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

func insert_anchor(anchor: Anchor) -> bool:
	print("Inserting anchor: ", anchor.id, " / ", anchor.name, " / ml2_id=", anchor.ml2_id, " / is_reference=", anchor.is_reference)
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").insert([{
			"name": anchor.name,
			"ml2_id": anchor.ml2_id,
			"is_reference": anchor.is_reference,
		}])
	).completed

	if task.error == null:
		print("Anchor inserted: ", anchor.id)
		return true
	else:
		print("Error inserting anchor: ", task.error.message)
		return false

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
	# if auth_user == null:
	# 	return false

	# temp dummy user id
	var auth_user_id := '00000000-0000-0000-0000-000000000000';

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


func _ready() -> void:
	pass

func _process(_delta: float) -> void:
	pass
