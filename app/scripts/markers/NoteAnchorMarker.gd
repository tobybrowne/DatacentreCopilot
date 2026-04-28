class_name NoteAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child
var note_text: String = ""  # pre-set to skip DB query


func _ready() -> void:
	if anchor.id.is_empty() and note_text.is_empty():
		return
	if note_text.is_empty():
		var task = await Supabase.database.query(
			SupabaseQuery.new().from("notes").select().eq("anchor_id", anchor.id).range(0, 0)
		).completed
		if task.error != null or task.data == null or task.data.is_empty():
			return
		note_text = task.data[0].get("text", "")
	if note_text.is_empty():
		return
	var note := StickyNote3D.new()
	add_child(note)
	note.position = Vector3(0.0, 0.05, 0.0)
	note.init(note_text)
