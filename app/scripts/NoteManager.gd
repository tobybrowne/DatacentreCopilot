extends Node

var _app: Node3D
var _location_manager: LocationManager
var _note_nodes: Array[Node3D] = []


func setup(app: Node3D, location_manager: LocationManager) -> void:
	_app = app
	_location_manager = location_manager
	location_manager.calibrated.connect(_on_calibrated)


func create_note_at(world_pos: Vector3, text: String) -> void:
	var space_id := _location_manager.get_current_space_id()
	var glb_pos  := _location_manager.world_to_glb(world_pos)

	var anchor := Anchor.new()
	anchor.anchor_type  = Anchor.TYPE_NOTE
	anchor.name         = "note"
	anchor.space_id     = space_id
	anchor.glb_position = glb_pos

	var inserted_anchor: Anchor = await SupabaseManager.insert_anchor(anchor)
	if not inserted_anchor:
		push_warning("NoteManager: failed to insert anchor — showing note locally only")
		_spawn_note(world_pos, text)
		return

	var note := StickyNote.new()
	note.text      = text
	note.anchor_id = inserted_anchor.id

	await SupabaseManager.insert_note(note)
	_spawn_note(world_pos, text)


func clear() -> void:
	for node in _note_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_note_nodes.clear()


func _spawn_note(world_pos: Vector3, text: String) -> void:
	var node := StickyNote3D.new()
	_app.add_child(node)
	node.global_position = world_pos + Vector3(0.0, 0.05, 0.0)
	node.init(text)
	_note_nodes.append(node)


func _on_calibrated() -> void:
	_load_notes_for_space(_location_manager.get_current_space_id())


func _load_notes_for_space(space_id: String) -> void:
	for node in _note_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_note_nodes.clear()

	var notes: Array[StickyNote] = await SupabaseManager.get_notes_for_space(space_id)
	for note in notes:
		if note.glb_position == Vector3.ZERO and note.glb_position.length() == 0.0:
			continue
		var world_pos := _location_manager.glb_to_world(note.glb_position)
		_spawn_note(world_pos, note.text)
		await get_tree().process_frame
