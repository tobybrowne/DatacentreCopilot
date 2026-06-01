class_name StickyNote

var id: String = ""
var text: String = ""
var anchor_id: String = ""
var glb_position: Vector3  # runtime only - populated from anchor on load, not stored in notes table


static func from_dict(data: Dictionary) -> StickyNote:
	var note := StickyNote.new()
	note.id        = data.get("id", "")
	note.text      = data.get("text", "")
	note.anchor_id = data.get("anchor_id", "")
	return note
