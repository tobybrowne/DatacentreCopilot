# Handles log recording, by calling the camera and gesture manager when needed (these implement recording for cam + geo respectively)
# mainly implements the state machine and uploads

extends Node

var _gesture_manager: GestureManager = null
var _anchor_manager: AnchorManager = null
var _camera_manager: Node = null

var _procedure: Procedure = null
var _site_id: String = ""
var _procedure_run_id: String = ""
var _current_step: Step = null
var _interacted_assets: Dictionary = {}  # asset_id -> true, deduplicated set


func _ready() -> void:
	print("LogRecordManager: ready")


func setup(gm: GestureManager, am: AnchorManager, cm: Node = null) -> void:
	_gesture_manager = gm
	_anchor_manager = am
	_camera_manager = cm


func start_procedure(procedure: Procedure, site_id: String) -> void:
	_procedure = procedure
	if site_id.is_empty() and not procedure.building_id.is_empty():
		_site_id = await SupabaseManager.get_building_site_id(procedure.building_id)
	else:
		_site_id = site_id
	print("LogRecordManager: start_procedure log_type='%s' site_id='%s'" % [procedure.log_type, _site_id])
	_procedure_run_id = await SupabaseManager.insert_procedure_run(procedure.id)
	print("LogRecordManager: procedure_run_id='%s'" % _procedure_run_id)


func end_procedure() -> void:
	if _current_step:
		await _end_step(_current_step)
	_procedure = null
	_site_id = ""
	_procedure_run_id = ""
	_current_step = null


func on_step_changed(prev_step: Step, next_step: Step) -> void:
	print("LogRecordManager: on_step_changed prev=%s next=%s procedure=%s" % [
		prev_step.id if prev_step else "null",
		next_step.id if next_step else "null",
		_procedure.id if _procedure else "null"
	])
	if not _procedure:
		return
	if prev_step:
		await _end_step(prev_step)
	_current_step = next_step
	_begin_step(next_step)


# called by AssetAnchorMarker when user interacts with an asset
func record_asset_interaction(asset_id: String) -> void:
	_interacted_assets[asset_id] = true


func _begin_step(step: Step) -> void:
	_interacted_assets.clear()
	var log_type: String = _procedure.log_type

	if log_type in ["FULL", "GEOMETRY_ONLY"]:
		var current_space_id := _anchor_manager.get_current_space_id()
		var offsets := _anchor_manager.get_space_offsets()
		var current_offset: Transform3D = offsets.get(current_space_id, Transform3D.IDENTITY)
		_gesture_manager.start_recording(_anchor_manager.get_calibration() * current_offset.affine_inverse())

	if log_type in ["FULL", "CAMERA_ONLY"]:
		if _camera_manager:
			_camera_manager.start_recording()


func _end_step(step: Step) -> void:
	var log_type: String = _procedure.log_type
	var geometry_path := ""
	var camera_path := ""

	if log_type in ["FULL", "GEOMETRY_ONLY"]:
		var frames := _gesture_manager.stop_recording()
		# upload geometry recording to supabase storage
		geometry_path = await _upload_gesture_recording(frames, step.id)

	if log_type in ["FULL", "CAMERA_ONLY"]:
		if _camera_manager:
			_camera_manager.stop_recording()
			var local_path: String = await _camera_manager.recording_stopped
			# upload camera recording to supabase storage
			camera_path = await _upload_camera_recording(local_path, step.id)

	var log_id := await SupabaseManager.insert_log(step.id, _site_id, _procedure_run_id, geometry_path, camera_path)

	if not log_id.is_empty():
		var all_asset_ids := _interacted_assets.keys()
		for aid: String in step.asset_ids:
			if aid not in all_asset_ids:
				all_asset_ids.append(aid)
		if not all_asset_ids.is_empty():
			await SupabaseManager.insert_log_assets(log_id, all_asset_ids)


func _upload_gesture_recording(frames: Array[PoseRec], step_id: String) -> String:
	if frames.is_empty():
		return ""

	# Each frame is a flat array: [timestamp_msec, ...12 floats per transform × 53 transforms]
	var frame_list := []
	for f in frames:
		var row: Array = [f.timestamp_msec]
		_append_transform(row, f.head_transform)
		for t in f.left_joints:
			_append_transform(row, t)
		for t in f.right_joints:
			_append_transform(row, t)
		row.append(1 if f.left_tracked  else 0)
		row.append(1 if f.right_tracked else 0)
		frame_list.append(row)

	# store data in a local temp file
	var tmp_path := "user://gesture_%s.json" % step_id
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		push_warning("LogRecordManager: failed to open temp file for gesture recording")
		return ""
	# TO-DO: should consider JSON alternatives, this is pretty heavy
	var json_str := JSON.stringify({"v": 1, "frames": frame_list})
	file.store_string(json_str)
	file.close()
	print("LogRecordManager: gesture file size=%d frames=%d" % [json_str.length(), frame_list.size()])

	# upload local temp file to supabase storage
	var remote_path := "gestures/%s_%s.json" % [_procedure_run_id, step_id]
	print("LogRecordManager: uploading as user_id=%s" % (SupabaseManager.auth_user.id if SupabaseManager.auth_user else "null"))
	var task = await Supabase.storage.from("log_bucket").upload(remote_path, tmp_path, false).completed
	DirAccess.remove_absolute(tmp_path)

	if task.error != null:
		push_warning("LogRecordManager: gesture upload failed — code=%s message=%s details=%s" % [task.error.code, task.error.message, task.error.details])
		return ""
	return remote_path

func _upload_camera_recording(local_path: String, step_id: String) -> String:
	if local_path.is_empty():
		return ""

	# upload local temp file to supabase storage
	var remote_path := "videos/%s_%s.mp4" % [_procedure_run_id, step_id]
	print("LogRecordManager: uploading camera recording as user_id=%s" % (SupabaseManager.auth_user.id if SupabaseManager.auth_user else "null"))
	var task = await Supabase.storage.from("log_bucket").upload(remote_path, local_path, false).completed
	DirAccess.remove_absolute(local_path)

	if task.error != null:
		push_warning("LogRecordManager: camera upload failed — code=%s message=%s details=%s" % [task.error.code, task.error.message, task.error.details])
		return ""
	return remote_path


# we collapse transform dicts to arrays, this saves a lot of space
func _append_transform(row: Array, t: Transform3D) -> void:
	row.append(snappedf(t.basis.x.x, 0.0001))
	row.append(snappedf(t.basis.x.y, 0.0001))
	row.append(snappedf(t.basis.x.z, 0.0001))
	row.append(snappedf(t.basis.y.x, 0.0001))
	row.append(snappedf(t.basis.y.y, 0.0001))
	row.append(snappedf(t.basis.y.z, 0.0001))
	row.append(snappedf(t.basis.z.x, 0.0001))
	row.append(snappedf(t.basis.z.y, 0.0001))
	row.append(snappedf(t.basis.z.z, 0.0001))
	row.append(snappedf(t.origin.x, 0.0001))
	row.append(snappedf(t.origin.y, 0.0001))
	row.append(snappedf(t.origin.z, 0.0001))


