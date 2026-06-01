extends Node
class_name AnchorManager

## ML2 spatial anchor lifecycle, Kabsch calibration, and building-wide visualisation.
## Must be a child of XROrigin3D.

var _ml_mgr: Node
var _next_num := 1

# ── Anchor data ───────────────────────────────────────────────────────────────
var _all_anchors: Dictionary = {}       # supabase_id → Anchor
var _ref_anchors: Dictionary = {}       # ml2_id → Anchor (current space, has glb_position)
var _desktop_content: Array[Anchor] = []
var _pending_save: Dictionary = {}      # ml2_uuid → Node3D (write glb_position after calibration)

# Kabsch calibration
var _kabsch_src: Array[Vector3] = []
var _kabsch_nodes: Array[Node3D] = []
var _kabsch_names: Array[String] = []
var _calibration := Transform3D.IDENTITY
var _calibrated := false       # true once we have any valid calibration transform
var _space_calibrated := false # true once the *current* space's calibration is ready
var _last_kabsch_error := 0.0

# Building stitching: space_id → Transform3D
var _space_offsets: Dictionary = {}
var _current_space_id := ""

# Virtual markers (non-ML2, positioned by GLB coords): [{marker: Node3D, anchor: Anchor}]
var _virtual_markers: Array[Dictionary] = []

# Calibration validation (held-out reference anchors)
var _holdout_anchors: Dictionary = {}   # ml2_id → Anchor (excluded from Kabsch)
var _holdout_nodes: Dictionary = {}     # ml2_id → Node3D (their tracked nodes once found)
var _validation_markers: Array[Node3D] = []

# Cross-space alignment visualisation
var _prev_calibration := Transform3D.IDENTITY
var _prev_space_id := ""
var _cross_space_markers: Array[Node3D] = []

# ML2 tracking
var tracked_nodes: Dictionary = {}     # ml2_uuid → Node3D
var _retry_uuids: Dictionary = {}
var _storage_pending: Array[String] = []
var _storage_retry_timer := 0.0
const RETRY_DELAY := 3.0
const STORAGE_RETRY_INTERVAL := 2.0

const RECALIB_MOVE_THRESHOLD := 0.005  # 5 mm
var _kabsch_snapshot: Array[Vector3] = []  # last positions used for calibration
var _periodic_recalib_timer := 0.0

var _anchor_editing := false

signal calibrated
signal space_localized(uuid: String)
signal anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool)
signal anchor_untracked(uuid: StringName)


func _ready() -> void:
	if not ClassDB.class_exists("OpenXRMlSpatialAnchorManager"):
		push_warning("AnchorManager: OpenXRMlSpatialAnchorManager unavailable - spatial anchors disabled.")
		return
	_ml_mgr = ClassDB.instantiate("OpenXRMlSpatialAnchorManager")
	_ml_mgr.connect("openxr_ml_spatial_anchor_tracked", _on_ml_anchor_tracked)
	_ml_mgr.connect("openxr_ml_spatial_anchor_untracked", _on_anchor_untracked)
	_ml_mgr.connect("openxr_ml_spatial_anchor_create_failed", _on_create_failed)
	_ml_mgr.connect("openxr_ml_spatial_anchor_load_failed", _on_load_failed)
	_ml_mgr.tree_entered.connect(_on_mgr_entered_tree)
	get_parent().add_child.call_deferred(_ml_mgr)


func _on_mgr_entered_tree() -> void:
	pass


func _process(delta: float) -> void:
	if not _storage_pending.is_empty() and _ml_mgr:
		_storage_retry_timer -= delta
		if _storage_retry_timer <= 0.0:
			_storage_retry_timer = STORAGE_RETRY_INTERVAL
			print("AnchorManager: retrying ", _storage_pending.size(), " pending anchors")
			for uuid in _storage_pending.duplicate():
				_ml_mgr.call("load_anchor", StringName(uuid))

	if _calibrated and _kabsch_nodes.size() >= 2 and _kabsch_snapshot.size() == _kabsch_nodes.size():
		if DevConfig.PERIODIC_RECALIBRATION:
			_periodic_recalib_timer += delta
			if _periodic_recalib_timer >= DevConfig.PERIODIC_RECALIBRATION_INTERVAL:
				_periodic_recalib_timer = 0.0
				_refresh_calibration()
		else:
			for i in _kabsch_nodes.size():
				if not is_instance_valid(_kabsch_nodes[i]):
					break
				if _kabsch_nodes[i].position.distance_to(_kabsch_snapshot[i]) >= RECALIB_MOVE_THRESHOLD:
					_refresh_calibration()
					break


# ── Calibration API ───────────────────────────────────────────────────────────

# loads anchors from supabase and runs calibration (called by LocationManager)
func calibrate_to_space(space_id: String, p_space_offsets: Dictionary, p_anchors: Array[Anchor], p_spaces: Array[Space]) -> void:
	var _t0 := Time.get_ticks_msec()
	if _calibrated:
		_prev_calibration = _calibration
		_prev_space_id = _current_space_id

	_space_offsets = p_space_offsets
	_building_spaces = p_spaces

	var _t1 := Time.get_ticks_msec()
	_all_anchors.clear()
	var next_num := 1
	for anchor in p_anchors:
		_all_anchors[anchor.id] = anchor
		if anchor.name.is_valid_int():
			next_num = max(next_num, anchor.name.to_int() + 1)
	_next_num = next_num
	print("[TIMING] process anchors: ", Time.get_ticks_msec() - _t1, "ms")

	_setup_space_for_calibration(space_id)
	print("[TIMING] calibrate_to_space total: ", Time.get_ticks_msec() - _t0, "ms")


func get_calibration() -> Transform3D:
	return _calibration

func world_to_glb(world_pos: Vector3) -> Vector3:
	return _calibration.affine_inverse() * world_pos

func glb_to_world(glb_pos: Vector3) -> Vector3:
	return _calibration * glb_pos

func world_to_local(building_pos: Vector3) -> Vector3:
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return _calibration * (current_offset.affine_inverse() * building_pos)

func get_all_anchors() -> Dictionary:
	return _all_anchors

func get_space_offsets() -> Dictionary:
	return _space_offsets

func get_building_spaces() -> Array[Space]:
	return _building_spaces


var _building_spaces: Array[Space] = []

func get_last_kabsch_error() -> float:
	return _last_kabsch_error

# Returns one dict per Kabsch pair: ml2_id, current world pos, and stored GLB pos.
func get_kabsch_pairs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for i in _kabsch_src.size():
		if not is_instance_valid(_kabsch_nodes[i]):
			continue
		var ml2_id := ""
		for uuid in tracked_nodes:
			if tracked_nodes[uuid] == _kabsch_nodes[i]:
				ml2_id = uuid
				break
		result.append({
			"ml2_id": ml2_id,
			"world_pos": _v3_dict(_kabsch_nodes[i].position),
			"glb_pos": _v3_dict(_kabsch_src[i]),
		})
	return result


func _v3_dict(v: Vector3) -> Dictionary:
	return {"x": snappedf(v.x, 0.0001), "y": snappedf(v.y, 0.0001), "z": snappedf(v.z, 0.0001)}

func get_space_anchor_xr_positions() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for anchor in _all_anchors.values():
		if anchor.space_id != _current_space_id or not anchor.ml2_id:
			continue
		var node: Node3D = tracked_nodes.get(anchor.ml2_id)
		if not is_instance_valid(node):
			continue
		result.append({
			"name": anchor.name,
			"anchor_type": anchor.anchor_type,
			"xr_pos": _v3_dict(node.position),
		})
	return result


func get_current_space_id() -> String:
	return _current_space_id

func get_ml2_anchors(space_id: String) -> Array[Anchor]:
	var result: Array[Anchor] = []
	for anchor in _all_anchors.values():
		if anchor.space_id == space_id and anchor.ml2_id:
			result.append(anchor)
	return result

func ref_anchor_count(space_id: String) -> int:
	var count := 0
	for anchor in _all_anchors.values():
		if anchor.space_id == space_id and anchor.anchor_type == Anchor.TYPE_REFERENCE and anchor.glb_position != null:
			count += 1
	return count


## Create a transient anchor at an ML2 local-space position, saving the computed
## GLB position to Supabase. Returns the new Supabase UUID or "" on failure.
func create_temp_anchor(local_pos: Vector3) -> String:
	if not _calibrated:
		push_warning("AnchorManager: not calibrated - cannot create content anchor")
		return ""
	var glb_pos: Vector3 = _calibration.affine_inverse() * local_pos
	var anchor := Anchor.new()
	anchor.name         = "user_position"
	anchor.anchor_type  = Anchor.TYPE_TEMP
	anchor.glb_position = glb_pos
	anchor.space_id     = _current_space_id
	var inserted: Anchor = await SupabaseManager.insert_anchor(anchor)
	if not inserted or inserted.id.is_empty():
		push_warning("AnchorManager: failed to insert content anchor")
		return ""
	_building_spaces.clear()  # force re-fetch on next calibrate
	print("AnchorManager: created content anchor ", inserted.id, " at glb ", glb_pos)
	return inserted.id


# ── ML2 anchor tracking API ───────────────────────────────────────────────────

func set_next_num(n: int) -> void:
	_next_num = n


func load_anchor_from_ml2(uuid: String) -> void:
	if not _ml_mgr:
		return
	if uuid not in _storage_pending:
		_storage_pending.append(uuid)
	_retry_uuids[uuid] = 0
	_ml_mgr.call("load_anchor", StringName(uuid))


func place_anchor(world_transform: Transform3D) -> void:
	if not _ml_mgr:
		return
	print("AnchorManager: placing anchor at ", world_transform.origin)
	_ml_mgr.call("create_anchor", world_transform)


func remove_anchor(anchor: Anchor) -> void:
	if not _ml_mgr:
		return
	if anchor.ml2_id != null:
		_ml_mgr.call("untrack_anchor", anchor.ml2_id)
	SupabaseManager.remove_anchor(str(anchor.id))


func get_anchor_near(pos: Vector3, radius: float) -> Anchor:
	for uuid in tracked_nodes:
		var node: Node3D = tracked_nodes[uuid]
		if is_instance_valid(node) and node.global_position.distance_to(pos) <= radius:
			for anchor in _all_anchors.values():
				if str(anchor.ml2_id) == uuid:
					return anchor
	return null


func set_anchor_editing(editing: bool) -> void:
	_anchor_editing = editing


func clear_markers() -> void:
	for entry in _virtual_markers:
		if is_instance_valid(entry.marker):
			entry.marker.queue_free()
	_virtual_markers.clear()
	for node in tracked_nodes.values():
		if is_instance_valid(node):
			for child in node.get_children():
				child.queue_free()
	for m in _validation_markers:
		if is_instance_valid(m):
			m.queue_free()
	_validation_markers.clear()
	for m in _cross_space_markers:
		if is_instance_valid(m):
			m.queue_free()
	_cross_space_markers.clear()


func spawn_note_marker(anchor: Anchor, text: String, world_pos: Vector3) -> void:
	var marker := NoteAnchorMarker.new()
	marker.anchor = anchor
	marker.note_text = text
	get_parent().add_child(marker)
	marker.global_position = world_pos
	marker.basis = _calibration.basis * Basis(anchor.glb_rotation)
	_virtual_markers.append({ "marker": marker, "anchor": anchor })


func clear_note_markers() -> void:
	var remaining: Array[Dictionary] = []
	for entry in _virtual_markers:
		if entry.anchor.anchor_type == Anchor.TYPE_NOTE:
			if is_instance_valid(entry.marker):
				entry.marker.queue_free()
		else:
			remaining.append(entry)
	_virtual_markers = remaining


# ── Anchor loading ────────────────────────────────────────────────────────────



# ── Calibration internals ─────────────────────────────────────────────────────

# iterates through the anchors loaded from the database
# initialise inputs to the kabsch algorithm
# call ML2 apis to load reference anchors
func _setup_space_for_calibration(space_id: String) -> void:
	_ref_anchors.clear()
	_desktop_content.clear()
	_kabsch_src.clear()
	_kabsch_nodes.clear()
	_kabsch_names.clear()
	_holdout_anchors.clear()
	_holdout_nodes.clear()
	for m in _validation_markers:
		if is_instance_valid(m):
			m.queue_free()
	_validation_markers.clear()
	for m in _cross_space_markers:
		if is_instance_valid(m):
			m.queue_free()
	_cross_space_markers.clear()
	_space_calibrated = false
	_current_space_id = space_id

	# Collect all valid reference anchors for this space
	var valid_refs: Array = []
	for anchor in _all_anchors.values():
		if anchor.space_id != space_id or anchor.anchor_type != Anchor.TYPE_REFERENCE:
			continue
		if anchor.glb_position != null and anchor.ml2_id:
			valid_refs.append(anchor)
		else:
			print("AnchorManager: ref anchor ", anchor.id, " skipped - missing glb_position or ml2_id")

	# Split into calibration vs held-out sets when validation mode is active
	var calib_refs: Array = []
	if DevConfig.CALIBRATION_VALIDATION and valid_refs.size() > DevConfig.CALIBRATION_VALIDATION_MIN_ANCHORS:
		if not DevConfig.CALIBRATION_ANCHOR_NAMES.is_empty():
			var pinned: Array = valid_refs.filter(func(a): return a.name in DevConfig.CALIBRATION_ANCHOR_NAMES)
			if pinned.is_empty():
				print("AnchorManager: CALIBRATION_ANCHOR_NAMES had no matches - falling back to random")
			else:
				calib_refs = pinned
				for a in valid_refs:
					if not a.name in DevConfig.CALIBRATION_ANCHOR_NAMES:
						_holdout_anchors[a.ml2_id] = a
				print("AnchorManager: pinned calibration anchors: ", calib_refs.map(func(a): return a.name))
		if calib_refs.is_empty():
			valid_refs.shuffle()
			var n_holdout := valid_refs.size() - DevConfig.CALIBRATION_VALIDATION_MIN_ANCHORS
			for i in valid_refs.size():
				if i < n_holdout:
					_holdout_anchors[valid_refs[i].ml2_id] = valid_refs[i]
				else:
					calib_refs.append(valid_refs[i])
		print("AnchorManager: validation mode - ", calib_refs.size(), " calibration anchors, ", _holdout_anchors.size(), " held out")
	else:
		calib_refs = valid_refs

	# Load calibration anchors into Kabsch
	for anchor in calib_refs:
		_ref_anchors[anchor.ml2_id] = anchor
		var already_tracked: Node3D = tracked_nodes.get(anchor.ml2_id)
		if already_tracked:
			_kabsch_src.append(anchor.glb_position)
			_kabsch_nodes.append(already_tracked)
			_kabsch_names.append(anchor.name)
		else:
			load_anchor_from_ml2(anchor.ml2_id)

	# Load held-out anchors via ML2 (for actual-position tracking) but not into Kabsch
	for ml2_id in _holdout_anchors:
		var already_tracked: Node3D = tracked_nodes.get(ml2_id)
		if already_tracked:
			_holdout_nodes[ml2_id] = already_tracked
		else:
			load_anchor_from_ml2(ml2_id)

	# Handle non-reference anchors
	for anchor in _all_anchors.values():
		if anchor.space_id != space_id or anchor.anchor_type == Anchor.TYPE_TEMP or anchor.anchor_type == Anchor.TYPE_REFERENCE:
			continue
		if anchor.ml2_id != null:
			if not tracked_nodes.has(anchor.ml2_id):
				load_anchor_from_ml2(anchor.ml2_id)
		else:
			_desktop_content.append(anchor)

	print("AnchorManager: setup space ", space_id,
			" - ", _ref_anchors.size(), " ref anchors, ", _kabsch_src.size(), " already tracked")
	if _kabsch_src.size() >= 2:
		await _try_calibrate()


func _try_calibrate() -> void:
	if _kabsch_src.size() < 2:
		print("AnchorManager: need ≥2 reference pairs (have ", _kabsch_src.size(), ")")
		return

	var _t0 := Time.get_ticks_msec()
	var kabsch_dst: Array[Vector3] = []
	for node in _kabsch_nodes:
		kabsch_dst.append(node.position)

	var first_calibration := not _space_calibrated
	_calibration = Kabsch.compute_yaw_locked(_kabsch_src, kabsch_dst)
	_calibrated = true
	_space_calibrated = true
	_kabsch_snapshot = kabsch_dst
	print("[TIMING] Kabsch compute: ", Time.get_ticks_msec() - _t0, "ms")

	var total_err := 0.0
	for i in _kabsch_src.size():
		var predicted := _calibration * _kabsch_src[i]
		var err := predicted.distance_to(kabsch_dst[i])
		total_err += err
		if DevConfig.ANCHOR_VERBOSE_LOG:
			var g := _kabsch_src[i]
			var x := kabsch_dst[i]
			print("  ref[", _kabsch_names[i], "] glb=(", snappedf(g.x,0.001), ",", snappedf(g.y,0.001), ",", snappedf(g.z,0.001), ") xr=(", snappedf(x.x,0.001), ",", snappedf(x.y,0.001), ",", snappedf(x.z,0.001), ") err=", snappedf(err,0.001), "m")
	_last_kabsch_error = total_err / _kabsch_src.size()
	print("AnchorManager: calibrated from ", _kabsch_src.size(), " reference points - avg error ", snappedf(_last_kabsch_error, 0.001), "m")

	if not first_calibration:
		return

	# Emit and let signal handlers (wall rebuild, bbox visuals) run, then give a frame to render
	var _t1 := Time.get_ticks_msec()
	calibrated.emit()
	print("[TIMING] calibrated.emit (wall+bbox rebuild): ", Time.get_ticks_msec() - _t1, "ms")
	await get_tree().process_frame

	var _t2 := Time.get_ticks_msec()
	_spawn_ready_validation_markers()
	_spawn_cross_space_markers()
	print("[TIMING] validation+cross-space markers: ", Time.get_ticks_msec() - _t2, "ms")

	# Keep old markers visible until new ones are fully placed, then swap
	var old_markers := _virtual_markers.duplicate()
	_virtual_markers.clear()

	# Spread virtual marker placement across frames — 10 per frame to avoid a single-frame spike
	var _t3 := Time.get_ticks_msec()
	var placed := 0
	for anchor in _desktop_content:
		_place_virtual_marker(anchor, false)
		placed += 1
		if placed % 10 == 0:
			await get_tree().process_frame

	for anchor in _all_anchors.values():
		if anchor.space_id == _current_space_id or anchor.glb_position == null:
			continue
		if anchor.anchor_type != Anchor.TYPE_CONTENT and anchor.anchor_type != Anchor.TYPE_ASSET and anchor.anchor_type != Anchor.TYPE_NOTE:
			continue
		_place_virtual_marker(anchor, true)
		placed += 1
		if placed % 10 == 0:
			await get_tree().process_frame
	print("[TIMING] place ", placed, " virtual markers: ", Time.get_ticks_msec() - _t3, "ms")

	for entry in old_markers:
		if is_instance_valid(entry.marker):
			entry.marker.queue_free()

	for uuid in _pending_save:
		_write_glb_position(uuid, _pending_save[uuid].position)
	_pending_save.clear()


func _refresh_calibration() -> void:
	var kabsch_dst: Array[Vector3] = []
	for node in _kabsch_nodes:
		if not is_instance_valid(node):
			return
		kabsch_dst.append(node.position)

	var new_calibration := Kabsch.compute_yaw_locked(_kabsch_src, kabsch_dst)

	var err := 0.0
	for i in _kabsch_src.size():
		var e := (new_calibration * _kabsch_src[i]).distance_to(kabsch_dst[i])
		err += e
		if DevConfig.ANCHOR_VERBOSE_LOG:
			print("  ref[", _kabsch_names[i], "] error=", snappedf(e, 0.001), "m")
	err /= _kabsch_src.size()

	_last_kabsch_error = err
	if DevConfig.ANCHOR_VERBOSE_LOG:
		print("AnchorManager: recalibrated - avg error ", snappedf(err, 0.001), "m")
	_calibration = new_calibration
	_kabsch_snapshot = kabsch_dst
	_reposition_virtual_markers()




func _reposition_virtual_markers() -> void:
	for entry in _virtual_markers:
		if is_instance_valid(entry.marker):
			entry.marker.position = _to_local(entry.anchor.glb_position, entry.anchor.space_id)
			if entry.anchor.anchor_type == Anchor.TYPE_NOTE:
				entry.marker.basis = _to_local_basis(entry.anchor.glb_rotation, entry.anchor.space_id)


func _to_local(glb_pos: Vector3, space_id: String) -> Vector3:
	if space_id == _current_space_id or _space_offsets.is_empty():
		return _calibration * glb_pos
	var other_offset: Transform3D = _space_offsets.get(space_id, Transform3D.IDENTITY)
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return _calibration * (current_offset.affine_inverse() * (other_offset * glb_pos))


func _to_local_basis(glb_rot: Quaternion, space_id: String) -> Basis:
	var glb_basis := Basis(glb_rot)
	if space_id == _current_space_id or _space_offsets.is_empty():
		return _calibration.basis * glb_basis
	var other_offset: Transform3D = _space_offsets.get(space_id, Transform3D.IDENTITY)
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return (_calibration * current_offset.affine_inverse() * other_offset).basis * glb_basis


func _write_glb_position(uuid: String, local_pos: Vector3) -> void:
	SupabaseManager.update_anchor_glb_position(uuid, _calibration.affine_inverse() * local_pos)


func _place_virtual_marker(anchor: Anchor, other_space: bool) -> void:
	var marker := _create_virtual_marker(anchor, other_space)
	marker.position = _to_local(anchor.glb_position, anchor.space_id)
	if anchor.anchor_type == Anchor.TYPE_NOTE:
		marker.basis = _to_local_basis(anchor.glb_rotation, anchor.space_id)
	get_parent().add_child(marker)
	_virtual_markers.append({ "marker": marker, "anchor": anchor })




func _create_virtual_marker(anchor: Anchor, other_space: bool) -> Node3D:
	match anchor.anchor_type:
		Anchor.TYPE_ASSET:
			var m := AssetAnchorMarker.new()
			m.anchor = anchor
			return m
		Anchor.TYPE_NOTE:
			var m := NoteAnchorMarker.new()
			m.anchor = anchor
			return m
		_:
			if not DevConfig.DEV_MODE:
				return Node3D.new()  # invisible placeholder
			var m := ContentAnchorMarker.new()
			m.anchor = anchor
			m.other_space = other_space
			return m


func _create_tracked_marker(anchor: Anchor) -> Node3D:
	match anchor.anchor_type:
		Anchor.TYPE_ASSET:
			var m := AssetAnchorMarker.new()
			m.anchor = anchor
			return m
		Anchor.TYPE_REFERENCE:
			if not DevConfig.DEV_MODE and not _anchor_editing and not DevConfig.CALIBRATION_VALIDATION:
				return Node3D.new()
			var m := ReferenceAnchorMarker.new()
			m.anchor = anchor
			return m
		Anchor.TYPE_NOTE:
			var m := NoteAnchorMarker.new()
			m.anchor = anchor
			return m
		_:
			if not DevConfig.DEV_MODE:
				return Node3D.new()
			var m := ContentAnchorMarker.new()
			m.anchor = anchor
			return m


# Capture a CV-camera photo of the anchor's surroundings and attach it to the
# anchor row, so the desktop can show what the anchor is pointing at while it is
# being mapped to the mesh. Fire-and-forget: the camera latency gives the insert
# above time to land before upload_anchor_image updates the row by ml2_id.
func _capture_anchor_image(ml2_id: String) -> void:
	var image: Image = await CVCameraManager.capture_frame()
	if image == null:
		return
	await SupabaseManager.upload_anchor_image(ml2_id, image)


func _spawn_validation_marker(ml2_id: String) -> void:
	var anchor: Anchor = _holdout_anchors.get(ml2_id)
	var tracked: Node3D = _holdout_nodes.get(ml2_id)
	if not anchor or not is_instance_valid(tracked):
		return
	var marker := CalibrationValidationMarker.new()
	marker.actual_node = tracked
	marker.glb_position = anchor.glb_position
	marker.anchor_name = anchor.name
	marker.anchor_mgr = self
	get_parent().add_child(marker)
	_validation_markers.append(marker)
	print("AnchorManager: validation marker spawned for held-out anchor ", anchor.name, " (", ml2_id, ")")


func _spawn_ready_validation_markers() -> void:
	for ml2_id in _holdout_nodes:
		_spawn_validation_marker(ml2_id)


func _spawn_cross_space_markers() -> void:
	if not DevConfig.CROSS_SPACE_ALIGNMENT_VIZ or _prev_space_id.is_empty():
		return
	var prev_offset: Transform3D = _space_offsets.get(_prev_space_id, Transform3D.IDENTITY)
	var curr_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	var spawned := 0
	for anchor in _all_anchors.values():
		if anchor.space_id != _current_space_id or anchor.anchor_type != Anchor.TYPE_REFERENCE:
			continue
		if anchor.glb_position == null:
			continue
		var rough_pos: Vector3 = _prev_calibration * (prev_offset.affine_inverse() * (curr_offset * (anchor.glb_position as Vector3)))
		var marker := CrossSpaceAlignmentMarker.new()
		marker.rough_pos = rough_pos
		marker.glb_position = anchor.glb_position
		marker.anchor_name = anchor.name
		marker.anchor_mgr = self
		get_parent().add_child(marker)
		_cross_space_markers.append(marker)
		spawned += 1
	print("AnchorManager: cross-space alignment markers spawned for ", spawned, " anchors (", _prev_space_id, " → ", _current_space_id, ")")


func _get_anchor_by_ml2(ml2_id: String) -> Anchor:
	for anchor in _all_anchors.values():
		if anchor.ml2_id == ml2_id:
			return anchor
	return null


# ── ML2 callbacks ─────────────────────────────────────────────────────────────

func _on_ml_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	var uuid_str := str(ml2_uuid)
	if DevConfig.ANCHOR_VERBOSE_LOG:
		print("AnchorManager: tracked ", uuid_str, " (new=", is_new, ")")
	tracked_nodes[uuid_str] = anchor_node
	_retry_uuids.erase(uuid_str)
	_storage_pending.erase(uuid_str)

	if is_new:
		var new_anchor := Anchor.new()
		new_anchor.ml2_id      = uuid_str
		new_anchor.name        = str(_next_num)
		new_anchor.anchor_type = Anchor.TYPE_REFERENCE
		new_anchor.space_id    = _current_space_id
		_next_num += 1
		_all_anchors[new_anchor.id] = new_anchor
		_building_spaces.clear()  # force re-fetch on next calibrate
		SupabaseManager.insert_anchor(new_anchor)
		_capture_anchor_image(uuid_str)
		var new_marker := ReferenceAnchorMarker.new()
		new_marker.anchor = new_anchor
		anchor_node.add_child(new_marker)
		if _calibrated:
			await get_tree().process_frame
			_write_glb_position(uuid_str, anchor_node.position)
		else:
			_pending_save[uuid_str] = anchor_node
		anchor_tracked.emit(anchor_node, ml2_uuid, is_new)
		return

	var anchor := _get_anchor_by_ml2(uuid_str)

	await get_tree().process_frame

	if _holdout_anchors.has(uuid_str):
		_holdout_nodes[uuid_str] = anchor_node
		if _calibrated:
			_spawn_validation_marker(uuid_str)
		anchor_tracked.emit(anchor_node, ml2_uuid, is_new)
		return

	if _ref_anchors.has(uuid_str):
		var ref: Anchor = _ref_anchors[uuid_str]
		if anchor:
			anchor_node.add_child(_create_tracked_marker(anchor))
		else:
			var fallback := ReferenceAnchorMarker.new()
			fallback.anchor = Anchor.new()
			anchor_node.add_child(fallback)
		if anchor_node not in _kabsch_nodes:
			_kabsch_src.append(ref.glb_position)
			_kabsch_nodes.append(anchor_node)
			_kabsch_names.append(ref.name)
		if DevConfig.ANCHOR_VERBOSE_LOG:
			print("AnchorManager: Kabsch pair #", _kabsch_src.size(), " for ", uuid_str)
		# try and calibrate every time we get a new tracked anchor
		await _try_calibrate()
	elif _calibrated:
		if anchor and anchor.glb_position:
			_place_virtual_marker(anchor, anchor.space_id != _current_space_id)

	anchor_tracked.emit(anchor_node, ml2_uuid, is_new)


func _on_anchor_untracked(uuid: StringName) -> void:
	print("AnchorManager: untracked ", uuid)
	tracked_nodes.erase(str(uuid))
	anchor_untracked.emit(uuid)


func _on_create_failed(transform: Transform3D) -> void:
	push_warning("AnchorManager: failed to create anchor at ", transform.origin)


func _on_load_failed(uuid: StringName) -> void:
	var uuid_str := str(uuid)
	if not _retry_uuids.has(uuid_str):
		push_warning("AnchorManager: failed to load anchor ", uuid)
		return
	var attempt: int = _retry_uuids[uuid_str]
	_retry_uuids[uuid_str] = attempt + 1
	print("AnchorManager: load failed for ", uuid, " - retrying in ", RETRY_DELAY, "s (attempt ", attempt + 1, ")")
	await get_tree().create_timer(RETRY_DELAY).timeout
	_ml_mgr.call("load_anchor", uuid)
