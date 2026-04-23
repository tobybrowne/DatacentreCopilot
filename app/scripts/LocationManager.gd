extends Node
class_name LocationManager

## Handles calibration, anchor placement, and building-wide anchor visualisation.
## Must be a child of XROrigin3D. Depends on AnchorManager for ML2 tracking.

## Emitted once after the first successful calibration and building offsets are loaded.
signal calibrated
## Emitted when navigation is requested but the user's space within the building is unknown.
signal space_picker_needed(spaces: Array[Space])
## Emitted when the current coarse space is already within the requested building.
signal navigation_ready(space_id: String)
## Emitted when the nearest coarse space changes.
signal coarse_space_changed(coarse_id: String, active_id: String)

var _anchor_manager: AnchorManager

var _all_anchors: Dictionary = {}       # supabase_id → Anchor
var _ref_anchors: Dictionary = {}       # ml2_id → Anchor (current space, has glb_position)
var _desktop_content: Array[Anchor] = []
var _pending_save: Dictionary = {}      # ml2_uuid → Node3D

# Kabsch
var _kabsch_src: Array[Vector3] = []
var _kabsch_nodes: Array[Node3D] = []
var _calibration := Transform3D.IDENTITY
var _calibrated := false

# Building stitching: space_id → Transform3D (offset from that space's GLB to the reference space's GLB)
var _space_offsets: Dictionary = {}
var _current_space_id := ""

@export var write_user_position := false
var _user_pos_timer := 0.0
const USER_POS_INTERVAL := 1.0

var _loc_poll_timer := 0.0
const LOC_POLL_INTERVAL := 2.0
var _last_loc_confidence := -1

# Relocalisation
var current_coarse_space := ""
var _poor_quality_timer := 0.0
const POOR_RELOC_THRESHOLD := 10.0
var _relocalising := false

var _tracking_dot_mat: StandardMaterial3D
var _tracking_label: Label3D

var _marker_nodes: Array[Node3D] = []
var _space_manager: SpaceManager


func _ready() -> void:
	_anchor_manager = get_parent().get_node_or_null("AnchorManager")
	_space_manager  = get_parent().get_node_or_null("SpaceManager")
	if not _anchor_manager:
		push_warning("LocationManager: AnchorManager not found")
		return
	_anchor_manager.anchor_tracked.connect(_on_anchor_tracked)
	_create_tracking_indicator()

	var ext := _ml2_ext()
	if ext:
		ext.localization_changed.connect(_on_localization_changed)


func _ml2_ext() -> Object:
	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return Engine.get_singleton("OpenXRMlLocalizationMapExtension")
	return null


func _create_tracking_indicator() -> void:
	var camera := get_parent().get_node_or_null("XRCamera3D")
	if not camera:
		return
	var sphere := SphereMesh.new()
	sphere.radius = 0.004
	sphere.height = 0.008
	_tracking_dot_mat = StandardMaterial3D.new()
	_tracking_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracking_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	_tracking_dot_mat.albedo_color = Color(0.5, 0.5, 0.5)
	var dot := MeshInstance3D.new()
	dot.mesh = sphere
	dot.material_override = _tracking_dot_mat
	dot.position = Vector3(0.11, 0.07, -0.3)
	camera.add_child(dot)

	_tracking_label = Label3D.new()
	_tracking_label.text = ""
	_tracking_label.font_size = 64
	_tracking_label.pixel_size = 0.0003
	_tracking_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_tracking_label.no_depth_test = true
	_tracking_label.position = Vector3(0.11, 0.076, -0.3)
	_tracking_label.modulate = Color(1.0, 1.0, 1.0)
	camera.add_child(_tracking_label)


func _process(delta: float) -> void:
	_loc_poll_timer += delta
	if _loc_poll_timer >= LOC_POLL_INTERVAL:
		_loc_poll_timer = 0.0
		_poll_localization()

	if not _calibrated:
		return
	_user_pos_timer += delta
	if _user_pos_timer >= USER_POS_INTERVAL:
		_user_pos_timer = 0.0
		var camera := get_parent().get_node_or_null("XRCamera3D")
		if camera:
			var space_glb_pos: Vector3 = _calibration.affine_inverse() * camera.position
			var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
			_update_room_label(current_offset * space_glb_pos)
			if write_user_position:
				SupabaseManager.update_user_glb_position(space_glb_pos)


func _update_room_label(building_pos: Vector3) -> void:
	var closest_id := ""
	var closest_dist := INF
	for anchor in _all_anchors.values():
		if anchor.name != "__centroid__" or anchor.glb_position == null:
			continue
		var offset: Transform3D = _space_offsets.get(anchor.space_id, Transform3D.IDENTITY)
		var dist: float = building_pos.distance_to(offset * anchor.glb_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_id = anchor.space_id

	if closest_id.is_empty():
		return
	current_coarse_space = closest_id
	coarse_space_changed.emit(closest_id, _current_space_id)


func _poll_localization() -> void:
	var ext := _ml2_ext()
	if not ext:
		return
	var confidence: int = ext.get_localization_confidence() if ext.has_method("get_localization_confidence") else -1

	if confidence != _last_loc_confidence:
		_last_loc_confidence = confidence
		var labels := ["POOR", "FAIR", "GOOD", "EXCELLENT"]
		var label: String = labels[confidence] if confidence >= 0 and confidence < labels.size() else str(confidence)
		print("LocationManager: confidence=", label, " uuid=", ext.get_localization_map_uuid())

	if _tracking_dot_mat:
		match confidence:
			3: _tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # EXCELLENT — green
			2: _tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # GOOD — green
			1: _tracking_dot_mat.albedo_color = Color(1.0, 0.55, 0.0)  # FAIR — orange
			0: _tracking_dot_mat.albedo_color = Color(1.0, 0.2, 0.2)   # POOR — red
			_: _tracking_dot_mat.albedo_color = Color(0.5, 0.5, 0.5)   # unknown — grey

	if confidence == 0:
		_poor_quality_timer += LOC_POLL_INTERVAL
		if _poor_quality_timer >= POOR_RELOC_THRESHOLD:
			if not current_coarse_space.is_empty() and current_coarse_space != _current_space_id:
				_attempt_relocalisation(current_coarse_space)
				_poor_quality_timer = 0.0
	else:
		_poor_quality_timer = 0.0


func _attempt_relocalisation(target_space_id: String) -> void:
	var ref_count := _ref_anchor_count(target_space_id)
	if ref_count < 3:
		print("LocationManager: skipping reloc to ", target_space_id, " — only ", ref_count, "/3 ref anchors")
		return
	print("LocationManager: POOR quality too long — attempting reloc to ", target_space_id)
	var ext := _ml2_ext()
	if not ext:
		return
	if ext.has_method("request_localization"):
		ext.request_localization(target_space_id)
		_relocalising = true
		if _tracking_label:
			_tracking_label.text = "?"
	else:
		push_warning("LocationManager: OpenXRMlLocalizationMapExtension has no request_localization method")


func _on_localization_changed(state: int, _confidence: int, _error_flags: int) -> void:
	print("LocationManager: _on_localization_changed state=", state, " confidence=", _confidence, " error_flags=", _error_flags)
	match state:
		1: # LOCALIZED — success
			_relocalising = false
			if _tracking_label:
				_tracking_label.text = ""
			var ext := _ml2_ext()
			if ext:
				var new_uuid: String = ext.get_localization_map_uuid()
				if not new_uuid.is_empty() and new_uuid != _current_space_id:
					print("LocationManager: relocalised to ", new_uuid)
					current_coarse_space = new_uuid
					_setup_space_for_calibration(new_uuid)
		0: # NOT_LOCALIZED
			_current_space_id = ""
			if _relocalising:
				_relocalising = false
				if _tracking_label:
					_tracking_label.text = "!"
				print("LocationManager: relocalisation failed — NOT_LOCALIZED")
			else:
				if _tracking_label:
					_tracking_label.text = ""
		2, 3: # PENDING / SLEEPING — keep ? visible, do nothing
			pass


# ── Load ──────────────────────────────────────────────────────────────────────

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
				var already_tracked: Node3D = _anchor_manager.tracked_nodes.get(anchor.ml2_id)
				if already_tracked:
					_kabsch_src.append(anchor.glb_position)
					_kabsch_nodes.append(already_tracked)
				else:
					_anchor_manager.load_anchor(anchor.ml2_id)
			else:
				print("LocationManager: ref anchor ", anchor.id, " has no glb_position — skipping")
		else:
			if anchor.ml2_id != null:
				if not _anchor_manager.tracked_nodes.has(anchor.ml2_id):
					_anchor_manager.load_anchor(anchor.ml2_id)
			else:
				_desktop_content.append(anchor)

	print("LocationManager: setup space ", space_id,
			" — ", _ref_anchors.size(), " ref anchors, ", _kabsch_src.size(), " already tracked")
	if _kabsch_src.size() >= 3:
		_try_calibrate()


func _ref_anchor_count(space_id: String) -> int:
	var count := 0
	for anchor in _all_anchors.values():
		if anchor.space_id == space_id and anchor.anchor_type == Anchor.TYPE_REFERENCE and anchor.glb_position != null:
			count += 1
	return count


## Ensure the ML2 has the localization map downloaded for the given space.
func ensure_space_local(space: Space) -> bool:
	if not _space_manager:
		push_warning("LocationManager: no SpaceManager — cannot import space")
		return false
	var local_ids := _space_manager.get_all_local_spaces().map(func(s: Space): return s.id)
	if space.id in local_ids:
		return true
	print("LocationManager: space not local — importing ", space.id)
	var ok := await _space_manager.import_space(space)
	if not ok:
		push_warning("LocationManager: import failed for space ", space.id)
	return ok


## Localise into a space without running Kabsch calibration.
func localize_to_space(space_id: String) -> void:
	if _current_space_id != space_id:
		_request_localization(space_id)
	await _load_anchors()
	_current_space_id = space_id
	print("LocationManager: localize_to_space ", space_id)


## Called when the user wants to navigate within a building.
func request_navigation(building_id: String) -> void:
	var spaces: Array[Space] = await SupabaseManager.get_spaces_for_building(building_id)
	print("LocationManager: building has ", spaces.size(), " spaces, coarse=", current_coarse_space)
	var space_ids := spaces.map(func(s: Space): return s.id)
	if current_coarse_space in space_ids:
		navigation_ready.emit(current_coarse_space)
	else:
		space_picker_needed.emit(spaces)


func get_space_anchors(space_id: String) -> Array[Anchor]:
	var result: Array[Anchor] = []
	for anchor in _all_anchors.values():
		if anchor.space_id == space_id and anchor.ml2_id:
			result.append(anchor)
	return result


## Localise into a space AND run Kabsch calibration as reference anchors track in.
func calibrate_to_space(space_id: String) -> void:
	if _current_space_id != space_id:
		_request_localization(space_id)
	await _load_anchors()
	if _current_space_id == space_id:
		_setup_space_for_calibration(space_id)
	# else: _on_localization_changed(LOCALIZED) will call _setup_space_for_calibration
	print("LocationManager: calibrate_to_space ", space_id, " — confirmed=", _current_space_id == space_id)


func _request_localization(space_id: String) -> void:
	var ext := _ml2_ext()
	if ext and ext.has_method("request_localization"):
		ext.request_localization(space_id)


func _load_anchors() -> void:
	var all_anchors: Array[Anchor] = await SupabaseManager.get_anchors()
	_all_anchors.clear()
	var next_num := 1
	for anchor in all_anchors:
		_all_anchors[anchor.id] = anchor
		if anchor.name.is_valid_int():
			next_num = max(next_num, anchor.name.to_int() + 1)
	_anchor_manager.set_next_num(next_num)
	_anchor_manager.set_anchor_registry(_all_anchors)


func get_current_space_id() -> String:
	var ext := _ml2_ext()
	return ext.get_localization_map_uuid() if ext else ""


## Create a transient content anchor at a given ML2 local-space position,
## saving it to Supabase with the computed GLB position.
## Returns the new anchor's Supabase UUID, or "" on failure.
func create_content_anchor(local_pos: Vector3) -> String:
	if not _calibrated:
		push_warning("LocationManager: not calibrated — cannot create content anchor")
		return ""
	var glb_pos: Vector3 = _calibration.affine_inverse() * local_pos
	var anchor := Anchor.new()
	anchor.name         = "user_position"
	anchor.anchor_type = Anchor.TYPE_TEMP
	anchor.glb_position = glb_pos
	anchor.space_id     = _current_space_id
	var inserted: Anchor = await SupabaseManager.insert_anchor(anchor)
	if not inserted or inserted.id.is_empty():
		push_warning("LocationManager: failed to insert content anchor")
		return ""
	print("LocationManager: created content anchor ", inserted.id, " at glb ", glb_pos)
	return inserted.id


func _load_building_offsets(space_id: String) -> void:
	if space_id.is_empty():
		return
	var sibling_spaces: Array[Space] = await SupabaseManager.get_sibling_spaces(space_id)
	if sibling_spaces.is_empty():
		print("LocationManager: no building found for space ", space_id)
		return
	print("LocationManager: building has ", sibling_spaces.size(), " spaces")
	for s in sibling_spaces:
		_space_offsets[s.id] = s.offset_transformation


# ── Calibration ──────────────────────────────────────────────────────────────

func _try_calibrate() -> void:
	if _kabsch_src.size() < 3:
		print("LocationManager: need ≥3 reference pairs (have ", _kabsch_src.size(), ")")
		return

	var kabsch_dst: Array[Vector3] = []
	for node in _kabsch_nodes:
		kabsch_dst.append(node.position)

	var first_calibration := not _calibrated
	_calibration = Kabsch.compute(_kabsch_src, kabsch_dst)
	_calibrated = true

	print("LocationManager: calibrated from ", _kabsch_src.size(), " reference points")
	for i in _kabsch_src.size():
		var predicted := _calibration * _kabsch_src[i]
		print("  ref[", i, "] error=", snappedf(predicted.distance_to(kabsch_dst[i]), 0.001), "m")

	if not first_calibration:
		return

	_current_space_id = get_current_space_id()
	await _load_building_offsets(_current_space_id)

	calibrated.emit()

	for node in _marker_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_marker_nodes.clear()

	for anchor in _desktop_content:
		_place_virtual_marker(anchor, anchor.space_id)

	for anchor in _all_anchors.values():
		if anchor.space_id == _current_space_id or anchor.glb_position == null or anchor.anchor_type != Anchor.TYPE_CONTENT:
			continue
		_place_virtual_marker(anchor, anchor.space_id)

	for uuid in _pending_save:
		_write_glb_position(uuid, _pending_save[uuid].position)
	_pending_save.clear()


func get_calibration() -> Transform3D:
	return _calibration

func world_to_glb(world_pos: Vector3) -> Vector3:
	return _calibration.affine_inverse() * world_pos


func glb_to_world(glb_pos: Vector3) -> Vector3:
	return _calibration * glb_pos


func world_to_local(building_pos: Vector3) -> Vector3:
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return _calibration * (current_offset.affine_inverse() * building_pos)


func _to_local(glb_pos: Vector3, space_id: String) -> Vector3:
	if space_id == _current_space_id or _space_offsets.is_empty():
		return _calibration * glb_pos
	var other_offset: Transform3D = _space_offsets.get(space_id, Transform3D.IDENTITY)
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return _calibration * (current_offset.affine_inverse() * (other_offset * glb_pos))


func _write_glb_position(uuid: String, local_pos: Vector3) -> void:
	SupabaseManager.update_anchor_glb_position(uuid, _calibration.affine_inverse() * local_pos)


func clear_markers() -> void:
	for node in _marker_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_marker_nodes.clear()
	_anchor_manager.clear_markers()


func _place_virtual_marker(anchor: Anchor, space_id: String) -> void:
	var color := Color(0.5, 0.3, 1.0) if space_id != _current_space_id else Color(1.0, 0.55, 0.0)
	var marker := _anchor_manager._make_marker(color, anchor.name)
	marker.position = _to_local(anchor.glb_position, space_id)
	get_parent().add_child(marker)
	_marker_nodes.append(marker)


# ── AnchorManager callback ────────────────────────────────────────────────────

func _on_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	var uuid_str := str(ml2_uuid)

	if is_new:
		if _calibrated:
			await get_tree().process_frame
			_write_glb_position(uuid_str, anchor_node.position)
		else:
			_pending_save[uuid_str] = anchor_node
		return

	await get_tree().process_frame

	if _ref_anchors.has(uuid_str):
		var ref: Anchor = _ref_anchors[uuid_str]
		_kabsch_src.append(ref.glb_position)
		_kabsch_nodes.append(anchor_node)
		print("LocationManager: Kabsch pair #", _kabsch_src.size(), " for ", uuid_str)
		_try_calibrate()
	elif _calibrated:
		var anchor: Anchor = _get_anchor_by_ml2(uuid_str)
		if anchor and anchor.glb_position:
			anchor_node.position = _to_local(anchor.glb_position, anchor.space_id)


func _get_anchor_by_ml2(ml2_id: String) -> Anchor:
	for anchor in _all_anchors.values():
		if anchor.ml2_id == ml2_id:
			return anchor
	return null
