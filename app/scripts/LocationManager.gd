extends Node
class_name LocationManager

## Handles calibration, anchor placement, and building-wide anchor visualisation.
## Must be a child of XROrigin3D. Depends on AnchorManager for ML2 tracking.

## Emitted once after the first successful calibration and building offsets are loaded.
signal calibrated

var _anchor_manager: AnchorManager

# All anchors from DB, keyed by ml2_id (for reference lookup) or supabase id
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
var _space_offsets: Dictionary = {}     # space_id → Transform3D
var _current_space_id := ""            # space_id of the space we calibrated against

# User position reporting
@export var write_user_position := false
var _user_pos_timer := 0.0
const USER_POS_INTERVAL := 1.0

var _loc_poll_timer := 0.0
const LOC_POLL_INTERVAL := 2.0
var _last_loc_confidence := -1
var _last_loc_state := -1

# Relocalisation
var current_coarse_space := ""         # space_id nearest to user by centroid proximity
var _poor_quality_timer := 0.0
const POOR_RELOC_THRESHOLD := 10.0    # seconds at POOR before attempting reloc
var _relocalising := false

var _tracking_dot_mat: StandardMaterial3D
var _tracking_label: Label3D
var _coarse_label: Label
var _active_label: Label
var _space_names: Dictionary = {}  # space_id → name

# Placed marker nodes, so we can refresh them on re-calibration
var _marker_nodes: Array[Node3D] = []


func _ready() -> void:
	_anchor_manager = get_parent().get_node_or_null("AnchorManager")
	if not _anchor_manager:
		push_warning("LocationManager: AnchorManager not found")
		return
	_anchor_manager.anchor_tracked.connect(_on_anchor_tracked)
	_create_tracking_indicator()

	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr:
		xr.session_begun.connect(_load_and_calibrate)
		if xr.is_initialized():
			_load_and_calibrate()

	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		var ext := Engine.get_singleton("OpenXRMlLocalizationMapExtension")
		ext.localization_changed.connect(_on_localization_changed)


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
			var building_pos: Vector3 = current_offset * space_glb_pos
			_update_room_label(building_pos)
			if write_user_position:
				SupabaseManager.update_user_glb_position(space_glb_pos)


func _update_room_label(building_pos: Vector3) -> void:
	# Use __centroid__ anchors (computed by desktop) to find the nearest room.
	var closest_id := ""
	var closest_dist := INF
	for anchor in _all_anchors.values():
		if anchor.name != "__centroid__" or anchor.glb_position == null:
			continue
		var offset: Transform3D = _space_offsets.get(anchor.space_id, Transform3D.IDENTITY)
		var centroid_building: Vector3 = offset * anchor.glb_position
		var dist: float = building_pos.distance_to(centroid_building)
		if dist < closest_dist:
			closest_dist = dist
			closest_id = anchor.space_id

	if not closest_id.is_empty():
		current_coarse_space = closest_id
		if not _coarse_label:
			var space_label_3d := get_parent().get_node_or_null("SpaceLabel")
			if space_label_3d and space_label_3d.get_panel():
				var panel: Control = space_label_3d.get_panel()
				_coarse_label = panel.get_node_or_null("MarginContainer/VBoxContainer/CoarseLabel")
				_active_label = panel.get_node_or_null("MarginContainer/VBoxContainer/ActiveLabel")
		if _coarse_label:
			_coarse_label.text = _space_names.get(closest_id, closest_id)
		if _active_label:
			var active_name: String = _space_names.get(_current_space_id, _current_space_id)
			_active_label.text = "active: " + active_name


func _poll_localization() -> void:
	if not Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return
	var ext := Engine.get_singleton("OpenXRMlLocalizationMapExtension")
	var confidence: int = ext.get_localization_confidence() if ext.has_method("get_localization_confidence") else -1
	var uuid: String = ext.get_localization_map_uuid()

	if confidence != _last_loc_confidence:
		_last_loc_confidence = confidence
		var confidence_labels := ["POOR", "FAIR", "GOOD", "EXCELLENT"]
		var confidence_str: String = confidence_labels[confidence] if confidence >= 0 and confidence < confidence_labels.size() else str(confidence)
		print("LocationManager: confidence=", confidence_str, " uuid=", uuid)

	if _tracking_dot_mat:
		match confidence:
			3: _tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # EXCELLENT — green
			2: _tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # GOOD — green
			1: _tracking_dot_mat.albedo_color = Color(1.0, 0.55, 0.0)  # FAIR — orange
			0: _tracking_dot_mat.albedo_color = Color(1.0, 0.2, 0.2)   # POOR — red
			_: _tracking_dot_mat.albedo_color = Color(0.5, 0.5, 0.5)   # unknown — grey

	# Accumulate POOR time and attempt relocalisation if coarse space differs
	if confidence == 0:
		_poor_quality_timer += LOC_POLL_INTERVAL
		if _poor_quality_timer >= POOR_RELOC_THRESHOLD:
			if not current_coarse_space.is_empty() and current_coarse_space != _current_space_id:
				_attempt_relocalisation(current_coarse_space)
				_poor_quality_timer = 0.0
	else:
		_poor_quality_timer = 0.0


func _attempt_relocalisation(target_space_id: String) -> void:
	var target_name: String = _space_names.get(target_space_id, target_space_id)
	var ref_count := _ref_anchor_count(target_space_id)
	if ref_count < 3:
		print("LocationManager: skipping reloc to \"", target_name, "\" — only ", ref_count, "/3 ref anchors")
		return
	print("LocationManager: POOR quality too long — attempting reloc to \"", target_name, "\" (", target_space_id, ")")
	if not Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return
	var ext := Engine.get_singleton("OpenXRMlLocalizationMapExtension")
	if ext.has_method("request_localization"):
		ext.request_localization(target_space_id)
		_relocalising = true
		if _tracking_label:
			_tracking_label.text = "?"
	else:
		push_warning("LocationManager: OpenXRMlLocalizationMapExtension has no request_localization method")


func _on_localization_changed(state: int, _confidence: int, _error_flags: int) -> void:
	# LOCALIZATION_PENDING (2) and SLEEPING_BEFORE_RETRY (3) mean still in progress — keep the ?
	match state:
		1: # LOCALIZED — success
			_relocalising = false
			if _tracking_label:
				_tracking_label.text = ""
			if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
				var new_uuid: String = Engine.get_singleton("OpenXRMlLocalizationMapExtension").get_localization_map_uuid()
				if not new_uuid.is_empty() and new_uuid != _current_space_id:
					var new_name: String = _space_names.get(new_uuid, new_uuid)
					print("LocationManager: relocalised to \"", new_name, "\" (", new_uuid, ")")
					current_coarse_space = new_uuid
					_setup_space_for_calibration(new_uuid)
		0: # NOT_LOCALIZED
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

func _load_and_calibrate() -> void:
	# Warm up the write connection so the first anchor insert doesn't stall.
	SupabaseManager.update_user_glb_position(Vector3.ZERO)

	var spaces: Array[Space] = await SupabaseManager.get_spaces()
	for space in spaces:
		_space_names[space.id] = space.name

	var all_anchors: Array[Anchor] = await SupabaseManager.get_anchors()
	print("LocationManager: fetched ", all_anchors.size(), " anchors")

	var next_num := 1
	for anchor in all_anchors:
		_all_anchors[anchor.id] = anchor
		if anchor.name.is_valid_int():
			next_num = max(next_num, anchor.name.to_int() + 1)
	_anchor_manager.set_next_num(next_num)
	_anchor_manager.set_anchor_registry(_all_anchors)

	# Determine current space from localization, then load anchors for it
	var current_space_id := get_current_space_id()
	_setup_space_for_calibration(current_space_id)


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
		if anchor.is_reference:
			if anchor.glb_position != null:
				_ref_anchors[anchor.ml2_id] = anchor
				_anchor_manager.load_anchor(anchor.ml2_id)
			else:
				print("LocationManager: ref anchor ", anchor.id, " has no glb_position — skipping")
		else:
			if anchor.ml2_id != null:
				_anchor_manager.load_anchor(anchor.ml2_id)
			else:
				_desktop_content.append(anchor)

	print("LocationManager: setup space ", _space_names.get(space_id, space_id),
			" — ", _ref_anchors.size(), " ref anchors loaded")


func _ref_anchor_count(space_id: String) -> int:
	var count := 0
	for anchor in _all_anchors.values():
		if anchor.space_id == space_id and anchor.is_reference and anchor.glb_position != null:
			count += 1
	return count


func get_current_space_id() -> String:
	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return Engine.get_singleton("OpenXRMlLocalizationMapExtension").get_localization_map_uuid()
	return ""


func _load_building_offsets(space_id: String) -> void:
	if space_id.is_empty():
		return
	var building_spaces: Array = await SupabaseManager.get_building_spaces_for_space(space_id)
	if building_spaces.is_empty():
		print("LocationManager: no building found for space ", space_id)
		return

	print("LocationManager: building has ", building_spaces.size(), " spaces")
	for bs in building_spaces:
		_space_offsets[bs.space_id] = bs.offset_transformation


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
		var actual    := kabsch_dst[i]
		print("  ref[", i, "] error=", snappedf(predicted.distance_to(actual), 0.001), "m")

	if not first_calibration:
		return

	# Now definitely localized — set space ID and load building offsets, then place cross-room anchors.
	_current_space_id = get_current_space_id()
	await _load_building_offsets(_current_space_id)

	calibrated.emit()

	# Clear any previously placed markers
	for node in _marker_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_marker_nodes.clear()

	# Place current-space desktop anchors
	for anchor in _desktop_content:
		_place_virtual_marker(anchor, anchor.space_id)

	# Place anchors from all other spaces in the building
	for anchor in _all_anchors.values():
		if anchor.space_id == _current_space_id:
			continue
		if anchor.glb_position == null:
			continue
		if anchor.is_reference:
			continue
		_place_virtual_marker(anchor, anchor.space_id)

	# Flush pending saves (newly placed anchors that arrived before calibration)
	for uuid in _pending_save:
		var node: Node3D = _pending_save[uuid]
		_write_glb_position(uuid, node.position)
	_pending_save.clear()


func world_to_local(building_pos: Vector3) -> Vector3:
	## Convert a building-world-space position into headset local space.
	## building_pos is in the coordinate system of the navmesh (all space transforms applied).
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	return _calibration * (current_offset.affine_inverse() * building_pos)


func _to_local(glb_pos: Vector3, space_id: String) -> Vector3:
	# Convert a GLB-space position from any space into headset LOCAL space.
	# Uses the building offset to map into the calibrated space's frame first.
	if space_id == _current_space_id or _space_offsets.is_empty():
		return _calibration * glb_pos

	var other_offset: Transform3D = _space_offsets.get(space_id, Transform3D.IDENTITY)
	var current_offset: Transform3D = _space_offsets.get(_current_space_id, Transform3D.IDENTITY)
	# building_glb = other_offset * glb_pos
	# current_space_glb = current_offset.inverse() * building_glb
	var current_space_glb := current_offset.affine_inverse() * (other_offset * glb_pos)
	return _calibration * current_space_glb


func _write_glb_position(uuid: String, local_pos: Vector3) -> void:
	var glb_pos: Vector3 = _calibration.affine_inverse() * local_pos
	SupabaseManager.update_anchor_glb_position(uuid, glb_pos)


func _place_virtual_marker(anchor: Anchor, space_id: String) -> void:
	var local_pos := _to_local(anchor.glb_position, space_id)
	var is_other_space := space_id != _current_space_id
	var color := Color(0.5, 0.3, 1.0) if is_other_space else Color(1.0, 0.55, 0.0)
	var marker := _make_marker(color, anchor.name)
	marker.position = local_pos
	get_parent().add_child(marker)
	_marker_nodes.append(marker)


# ── AnchorManager callback ────────────────────────────────────────────────────

func _on_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	var uuid_str := str(ml2_uuid)

	if is_new:
		var new_anchor: Anchor = _all_anchors.get(uuid_str)
		anchor_node.add_child(_make_marker(Color(0.2, 0.8, 1.0), new_anchor.name if new_anchor else ""))
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
		anchor_node.add_child(_make_marker(Color(1.0, 0.85, 0.0), _all_anchors.get(
			_ref_anchors[uuid_str].id, Anchor.new()).name))
		_try_calibrate()
	else:
		# Content anchor — show marker if already calibrated, else defer
		if _calibrated:
			var anchor: Anchor = _get_anchor_by_ml2(uuid_str)
			if anchor and anchor.glb_position:
				var local_pos := _to_local(anchor.glb_position, anchor.space_id)
				anchor_node.position = local_pos
			anchor_node.add_child(_make_marker(Color(0.2, 0.8, 1.0),
				_get_anchor_by_ml2(uuid_str).name if _get_anchor_by_ml2(uuid_str) else ""))
		else:
			# Will be visualised once calibration runs
			pass


func _get_anchor_by_ml2(ml2_id: String) -> Anchor:
	for anchor in _all_anchors.values():
		if anchor.ml2_id == ml2_id:
			return anchor
	return null


# ── Marker ────────────────────────────────────────────────────────────────────

func _make_marker(color: Color = Color(0.2, 0.8, 1.0), label: String = "") -> Node3D:
	var root := Node3D.new()

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.10
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	root.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.5
	light.omni_range = 0.5
	root.add_child(light)

	if label != "":
		var lbl := Label3D.new()
		lbl.text = label
		lbl.position = Vector3(0, 0.10, 0)
		lbl.font_size = 128
		lbl.pixel_size = 0.0005
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.no_depth_test = true
		lbl.modulate = color
		root.add_child(lbl)

	return root
