class_name Anchor

const TYPE_REFERENCE := "reference"  # Kabsch calibration reference point
const TYPE_CONTENT   := "content"    # placed content marker
const TYPE_TEMP      := "temp"       # transient routing anchor, never rendered
const TYPE_NOTE      := "note"       # sticky note anchor
const TYPE_ASSET     := "asset"      # physical asset marker

var id: String
var name: String
var ml2_id           # optional ID from ML2 localization map, if applicable
var anchor_type: String = TYPE_CONTENT
var glb_position     # null or Vector3 — position in GLB mesh space
var space_id: String = ""

static func from_dict(data: Dictionary) -> Anchor:
	var anchor := Anchor.new()
	anchor.id = data.get("id", "")
	anchor.name = data.get("name", "")
	anchor.ml2_id = data.get("ml2_id", null)
	# Support both new anchor_type and legacy is_reference
	if data.has("anchor_type"):
		anchor.anchor_type = data.get("anchor_type", TYPE_CONTENT)
	else:
		anchor.anchor_type = TYPE_REFERENCE if data.get("is_reference", false) else TYPE_CONTENT
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
