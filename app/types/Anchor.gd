class_name Anchor

var id: String
var name: String
var ml2_id    # optional ID from ML2 localization map, if applicable
var is_reference: bool   # true = used as Kabsch reference point
var glb_position         # null or Vector3 — position in GLB mesh space
var space_id: String = ""

static func from_dict(data: Dictionary) -> Anchor:
	var anchor := Anchor.new()
	anchor.id = data.get("id", "")
	anchor.name = data.get("name", "")
	anchor.ml2_id = data.get("ml2_id", null)
	anchor.is_reference = data.get("is_reference", false)
	anchor.space_id = data.get("space_id", "")
	var pos = data.get("glb_position", null)
	if pos is Dictionary:
		anchor.glb_position = Vector3(
			pos.get("x", 0.0),
			pos.get("y", 0.0),
			pos.get("z", 0.0)
		)
	else:
		anchor.glb_position = null
	return anchor
