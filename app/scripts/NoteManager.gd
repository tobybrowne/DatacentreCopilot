# Very thin class, just implements the logic for creating a new Note.
# All the note styling and retrieval is handled by AnchorManager and NoteAnchorMarker.

class_name NoteManager
extends Node

var _location_manager: LocationManager
var _anchor_manager: AnchorManager


func _ready() -> void:
	_location_manager = get_parent().get_node_or_null("LocationManager")
	_anchor_manager = get_parent().get_node_or_null("AnchorManager")


func create_note_at(world_pos: Vector3, text: String) -> void:
	var space_id := _location_manager.get_current_space_id()
	var glb_pos  := _anchor_manager.world_to_glb(world_pos)

	# Compute a vertical rotation facing the camera at creation time.
	# +Z of the note points toward the camera, Y stays world-up.
	var glb_rot := Quaternion.IDENTITY
	var camera := get_viewport().get_camera_3d()
	if camera:
		var to_cam := (camera.global_position - world_pos)
		to_cam.y = 0.0
		to_cam = to_cam.normalized()
		if to_cam.length_squared() > 0.001:
			var right := Vector3.UP.cross(to_cam).normalized()
			var up    := to_cam.cross(right).normalized()
			var world_basis := Basis(right, up, to_cam)
			glb_rot = (_anchor_manager.get_calibration().basis.inverse() * world_basis).get_rotation_quaternion()

	var anchor := Anchor.new()
	anchor.anchor_type  = Anchor.TYPE_NOTE
	anchor.name         = "note"
	anchor.space_id     = space_id
	anchor.glb_position = glb_pos
	anchor.glb_rotation = glb_rot

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
