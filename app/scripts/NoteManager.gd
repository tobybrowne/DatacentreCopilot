extends Node

var _location_manager: LocationManager
var _anchor_manager: AnchorManager


func setup(location_manager: LocationManager, anchor_manager: AnchorManager) -> void:
	_location_manager = location_manager
	_anchor_manager = anchor_manager


func create_note_at(world_pos: Vector3, text: String) -> void:
	var space_id := _location_manager.get_current_space_id()
	var glb_pos  := _location_manager.world_to_glb(world_pos)

	var anchor := Anchor.new()
	anchor.anchor_type  = Anchor.TYPE_NOTE
	anchor.name         = "note"
	anchor.space_id     = space_id
	anchor.glb_position = glb_pos

	var inserted_anchor: Anchor = await SupabaseManager.insert_anchor(anchor)
	if inserted_anchor:
		var note := StickyNote.new()
		note.text      = text
		note.anchor_id = inserted_anchor.id
		await SupabaseManager.insert_note(note)
	else:
		push_warning("NoteManager: failed to insert anchor — showing note locally only")
		inserted_anchor = anchor

	_anchor_manager.spawn_note_marker(inserted_anchor, text, world_pos)


func clear() -> void:
	_anchor_manager.clear_note_markers()
