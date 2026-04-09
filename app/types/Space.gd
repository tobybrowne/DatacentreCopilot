class_name Space

var id: String        # uuid from ML2
var name: String
var blob_path: String # path to the binary space export file in Supabase storage
var glb_path: String  # path to the glb export file in Supabase storage
var created_at: String
var updated_at: String

static func from_dict(data: Dictionary) -> Space:
	var space := Space.new()
	space.id = data.get("id", "")
	space.name = data.get("name", "")
	space.blob_path = data.get("blob_path", "")
	space.glb_path = data.get("glb_path", "")
	space.created_at = data.get("created_at", "")
	space.updated_at = data.get("updated_at", "")
	return space
