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


func get_documents(table: String) -> Array[Dictionary]:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from(table).select()
	).completed

	if task.error == null:
		var result: Array[Dictionary] = []
		result.assign(task.data)
		return result
	else:
		print("get_documents error: ", task.error.message)
		return []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
