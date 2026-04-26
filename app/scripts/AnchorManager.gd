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
var _calibration := Transform3D.IDENTITY
var _calibrated := false

# Building stitching: space_id → Transform3D (offset from that space's GLB to the reference space's GLB)
var _space_offsets: Dictionary = {}
var _current_space_id := ""

# Virtual markers (non-ML2, positioned by GLB coords): [{marker: Node3D, anchor: Anchor}]
var _virtual_markers: Array[Dictionary] = []

# ML2 tracking
var tracked_nodes: Dictionary = {}     # ml2_uuid → Node3D
var _retry_uuids: Dictionary = {}
var _storage_pending: Array[String] = []
var _storage_retry_timer := 0.0
const RETRY_DELAY := 3.0
const STORAGE_RETRY_INTERVAL := 2.0

var _recalib_timer := 0.0
const RECALIB_INTERVAL := 2.0

signal calibrated
signal space_localized(uuid: String)
signal anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool)
signal anchor_untracked(uuid: StringName)


func _ready() -> void:
	if not ClassDB.class_exists("OpenXRMlSpatialAnchorManager"):
		push_warning("AnchorManager: OpenXRMlSpatialAnchorManager unavailable — spatial anchors disabled.")
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

	# rerun calibration every few seconsd, as the anchor node positions are constantly being refined by the ML2
	if _calibrated and _kabsch_nodes.size() >= 3:
		_recalib_timer -= delta
		if _recalib_timer <= 0.0:
			_recalib_timer = RECALIB_INTERVAL
			_refresh_calibration()


# ── Calibration API ───────────────────────────────────────────────────────────

# loads anchors from supabase and runs calibration (called by LocationManager)
func calibrate_to_space(space_id: String) -> void:
	await load_anchors_from_db() # sets the global _all_anchors to the curr spaces anchors
	_setup_space_for_calibration(space_id)


## Load anchors from Supabase and record the active space without running calibration.
func localize_to_space(space_id: String) -> void:
	await load_anchors_from_db() # sets the global _all_anchors to the curr spaces anchors
	_current_space_id = space_id
	print("AnchorManager: localize_to_space ", space_id)


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

func get_current_space_id() -> String:
	return _current_space_id

func get_space_anchors(space_id: String) -> Array[Anchor]:
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
func create_content_anchor(local_pos: Vector3) -> String:
	if not _calibrated:
		push_warning("AnchorManager: not calibrated — cannot create content anchor")
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


func clear_markers() -> void:
	for entry in _virtual_markers:
		if is_instance_valid(entry.marker):
			entry.marker.queue_free()
	_virtual_markers.clear()
	for node in tracked_nodes.values():
		if is_instance_valid(node):
			for child in node.get_children():
				child.queue_free()


# ── Anchor loading ────────────────────────────────────────────────────────────

# sets the global anchor vars for this new space: _all_anchors, _next_num
func load_anchors_from_db() -> void:
	var all_anchors: Array[Anchor] = await SupabaseManager.get_anchors()
	_all_anchors.clear()
	var next_num := 1
	for anchor in all_anchors:
		_all_anchors[anchor.id] = anchor
		if anchor.name.is_valid_int():
			next_num = max(next_num, anchor.name.to_int() + 1)
	_next_num = next_num


func _load_building_offsets(space_id: String) -> void:
	if space_id.is_empty():
		return
	var sibling_spaces: Array[Space] = await SupabaseManager.get_sibling_spaces(space_id)
	if sibling_spaces.is_empty():
		print("AnchorManager: no building found for space ", space_id)
		return
	print("AnchorManager: building has ", sibling_spaces.size(), " spaces")
	for s in sibling_spaces:
		_space_offsets[s.id] = s.offset_transformation


# ── Calibration internals ─────────────────────────────────────────────────────

# iterates through the anchors loaded from the database
# initialise inputs to the kabsch algorithm
# call ML2 apis to load reference anchors
func _setup_space_for_calibration(space_id: String) -> void:
	_ref_anchors.clear()
	_desktop_content.clear()
	_kabsch_src.clear()
	_kabsch_nodes.clear()
	_calibrated = false
	_current_space_id = space_id

	for anchor in _all_anchors.values():
		if anchor.space_id != space_id:
			continue
		if anchor.anchor_type == Anchor.TYPE_TEMP or anchor.anchor_type == Anchor.TYPE_NOTE:
			continue
		elif anchor.anchor_type == Anchor.TYPE_REFERENCE:
			if anchor.glb_position != null:
				_ref_anchors[anchor.ml2_id] = anchor
				var already_tracked: Node3D = tracked_nodes.get(anchor.ml2_id)
				if already_tracked:
					_kabsch_src.append(anchor.glb_position)
					_kabsch_nodes.append(already_tracked)
				else:
					load_anchor_from_ml2(anchor.ml2_id)
			else:
				print("AnchorManager: ref anchor ", anchor.id, " has no glb_position — skipping")
		else:
			if anchor.ml2_id != null:
				if not tracked_nodes.has(anchor.ml2_id):
					load_anchor_from_ml2(anchor.ml2_id)
			else:
				_desktop_content.append(anchor)

	print("AnchorManager: setup space ", space_id,
			" — ", _ref_anchors.size(), " ref anchors, ", _kabsch_src.size(), " already tracked")
	if _kabsch_src.size() >= 3:
		_try_calibrate()


func _try_calibrate() -> void:
	if _kabsch_src.size() < 3:
		print("AnchorManager: need ≥3 reference pairs (have ", _kabsch_src.size(), ")")
		return

	var kabsch_dst: Array[Vector3] = []
	for node in _kabsch_nodes:
		kabsch_dst.append(node.position)

	var first_calibration := not _calibrated
	_calibration = Kabsch.compute(_kabsch_src, kabsch_dst)
	_calibrated = true

	print("AnchorManager: calibrated from ", _kabsch_src.size(), " reference points")
	for i in _kabsch_src.size():
		var predicted := _calibration * _kabsch_src[i]
		print("  ref[", i, "] error=", snappedf(predicted.distance_to(kabsch_dst[i]), 0.001), "m")

	if not first_calibration:
		return

	await _load_building_offsets(_current_space_id)

	calibrated.emit()

	for entry in _virtual_markers:
		if is_instance_valid(entry.marker):
			entry.marker.queue_free()
	_virtual_markers.clear()

	for anchor in _desktop_content:
		_place_virtual_marker(anchor, false)

	for anchor in _all_anchors.values():
		if anchor.space_id == _current_space_id or anchor.glb_position == null:
			continue
		if anchor.anchor_type != Anchor.TYPE_CONTENT and anchor.anchor_type != Anchor.TYPE_ASSET:
			continue
		_place_virtual_marker(anchor, true)

	for uuid in _pending_save:
		_write_glb_position(uuid, _pending_save[uuid].position)
	_pending_save.clear()


func _refresh_calibration() -> void:
	var kabsch_dst: Array[Vector3] = []
	for node in _kabsch_nodes:
		if not is_instance_valid(node):
			return
		kabsch_dst.append(node.position)

	var new_calibration := Kabsch.compute(_kabsch_src, kabsch_dst)

	var old_err := 0.0
	var new_err := 0.0
	for i in _kabsch_src.size():
		old_err += (_calibration * _kabsch_src[i]).distance_to(kabsch_dst[i])
		new_err += (new_calibration * _kabsch_src[i]).distance_to(kabsch_dst[i])
	old_err /= _kabsch_src.size()
	new_err /= _kabsch_src.size()

	if new_err >= old_err:
		return

	print("AnchorManager: recalibrated — avg error ", snappedf(old_err, 0.001), "m → ", snappedf(new_err, 0.001), "m")
	_calibration = new_calibration
	_reposition_virtual_markers()


func _reposition_virtual_markers() -> void:
	for entry in _virtual_markers:
		if is_instance_valid(entry.marker):
			entry.marker.position = _to_local(entry.anchor.glb_position, entry.anchor.space_id)


func _to_local(glb_pos: Vector3, space_id: String) -> Vector3:
	if space_id == _current_space_id or _space_offsets.is_empty():
		return _calibration * glb_pos
	var other_offset: Transform3D = _space_offsets.get(space_id, Transform3D.IDENTITY)
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return _calibration * (current_offset.affine_inverse() * (other_offset * glb_pos))


func _write_glb_position(uuid: String, local_pos: Vector3) -> void:
	SupabaseManager.update_anchor_glb_position(uuid, _calibration.affine_inverse() * local_pos)


func _place_virtual_marker(anchor: Anchor, other_space: bool) -> void:
	var marker := _create_virtual_marker(anchor, other_space)
	marker.position = _to_local(anchor.glb_position, anchor.space_id)
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
			var m := ReferenceAnchorMarker.new()
			m.anchor = anchor
			return m
		_:
			var m := ContentAnchorMarker.new()
			m.anchor = anchor
			return m


func _get_anchor_by_ml2(ml2_id: String) -> Anchor:
	for anchor in _all_anchors.values():
		if anchor.ml2_id == ml2_id:
			return anchor
	return null


# ── ML2 callbacks ─────────────────────────────────────────────────────────────

func _on_ml_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	var uuid_str := str(ml2_uuid)
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
		SupabaseManager.insert_anchor(new_anchor)
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
	if anchor:
		anchor_node.add_child(_create_tracked_marker(anchor))
	else:
		var fallback := ReferenceAnchorMarker.new()
		fallback.anchor = Anchor.new()
		anchor_node.add_child(fallback)

	await get_tree().process_frame

	if _ref_anchors.has(uuid_str):
		var ref: Anchor = _ref_anchors[uuid_str]
		_kabsch_src.append(ref.glb_position)
		_kabsch_nodes.append(anchor_node)
		print("AnchorManager: Kabsch pair #", _kabsch_src.size(), " for ", uuid_str)
		# try and calibrate every time we get a new tracked anchor
		_try_calibrate()
	elif _calibrated:
		if anchor and anchor.glb_position:
			anchor_node.position = _to_local(anchor.glb_position, anchor.space_id)

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
	print("AnchorManager: load failed for ", uuid, " — retrying in ", RETRY_DELAY, "s (attempt ", attempt + 1, ")")
	await get_tree().create_timer(RETRY_DELAY).timeout
	_ml_mgr.call("load_anchor", uuid)
