# Thin localisation manager, handles ML2 localization requests, quality polling,
# user position writing, coarse space detection, and relocalisation.
# All anchor loading, calibration, and marker placement is owned by AnchorManager.
# Must be a child of XROrigin3D.

extends Node
class_name LocationManager

signal calibrated
signal coarse_space_changed(space_id: String)
signal localised_space_changed(space_id: String)

var _anchor_manager: AnchorManager
var _space_manager: SpaceManager

# for updating the user position co-ordinate in the database (mainly demo atm)
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

var _indicator: TrackingIndicator

@export var show_bounding_boxes: bool = true:
	set(v):
		show_bounding_boxes = v
		for vis in _bbox_visuals:
			vis.visible = v

var _bbox_visuals: Array[BoundingBoxVisual] = []

# IdleState reads _calibrated directly on location_manager
var _calibrated: bool:
	get: return _anchor_manager._calibrated if _anchor_manager else false


func _ready() -> void:
	_anchor_manager = get_parent().get_node_or_null("AnchorManager")
	_space_manager  = get_parent().get_node_or_null("SpaceManager")
	if not _anchor_manager:
		push_warning("LocationManager: AnchorManager not found")
		return
	_anchor_manager.calibrated.connect(_on_calibrated)
	_create_tracking_indicator()

	var ext := _ml2_ext()
	if ext:
		ext.localization_changed.connect(_on_localization_changed)


func _on_calibrated() -> void:
	calibrated.emit()
	_rebuild_bbox_visuals()


func _rebuild_bbox_visuals() -> void:
	for vis in _bbox_visuals:
		vis.queue_free()
	_bbox_visuals.clear()

	var spaces := _anchor_manager.get_building_spaces()
	for i in spaces.size():
		var space: Space = spaces[i]
		if space.loc_bounding_box.is_empty():
			continue
		var vis := BoundingBoxVisual.new()
		vis.bbox = space.loc_bounding_box
		vis.color = BoundingBoxVisual.COLORS[i % BoundingBoxVisual.COLORS.size()]
		vis.anchor_manager = _anchor_manager
		vis.visible = show_bounding_boxes
		get_parent().add_child(vis)
		_bbox_visuals.append(vis)


func _ml2_ext() -> Object:
	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		return Engine.get_singleton("OpenXRMlLocalizationMapExtension")
	return null


# onetime call, to instantiate the tracking indicator
func _create_tracking_indicator() -> void:
	var camera := get_parent().get_node_or_null("XRCamera3D")
	if not camera:
		return
	_indicator = TrackingIndicator.new()
	camera.add_child(_indicator)


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
			# find the user's position in building co-ordinates
			var space_glb_pos: Vector3 = _anchor_manager.world_to_glb(camera.position)
			var offsets := _anchor_manager.get_space_offsets()
			var current_offset: Transform3D = offsets.get(_anchor_manager.get_current_space_id(), Transform3D.IDENTITY)

			# find the coarse space label and update the user position in the database
			_update_room_label(current_offset * space_glb_pos)
			if write_user_position:
				SupabaseManager.update_user_glb_position(space_glb_pos)


# Returns true if building_pos falls inside the loc_bounding_box polygon.
# vertices_2d are [x, z] pairs; the polygon is in the XZ plane.
func _point_in_bbox(pos: Vector3, bbox: Dictionary) -> bool:
	if pos.y < bbox.get("y_min", -INF) or pos.y > bbox.get("y_max", INF):
		return false
	var verts: Array = bbox.get("vertices_2d", [])
	if verts.size() < 3:
		return false
	var inside := false
	var n := verts.size()
	var j := n - 1
	for i in n:
		var xi: float = verts[i][0]; var zi: float = verts[i][1]
		var xj: float = verts[j][0]; var zj: float = verts[j][1]
		if ((zi > pos.z) != (zj > pos.z)) and (pos.x < (xj - xi) * (pos.z - zi) / (zj - zi) + xi):
			inside = not inside
		j = i
	return inside


# Uses loc_bounding_box for containment, falls back to centroid distance.
func _update_room_label(building_pos: Vector3) -> void:
	var spaces := _anchor_manager.get_building_spaces()
	var offsets := _anchor_manager.get_space_offsets()

	var contained: Array[String] = []
	for space in spaces:
		if not space.loc_bounding_box.is_empty() and _point_in_bbox(building_pos, space.loc_bounding_box):
			contained.append(space.id)

	var closest_id := ""
	if contained.size() == 1:
		closest_id = contained[0]
	else:
		# Fallback: nearest centroid anchor — restricted to contained set when overlapping, else all spaces.
		var closest_dist := INF
		for anchor in _anchor_manager.get_all_anchors().values():
			if anchor.name != "__centroid__" or anchor.glb_position == null:
				continue
			if contained.size() > 1 and not anchor.space_id in contained:
				continue
			var offset: Transform3D = offsets.get(anchor.space_id, Transform3D.IDENTITY)
			var dist: float = building_pos.distance_to(offset * anchor.glb_position)
			if dist < closest_dist:
				closest_dist = dist
				closest_id = anchor.space_id

	if closest_id.is_empty():
		return
	if closest_id != current_coarse_space:
		coarse_space_changed.emit(closest_id)
		current_coarse_space = closest_id


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

	if _indicator:
		_indicator.set_confidence(confidence)

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
	var ml2_uuid := _space_manager.get_ml2_uuid(target_space_id) if _space_manager else target_space_id
	ext.request_localization(ml2_uuid)
	_relocalising = true
	if _indicator:
		_indicator.set_spinning(true)


func _on_localization_changed(state: int, _confidence: int, _error_flags: int) -> void:
	match state:
		1: # LOCALIZED — success
			var was_relocalising := _relocalising
			_relocalising = false
			if was_relocalising:
				if _indicator:
					_indicator.set_spinning(false)
				var ext := _ml2_ext()
				if ext:
					var ml2_uuid: String = ext.get_localization_map_uuid()
					if not ml2_uuid.is_empty():
						var supabase_id := _space_manager.get_supabase_id(ml2_uuid) if _space_manager else ml2_uuid
						if supabase_id != _anchor_manager.get_current_space_id():
							print("LocationManager: relocalised to ", supabase_id)
							current_coarse_space = supabase_id
							localised_space_changed.emit(supabase_id)
							_anchor_manager.calibrate_to_space(supabase_id)

		0: # NOT_LOCALIZED
			if _relocalising:
				_relocalising = false
				if _indicator:
					_indicator.set_spinning(false)
				print("LocationManager: relocalisation failed — NOT_LOCALIZED")

		2, 3: # PENDING / SLEEPING
			pass


func calibrate_to_space(space_id: String) -> void:
	_request_localization(space_id)
	await _wait_for_fair_localisation()
	await _anchor_manager.calibrate_to_space(space_id)
	print("LocationManager: calibrate_to_space ", space_id)
	localised_space_changed.emit(space_id)


func _wait_for_fair_localisation() -> void:
	var ext := _ml2_ext()
	if not ext:
		return
	if ext.get_localization_confidence() >= 1:
		return
	print("LocationManager: waiting for FAIR localisation…")
	if _indicator:
		_indicator.set_spinning(true)
	while true:
		var args = await ext.localization_changed
		if args[0] == 1 and args[1] >= 1:
			print("LocationManager: reached FAIR — proceeding with calibration")
			break
	if _indicator:
		_indicator.set_spinning(false)


func get_current_space_id() -> String:
	var ext := _ml2_ext()
	return ext.get_localization_map_uuid() if ext else ""


func _request_localization(space_id: String) -> void:
	var ext := _ml2_ext()
	if ext:
		var ml2_uuid := _space_manager.get_ml2_uuid(space_id) if _space_manager else space_id
		ext.request_localization(ml2_uuid)
