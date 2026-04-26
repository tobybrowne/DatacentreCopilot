extends Node
class_name LocationManager

## Thin localization manager: ML2 localization requests, quality polling,
## user position writing, coarse space detection, and relocalisation.
## All anchor loading, calibration, and marker placement is owned by AnchorManager.
## Must be a child of XROrigin3D. Depends on AnchorManager.

signal calibrated
signal space_picker_needed(spaces: Array[Space])
signal navigation_ready(space_id: String)
signal coarse_space_changed(coarse_id: String, active_id: String)

var _anchor_manager: AnchorManager
var _space_manager: SpaceManager

@export var write_user_position := false
var _user_pos_timer := 0.0
const USER_POS_INTERVAL := 1.0

var _loc_poll_timer := 0.0
const LOC_POLL_INTERVAL := 2.0
var _last_loc_confidence := -1

var current_coarse_space := ""
var _poor_quality_timer := 0.0
const POOR_RELOC_THRESHOLD := 10.0
var _relocalising := false

var _tracking_dot_mat: StandardMaterial3D
var _tracking_label: Label3D

# IdleState reads _calibrated directly on location_manager
var _calibrated: bool:
	get: return _anchor_manager._calibrated if _anchor_manager else false


func _ready() -> void:
	_anchor_manager = get_parent().get_node_or_null("AnchorManager")
	_space_manager  = get_parent().get_node_or_null("SpaceManager")
	if not _anchor_manager:
		push_warning("LocationManager: AnchorManager not found")
		return
	_anchor_manager.calibrated.connect(func(): calibrated.emit())
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

	if not _anchor_manager or not _anchor_manager._calibrated:
		return
	_user_pos_timer += delta
	if _user_pos_timer >= USER_POS_INTERVAL:
		_user_pos_timer = 0.0
		var camera := get_parent().get_node_or_null("XRCamera3D")
		if camera:
			var space_glb_pos: Vector3 = _anchor_manager.world_to_glb(camera.position)
			var offsets := _anchor_manager.get_space_offsets()
			var current_offset: Transform3D = offsets.get(_anchor_manager.get_current_space_id(), Transform3D.IDENTITY)
			_update_room_label(current_offset * space_glb_pos)
			if write_user_position:
				SupabaseManager.update_user_glb_position(space_glb_pos)


func _update_room_label(building_pos: Vector3) -> void:
	var closest_id := ""
	var closest_dist := INF
	var offsets := _anchor_manager.get_space_offsets()
	for anchor in _anchor_manager.get_all_anchors().values():
		if anchor.name != "__centroid__" or anchor.glb_position == null:
			continue
		var offset: Transform3D = offsets.get(anchor.space_id, Transform3D.IDENTITY)
		var dist: float = building_pos.distance_to(offset * anchor.glb_position)
		if dist < closest_dist:
			closest_dist = dist
			closest_id = anchor.space_id

	if closest_id.is_empty():
		return
	current_coarse_space = closest_id
	coarse_space_changed.emit(closest_id, _anchor_manager.get_current_space_id())


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
			if not current_coarse_space.is_empty() and current_coarse_space != _anchor_manager.get_current_space_id():
				_attempt_relocalisation(current_coarse_space)
				_poor_quality_timer = 0.0
	else:
		_poor_quality_timer = 0.0


func _attempt_relocalisation(target_space_id: String) -> void:
	var ref_count := _anchor_manager.ref_anchor_count(target_space_id)
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
				if not new_uuid.is_empty() and new_uuid != _anchor_manager.get_current_space_id():
					print("LocationManager: relocalised to ", new_uuid)
					current_coarse_space = new_uuid
					_anchor_manager.calibrate_to_space(new_uuid)
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


# ── Public API ────────────────────────────────────────────────────────────────

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
	_request_localization(space_id)
	await _anchor_manager.localize_to_space(space_id)


## Localise into a space and run Kabsch calibration as reference anchors track in.
func calibrate_to_space(space_id: String) -> void:
	_request_localization(space_id)
	await _anchor_manager.calibrate_to_space(space_id)
	print("LocationManager: calibrate_to_space ", space_id)


## Called when the user wants to navigate within a building.
func request_navigation(building_id: String) -> void:
	var spaces: Array[Space] = await SupabaseManager.get_spaces_for_building(building_id)
	print("LocationManager: building has ", spaces.size(), " spaces, coarse=", current_coarse_space)
	var space_ids := spaces.map(func(s: Space): return s.id)
	if current_coarse_space in space_ids:
		navigation_ready.emit(current_coarse_space)
	else:
		space_picker_needed.emit(spaces)


# ── Proxy methods (backward-compatible) ──────────────────────────────────────

func get_calibration() -> Transform3D:
	return _anchor_manager.get_calibration() if _anchor_manager else Transform3D.IDENTITY

func world_to_glb(world_pos: Vector3) -> Vector3:
	return _anchor_manager.world_to_glb(world_pos) if _anchor_manager else world_pos

func glb_to_world(glb_pos: Vector3) -> Vector3:
	return _anchor_manager.glb_to_world(glb_pos) if _anchor_manager else glb_pos

func world_to_local(building_pos: Vector3) -> Vector3:
	return _anchor_manager.world_to_local(building_pos) if _anchor_manager else building_pos

func get_current_space_id() -> String:
	var ext := _ml2_ext()
	return ext.get_localization_map_uuid() if ext else ""

func create_content_anchor(local_pos: Vector3) -> String:
	if not _anchor_manager:
		return ""
	return await _anchor_manager.create_content_anchor(local_pos)

func get_space_anchors(space_id: String) -> Array[Anchor]:
	if not _anchor_manager:
		return []
	return _anchor_manager.get_space_anchors(space_id)

func clear_markers() -> void:
	if _anchor_manager:
		_anchor_manager.clear_markers()


# ── Internal ──────────────────────────────────────────────────────────────────

func _request_localization(space_id: String) -> void:
	var ext := _ml2_ext()
	if ext and ext.has_method("request_localization"):
		ext.request_localization(space_id)
