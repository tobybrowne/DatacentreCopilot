class_name SpaceManager
extends Node

const DEVICE_GLB_DIR = "/storage/emulated/0/Android/data/com.magicleap.mappingtool/files"

func get_current_space() -> Space:
	var ext = _get_ext()
	if not ext:
		return null
	var uuid: String = ext.get_localization_map_uuid()
	if uuid.is_empty():
		return null

	var spaces: Array[Space] = await SupabaseManager.get_spaces()
	for space in spaces:
		if space.id == uuid:
			return space
	return null


# exports a given space to Supabase, including .glb and blob
func export_space(space: Space):
	var ext = _get_ext()
	if not ext:
		return null

	var uuid = space.id

	# Export binary localization map blob — synchronous C++ call, run on background
	# thread so the main loop continues processing XR events (required to avoid deadlock).
	print("export_space: starting blob export for ", uuid)
	var blob_result := []
	var thread := Thread.new()
	thread.start(func(): blob_result.append(ext.export_localization_map(uuid)))
	while thread.is_alive():
		await get_tree().process_frame
	thread.wait_to_finish()
	var blob: PackedByteArray = blob_result[0] if blob_result.size() > 0 else PackedByteArray()
	print("export_space: blob size = ", blob.size())
	if blob.is_empty():
		print("export_space: export_localization_map returned empty")
		return null

	# Write blob to temp file and upload
	var blob_path := "spaces/%s.blob" % uuid
	var blob_tmp := "user://space_%s.blob" % uuid
	var f := FileAccess.open(blob_tmp, FileAccess.WRITE)
	if not f:
		print("export_space: failed to open temp file")
		return null
	f.store_buffer(blob)
	f.close()

	var blob_upload = await Supabase.storage.from("spaces_bucket").upload(blob_path, blob_tmp, true).completed
	DirAccess.remove_absolute(blob_tmp)
	if blob_upload.error != null:
		print("export_space: blob upload failed — HTTP ", blob_upload.error.code, " ", blob_upload.error.message)
		return null

	# Upload GLB from device if the Spaces app has exported it
	var glb_path := ""
	var device_glb := "%s/{%s}.glb" % [DEVICE_GLB_DIR, uuid]
	if FileAccess.file_exists(device_glb):
		var glb_bytes := FileAccess.get_file_as_bytes(device_glb)
		print("export_space: GLB read ", glb_bytes.size(), " bytes from ", device_glb)
		var glb_tmp := "user://space_%s.glb" % uuid
		var gf := FileAccess.open(glb_tmp, FileAccess.WRITE)
		gf.store_buffer(glb_bytes)
		gf.close()
		glb_path = "spaces/%s.glb" % uuid
		var glb_upload = await Supabase.storage.from("spaces_bucket").upload(glb_path, glb_tmp, true).completed
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

	return space


# Downloads the space blob from Supabase and imports it onto the device.
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

	var new_uuid: String = ext.import_localization_map(blob)
	if new_uuid.is_empty():
		print("import_space: import_localization_map failed")
		return false

	print("import_space: imported '", space.name, "' as UUID ", new_uuid)
	return true


func _get_ext() -> Object:
	if not Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		print("SpaceManager: OpenXRMlLocalizationMapExtension not available")
		return null
	return Engine.get_singleton("OpenXRMlLocalizationMapExtension")


func get_all_local_spaces() -> Array[Space]:
	var ext = _get_ext()
	if not ext:
		return []

	var spaces: Array[Space] = []
	var maps: Array = ext.get_localization_maps()
	for map in maps:
		var space := Space.new()
		space.id = map["uuid"]
		space.name = map["name"]
		spaces.append(space)
	return spaces