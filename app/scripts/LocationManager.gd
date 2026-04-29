# Thin localisation manager, handles ML2 localization requests, quality polling, 
# user position writing, coarse space detection, and relocalisation.
# All anchor loading, calibration, and marker placement is owned by AnchorManager.
# Must be a child of XROrigin3D.

extends Node
class_name LocationManager

signal calibrated
signal coarse_space_changed(coarse_id: String, active_id: String)

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

# onetime call, to instantiate the tracking quality dot
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
			# find the user's position in building co-ordinates
			var space_glb_pos: Vector3 = _anchor_manager.world_to_glb(camera.position)
			var offsets := _anchor_manager.get_space_offsets()
			var current_offset: Transform3D = offsets.get(_anchor_manager.get_current_space_id(), Transform3D.IDENTITY)
			
			# find the coarse space lable and update the user position in the database
			_update_room_label(current_offset * space_glb_pos)
			if write_user_position:
				SupabaseManager.update_user_glb_position(space_glb_pos)


# uses the centroid anchors to find the user's closes space, updates current_coarse_space accordingly
func _update_room_label(building_pos: Vector3) -> void:
	var closest_id := ""
	var closest_dist := INF
	var offsets := _anchor_manager.get_space_offsets()

	for anchor in _anchor_manager.get_all_anchors().values():
		# TO-DO: if we continue with centroids then they need dedicated types
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


# called by _process on a timer
func _poll_localization() -> void:
	var ext := _ml2_ext()
	if not ext:
		return
	
	# poll extension for localisation confidence
	var confidence: int = ext.get_localization_confidence() if ext.has_method("get_localization_confidence") else -1
	if confidence != _last_loc_confidence:
		_last_loc_confidence = confidence
		var labels := ["POOR", "FAIR", "GOOD", "EXCELLENT"]
		var label: String = labels[confidence] if confidence >= 0 and confidence < labels.size() else str(confidence)
		print("LocationManager: confidence=", label, " uuid=", ext.get_localization_map_uuid())

	# update the tracking dot color
	if _tracking_dot_mat:
		match confidence:
			3: _tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # EXCELLENT — green
			2: _tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)   # GOOD — green
			1: _tracking_dot_mat.albedo_color = Color(1.0, 0.55, 0.0)  # FAIR — orange
			0: _tracking_dot_mat.albedo_color = Color(1.0, 0.2, 0.2)   # POOR — red
			_: _tracking_dot_mat.albedo_color = Color(0.5, 0.5, 0.5)   # unknown — grey

	# if confidence if poor for POOR_RELOC_THRESHOLD seconds, attempt relocalisation to the current coarse space
	if confidence == 0:
		_poor_quality_timer += LOC_POLL_INTERVAL
		if _poor_quality_timer >= POOR_RELOC_THRESHOLD:
			if not current_coarse_space.is_empty() and current_coarse_space != _anchor_manager.get_current_space_id():
				_attempt_relocalisation(current_coarse_space)
				_poor_quality_timer = 0.0
	else:
		_poor_quality_timer = 0.0


func _attempt_relocalisation(target_space_id: String) -> void:
	# can only relocalise to a space with 3 anchor references
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
	if _tracking_label:
		# set tracking label to ? during relocalisation attempt
		_tracking_label.text = "?"

# called by the ML2 extension when localisation state changes, including after a relocalisation attempt
func _on_localization_changed(state: int, _confidence: int, _error_flags: int) -> void:
	print("LocationManager: _on_localization_changed state=", state, " confidence=", _confidence, " error_flags=", _error_flags)
	match state:
		1: # LOCALIZED — success
			var was_relocalising := _relocalising
			_relocalising = false
			if _tracking_label:
				_tracking_label.text = ""
			
			# try and relocalise if _relocalising was set
			# this means functions like _request_localization can run without triggering a calibration
			if was_relocalising:
				var ext := _ml2_ext()
				if ext:
					var ml2_uuid: String = ext.get_localization_map_uuid()
					if not ml2_uuid.is_empty():
						var supabase_id := _space_manager.get_supabase_id(ml2_uuid) if _space_manager else ml2_uuid
						if supabase_id != _anchor_manager.get_current_space_id():
							print("LocationManager: relocalised to ", supabase_id)
							current_coarse_space = supabase_id
							# calibrate to the new space, load anchors, etc...
							_anchor_manager.calibrate_to_space(supabase_id)

		0: # NOT_LOCALIZED
			if _relocalising:
				# if you were relocalising, then this attempt failed
				_relocalising = false
				if _tracking_label:
					_tracking_label.text = "!"
				print("LocationManager: relocalisation failed — NOT_LOCALIZED")
			else:
				if _tracking_label:
					_tracking_label.text = ""
					
		2, 3: # PENDING / SLEEPING — keep ? visible, do nothing
			pass


# localise into a space and run Kabsch calibration as reference anchors track in.
func calibrate_to_space(space_id: String) -> void:
	_request_localization(space_id)
	await _anchor_manager.calibrate_to_space(space_id)
	print("LocationManager: calibrate_to_space ", space_id)


# TO-DO: check how this behaves if no space is localised
func get_current_space_id() -> String:
	var ext := _ml2_ext()
	return ext.get_localization_map_uuid() if ext else ""


# direct localisation request made to the extension
func _request_localization(space_id: String) -> void:
	var ext := _ml2_ext()
	if ext:
		var ml2_uuid := _space_manager.get_ml2_uuid(space_id) if _space_manager else space_id
		ext.request_localization(ml2_uuid)
