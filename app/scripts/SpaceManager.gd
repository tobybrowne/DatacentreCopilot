class_name SpaceManager
extends Node

const DEVICE_GLB_DIR = "/storage/emulated/0/Android/data/com.magicleap.mappingtool/files"
const _UUID_MAP_PATH := "user://space_uuid_map.json"

# supabase_id → ml2_uuid, persisted on-device.
# Native spaces (created on this device) have supabase_id == ml2_uuid so they're never in this map.
var _uuid_map: Dictionary = {}


func _ready() -> void:
	var f := FileAccess.open(_UUID_MAP_PATH, FileAccess.READ)
	if not f:
		return
	var data = JSON.parse_string(f.get_as_text())
	f.close()
	if data is Dictionary:
		_uuid_map = data


func _save_uuid_map() -> void:
	var f := FileAccess.open(_UUID_MAP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_uuid_map))
		f.close()


# Returns the ML2 UUID for a given Supabase space ID.
# For native spaces (created on this device) the two are identical.
func get_ml2_uuid(supabase_id: String) -> String:
	return _uuid_map.get(supabase_id, supabase_id)


# Reverse lookup: given an ML2 UUID from the extension, returns the Supabase ID.
# Falls back to the ml2_uuid itself for native spaces.
func get_supabase_id(ml2_uuid: String) -> String:
	for supabase_id: String in _uuid_map:
		if _uuid_map[supabase_id] == ml2_uuid:
			return supabase_id
	return ml2_uuid


func is_space_local(supabase_id: String) -> bool:
	var ext = _get_ext()
	if not ext:
		return false

	# check if any of the locally stored maps in the extension match this Supabase ID (via the mapping)
	for m in ext.get_localization_maps():
		if get_supabase_id(m.get("uuid", "")) == supabase_id:
			return true
	return false


# NOTE: need to figure out exactly how this works before using
# I think ext.get_localization_map_uuid() will just return the UUID of the "current" map in Spaces,
# regardless of whether it's actually localised
# (not used anywhere yet)
func get_current_space() -> Space:
	var ext = _get_ext()
	if not ext:
		return null
	var ml2_uuid: String = ext.get_localization_map_uuid()
	if ml2_uuid.is_empty():
		return null
	var supabase_id := get_supabase_id(ml2_uuid)
	var spaces: Array[Space] = await SupabaseManager.get_spaces()
	for space in spaces:
		if space.id == supabase_id:
			return space
	return null


# exports a given space to Supabase, including .glb and blob
func export_space(space: Space):
	var ext = _get_ext()
	if not ext:
		return null

	var ml2_uuid := get_ml2_uuid(space.id)

	# Export binary localization map blob — synchronous C++ call, run on background
	# thread so the main loop continues processing XR events (required to avoid deadlock).
	print("export_space: starting blob export for ", ml2_uuid)
	var blob_result := []
	var thread := Thread.new()
	thread.start(func(): blob_result.append(ext.export_localization_map(ml2_uuid)))
	while thread.is_alive():
		await get_tree().process_frame
	thread.wait_to_finish()
	var blob: PackedByteArray = blob_result[0] if blob_result.size() > 0 else PackedByteArray()
	print("export_space: blob size = ", blob.size())
	if blob.is_empty():
		print("export_space: export_localization_map returned empty")
		return null

	# Write blob to temp file and upload (storage path uses Supabase ID)
	var blob_path := "spaces/%s.blob" % space.id
	var blob_tmp := "user://space_%s.blob" % space.id
	var f := FileAccess.open(blob_tmp, FileAccess.WRITE)
	if not f:
		print("export_space: failed to open temp file")
		return null
	f.store_buffer(blob)
	f.close()

	var blob_upload = await Supabase.storage.from("spaces_bucket").upload(blob_path, blob_tmp, false).completed
	DirAccess.remove_absolute(blob_tmp)
	if blob_upload.error != null:
		print("export_space: blob upload failed — HTTP ", blob_upload.error.code, " ", blob_upload.error.message)
		return null

	# Upload GLB from device if the Spaces app has exported it
	var glb_path := ""
	var device_glb := "%s/{%s}.glb" % [DEVICE_GLB_DIR, ml2_uuid]
	if FileAccess.file_exists(device_glb):
		var glb_bytes := FileAccess.get_file_as_bytes(device_glb)
		print("export_space: GLB read ", glb_bytes.size(), " bytes from ", device_glb)
		var glb_tmp := "user://space_%s.glb" % space.id
		var gf := FileAccess.open(glb_tmp, FileAccess.WRITE)
		gf.store_buffer(glb_bytes)
		gf.close()
		glb_path = "spaces/%s.glb" % space.id
		var glb_upload = await Supabase.storage.from("spaces_bucket").upload(glb_path, glb_tmp, false).completed
		DirAccess.remove_absolute(glb_tmp)
		if glb_upload.error != null:
			print("export_current_space: GLB upload failed (continuing without GLB) — ", glb_upload.error.message)
			glb_path = ""
	else:
		print("export_space: no GLB found at ", device_glb, " — export from Spaces app first")

	space.blob_path = blob_path
	space.glb_path = glb_path

	var ok := await SupabaseManager.upsert_space(space)
	if not ok:
		print("export_space: DB upsert failed")
		return null


# downloads the space blob from Supabase and imports it onto the device.
# saves supabase_id → ml2_uuid mapping if the assigned UUID differs from the Supabase ID.
func import_space(space: Space) -> bool:
	var ext = _get_ext()
	if not ext:
		return false

	if space.blob_path.is_empty():
		print("import_space: space has no blob_path")
		return false

	var blob: PackedByteArray = await SupabaseManager.get_space_blob(space)
	if blob.is_empty():
		print("import_space: failed to download blob")
		return false

	var ml2_uuid: String = ext.import_localization_map(blob)
	if ml2_uuid.is_empty():
		print("import_space: import_localization_map failed")
		return false

	if ml2_uuid != space.id:
		_uuid_map[space.id] = ml2_uuid
		_save_uuid_map()

	print("import_space: imported '", space.name, "' supabase=", space.id, " ml2=", ml2_uuid)
	return true



# delete_space_local is disabled — IMapManager::DeleteMap (txn 14) requires
# com.magicleap.permission.PW_MAP which is signature-protected and not grantable
# to third-party apps. Revisit if ML exposes this via SPACE_MANAGER or enterprise MDM.
#func delete_space_local(space: Space) -> bool:
#	var ext = _get_ext()
#	if not ext:
#		return false
#	var ml2_uuid := get_ml2_uuid(space.id)
#	print("delete_space_local: calling delete_localization_map(", ml2_uuid, ")")
#	var ok: bool = ext.delete_localization_map(ml2_uuid)
#	if not ok:
#		print("delete_space_local: FAILED")
#		return false
#	_uuid_map.erase(space.id)
#	_save_uuid_map()
#	print("delete_space_local: success, uuid map updated")
#	return true


func ensure_space_local(space: Space) -> bool:
	if is_space_local(space.id):
		return true
	print("SpaceManager: space not local — importing ", space.id)
	var ok := await import_space(space)
	if not ok:
		push_warning("SpaceManager: import failed for space ", space.id)
	return ok


# Returns all locally stored spaces with their Supabase IDs.
func get_all_local_spaces() -> Array[Space]:
	var ext = _get_ext()
	if not ext:
		return []
	var spaces: Array[Space] = []
	for map in ext.get_localization_maps():
		var space := Space.new()
		space.id = get_supabase_id(map["uuid"])
		space.name = map["name"]
		spaces.append(space)
	return spaces


func _get_ext() -> Object:
	if not Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		print("SpaceManager: OpenXRMlLocalizationMapExtension not available")
		return null
	return Engine.get_singleton("OpenXRMlLocalizationMapExtension")
