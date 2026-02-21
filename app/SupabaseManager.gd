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
			print("Row: ", row)
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
			print("Row: ", row)
			result.append(Anchor.from_dict(row))
		return result
	else:
		if task.error != null:
			print("get_anchors error: ", task.error.message)
		else:
			print("get_anchors error: null response (check Supabase connection)")
		return []

func insert_anchor(anchor: Anchor) -> bool:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").insert([{
			"id": anchor.id,
			"name": anchor.name
		}])
	).completed

	if task.error == null:
		print("Anchor inserted successfully.")
		return true
	else:
		print("Error inserting anchor: ", task.error.message)
		return false

func remove_anchor(anchor_id: String) -> bool:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("anchors").delete().eq("id", anchor_id)
	).completed

	if task.error == null:
		print("Anchor removed successfully.")
		return true
	else:
		print("Error removing anchor: ", task.error.message)
		return false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
