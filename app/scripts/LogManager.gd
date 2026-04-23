extends Node

var _gesture_manager: GestureManager = null
var _location_manager: LocationManager = null

var _procedure: Procedure = null
var _site_id: String = ""
var _procedure_run_id: String = ""
var _current_step: Step = null


func _ready() -> void:
	print("LogManager: ready")


func setup(gm: GestureManager, lm: LocationManager) -> void:
	_gesture_manager = gm
	_location_manager = lm


func start_procedure(procedure: Procedure, site_id: String) -> void:
	_procedure = procedure
	if site_id.is_empty() and not procedure.building_id.is_empty():
		_site_id = await _fetch_site_id(procedure.building_id)
	else:
		_site_id = site_id
	print("LogManager: start_procedure log_type='%s' site_id='%s'" % [procedure.log_type, _site_id])
	_procedure_run_id = await _insert_procedure_run(procedure.id)
	print("LogManager: procedure_run_id='%s'" % _procedure_run_id)


func end_procedure() -> void:
	if _current_step:
		await _end_step(_current_step)
	_procedure = null
	_site_id = ""
	_procedure_run_id = ""
	_current_step = null


func on_step_changed(prev_step: Step, next_step: Step) -> void:
	print("LogManager: on_step_changed prev=%s next=%s procedure=%s" % [
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


# ── Recording ─────────────────────────────────────────────────────────────────

func _begin_step(step: Step) -> void:
	var log_type: String = _procedure.log_type

	if log_type in ["FULL", "GEOMETRY_ONLY"]:
		_gesture_manager.start_recording(_location_manager.get_calibration())

	if log_type in ["FULL", "CAMERA_ONLY"]:
		pass # TODO: CVCameraManager.start_step_recording()


func _end_step(step: Step) -> void:
	var log_type: String = _procedure.log_type
	var geometry_path := ""
	var camera_path := ""

	if log_type in ["FULL", "GEOMETRY_ONLY"]:
		var frames := _gesture_manager.stop_recording()
		geometry_path = await _upload_gesture_recording(frames, step.id)

	if log_type in ["FULL", "CAMERA_ONLY"]:
		pass # TODO: camera_path = await CVCameraManager.stop_step_recording(step.id)

	await _insert_log(step.id, geometry_path, camera_path)


# ── Upload ─────────────────────────────────────────────────────────────────────

func _upload_gesture_recording(frames: Array[PoseRec], step_id: String) -> String:
	if frames.is_empty():
		return ""

	# Each frame is a flat array: [timestamp_msec, ...12 floats per transform × 53 transforms]
	# Layout per transform: bxx bxy bxz byx byy byz bzx bzy bzz ox oy oz
	var frame_list := []
	for f in frames:
		var row: Array = [f.timestamp_msec]
		_append_transform(row, f.head_transform)
		for t in f.left_joints:
			_append_transform(row, t)
		for t in f.right_joints:
			_append_transform(row, t)
		frame_list.append(row)

	var tmp_path := "user://gesture_%s.json" % step_id
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if not file:
		push_warning("LogManager: failed to open temp file for gesture recording")
		return ""
	var json_str := JSON.stringify({"v": 1, "frames": frame_list})
	file.store_string(json_str)
	file.close()
	print("LogManager: gesture file size=%d frames=%d" % [json_str.length(), frame_list.size()])

	var remote_path := "gestures/%s_%s.json" % [_procedure_run_id, step_id]
	print("LogManager: uploading as user_id=%s" % (SupabaseManager.auth_user.id if SupabaseManager.auth_user else "null"))
	var task = await Supabase.storage.from("log_bucket").upload(remote_path, tmp_path, false).completed
	DirAccess.remove_absolute(tmp_path)

	if task.error != null:
		push_warning("LogManager: gesture upload failed — code=%s message=%s details=%s" % [task.error.code, task.error.message, task.error.details])
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




# ── Database ───────────────────────────────────────────────────────────────────

func _fetch_site_id(building_id: String) -> String:
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("buildings").select(["site_id"]).eq("id", building_id)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		push_warning("LogManager: failed to fetch site_id for building %s" % building_id)
		return ""
	return task.data[0].get("site_id", "")


func _insert_procedure_run(procedure_id: String) -> String:
	var user_id: String = SupabaseManager.auth_user.id if SupabaseManager.auth_user else ""
	print("LogManager: inserting procedure_run procedure_id=%s user_id=%s" % [procedure_id, user_id])
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("procedure_runs").insert([{
			"procedure_id": procedure_id,
			"user_id": user_id,
		}])
	).completed
	if task.error != null:
		push_warning("LogManager: failed to insert procedure_run — %s" % task.error.message)
		return ""
	if task.data == null or task.data.is_empty():
		push_warning("LogManager: procedure_run insert returned no data")
		return ""
	return task.data[0].get("id", "")


func _insert_log(step_id: String, geometry_path: String, camera_path: String) -> void:
	var user_id: String = SupabaseManager.auth_user.id if SupabaseManager.auth_user else ""
	var row := {
		"step_id": step_id,
		"site_id": _site_id,
		"user_id": user_id,
	}
	if not _procedure_run_id.is_empty():
		row["procedure_run_id"] = _procedure_run_id
	if not geometry_path.is_empty():
		row["geometry_recording_path"] = geometry_path
	if not camera_path.is_empty():
		row["camera_recording_path"] = camera_path

	var task = await Supabase.database.query(
		SupabaseQuery.new().from("logs").insert([row])
	).completed
	if task.error != null:
		push_warning("LogManager: failed to insert log — %s" % task.error.message)
