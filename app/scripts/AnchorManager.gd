extends Node
class_name AnchorManager

# NOTE: spatial anchors are attached to the SPACE, not the application.
# We track our own subset in Supabase so we only load anchors that belong to us.

## Manages ML2 spatial anchors: create, load, persist, and visualise.
## Must be a child of XROrigin3D.

var _ml_mgr: Node  # OpenXRMlSpatialAnchorManager, created at runtime if available.
var _anchors_loaded := false

# Counter for auto-naming new anchors. Initialised above the highest existing number on load.
var _next_num := 1

# All anchors fetched from DB (uuid → Anchor), for name lookup in callbacks.
var _all_anchors: Dictionary = {}

# Reference anchors fetched from DB (uuid → Anchor), used to build Kabsch pairs.
# Only anchors that have a glb_position are useful here.
var _ref_anchors: Dictionary = {}

# Desktop-placed content anchors have no ML2 UUID — we visualise them via calibration.
var _desktop_content: Array[Anchor] = []

# Kabsch inputs — store node refs so _try_calibrate always reads live positions.
var _kabsch_src: Array[Vector3] = []       # GLB-space positions (fixed, from DB)
var _kabsch_nodes: Array[Node3D] = []      # tracked nodes for live LOCAL-space positions
var _recalib_timer := 0.0
const RECALIB_INTERVAL := 2.0             # re-run Kabsch every N seconds while calibrated
var _user_pos_timer := 0.0
const USER_POS_INTERVAL := 1.0            # push user GLB position every N seconds

# Calibration state — maps GLB space → LOCAL space.
var _calibration := Transform3D.IDENTITY
var _calibrated := false

# Newly-placed anchors that arrived before calibration was ready.
# We save their glb_position once calibration is computed.
var _pending_save: Dictionary = {}  # uuid → anchor_node (Node3D)

# All currently-tracked anchor nodes, for proximity queries.
var _tracked_nodes: Dictionary = {}  # uuid → Node3D

# UUIDs from the initial DB load that failed — retried with a delay indefinitely.
var _retry_uuids: Dictionary = {}  # uuid → retry_count
const RETRY_DELAY := 3.0

# Localization state — set when any anchor successfully loads (reliable proxy for localization).
var is_localized := false
var localized_space_uuid := ""
signal space_localized(uuid: String)


func _ready() -> void:
	if not ClassDB.class_exists("OpenXRMlSpatialAnchorManager"):
		push_warning("AnchorManager: OpenXRMlSpatialAnchorManager unavailable — spatial anchors disabled.")
		return

	_ml_mgr = ClassDB.instantiate("OpenXRMlSpatialAnchorManager")
	_ml_mgr.connect("openxr_ml_spatial_anchor_tracked", _on_anchor_tracked)
	_ml_mgr.connect("openxr_ml_spatial_anchor_untracked", _on_anchor_untracked)
	_ml_mgr.connect("openxr_ml_spatial_anchor_create_failed", _on_create_failed)
	_ml_mgr.connect("openxr_ml_spatial_anchor_load_failed", _on_load_failed)

	_ml_mgr.tree_entered.connect(_on_mgr_entered_tree)
	get_parent().add_child.call_deferred(_ml_mgr)


func _process(delta: float) -> void:
	if not _calibrated:
		return
	_recalib_timer += delta
	if _recalib_timer >= RECALIB_INTERVAL:
		_recalib_timer = 0.0
		_try_calibrate()
	_user_pos_timer += delta
	if _user_pos_timer >= USER_POS_INTERVAL:
		_user_pos_timer = 0.0
		var camera := get_parent().get_node_or_null("XRCamera3D")
		if camera:
			var glb_pos: Vector3 = _calibration.affine_inverse() * camera.position
			SupabaseManager.update_user_glb_position(glb_pos)


func _on_mgr_entered_tree() -> void:
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr:
		xr.session_begun.connect(_load_anchors_from_db)
		if xr.is_initialized():
			_load_anchors_from_db()


# ── Public API ─────────────────────────────────────────────────────────────────

func place_anchor(world_transform: Transform3D) -> void:
	"""
	Place a new content anchor at world_transform.
	ML2 fires _on_anchor_tracked(is_new=true) on success, where we compute and
	save the glb_position via the current calibration.
	"""
	if not _ml_mgr:
		return
	# var loc_ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension") if Engine.has_singleton("OpenXRMlLocalizationMapExtension") else null
	# var confidence: int = loc_ext.get_localization_confidence() if loc_ext else -1
	# if confidence < 2:  # 2 = LOCALIZATION_CONFIDENCE_GOOD
	# 	push_warning("AnchorManager: cannot place anchor — localization confidence too low (%d)" % confidence)
	# 	return
	print("AnchorManager: placing anchor at ", world_transform.origin)
	_ml_mgr.call("create_anchor", world_transform)


func remove_anchor(anchor: Anchor) -> void:
	"""
	Permanently deletes an anchor from ML2 storage and Supabase.
	"""
	if not _ml_mgr:
		return

	if anchor.ml2_id != null:
		_ml_mgr.call("untrack_anchor", anchor.ml2_id)
	SupabaseManager.remove_anchor(str(anchor.id))


# ── Loading ────────────────────────────────────────────────────────────────────

func _load_anchors_from_db() -> void:
	if _anchors_loaded:
		return
	_anchors_loaded = true

	var all_anchors: Array[Anchor] = await SupabaseManager.get_anchors()
	print("AnchorManager: fetched ", all_anchors.size(), " anchors from DB")

	for anchor in all_anchors:
		_all_anchors[anchor.id] = anchor
		if anchor.name.is_valid_int():
			_next_num = max(_next_num, anchor.name.to_int() + 1)

	for anchor in all_anchors:
		if anchor.is_reference:
			if anchor.glb_position != null:
				# Store for Kabsch lookup, then tell ML2 to track it.
				_ref_anchors[anchor.ml2_id] = anchor
				_retry_uuids[anchor.ml2_id] = 0
				_ml_mgr.call("load_anchor", StringName(anchor.ml2_id))
				print("AnchorManager: loading reference anchor ", anchor.id)
			else:
				print("AnchorManager: reference anchor ", anchor.id, " has no glb_position — skipping")
		else:
			if anchor.ml2_id != null:
				# Has an ML2 UUID — load for accurate per-frame tracking.
				_retry_uuids[anchor.ml2_id] = 0
				_ml_mgr.call("load_anchor", StringName(anchor.ml2_id))
				print("AnchorManager: loading headset content anchor ", anchor.id)
			else:
				# Desktop-placed — no ML2 UUID, visualise via calibration once ready.
				_desktop_content.append(anchor)
				print("AnchorManager: queued desktop content anchor ", anchor.id)


# ── Calibration ────────────────────────────────────────────────────────────────

func _try_calibrate() -> void:
	"""
	Run Kabsch once we have ≥3 reference pairs. Called each time a new pair arrives,
	so calibration improves incrementally as more reference anchors are tracked.
	"""
	print("Try Calibrate!")
	print(_kabsch_src.size())

	if _kabsch_src.size() < 3:
		print("AnchorManager: need ≥3 reference anchors for calibration (have ", _kabsch_src.size(), ")")
		return

	# Build dst from live node positions so settled positions are always used.
	var kabsch_dst: Array[Vector3] = []
	for node in _kabsch_nodes:
		kabsch_dst.append(node.position)

	var first_calibration := not _calibrated
	_calibration = Kabsch.compute(_kabsch_src, kabsch_dst)
	_calibrated = true

	# Log calibration quality: how well does the transform map each ref pair?
	print("AnchorManager: calibration from ", _kabsch_src.size(), " reference points")
	for i in _kabsch_src.size():
		var predicted := _calibration * _kabsch_src[i]
		var actual    := kabsch_dst[i]
		print("  ref[", i, "] glb=", _kabsch_src[i],
			"  predicted_local=", predicted.snappedf(0.001),
			"  actual_local=",    actual.snappedf(0.001),
			"  error=", snappedf(predicted.distance_to(actual), 0.001), "m")

	if not first_calibration:
		return

	# First time calibrated — materialise desktop anchors and flush pending saves.
	for anchor in _desktop_content:
		print("Placing Desktop Anchor: ", anchor.name)
		_place_virtual_marker(anchor)

	for uuid in _pending_save:
		var node: Node3D = _pending_save[uuid]
		_write_glb_position(uuid, node.position)
	_pending_save.clear()


func _write_glb_position(uuid: String, local_pos: Vector3) -> void:
	"""
	Inverse-transform a LOCAL-space position back to GLB space and persist it.
	"""
	var glb_pos: Vector3 = _calibration.affine_inverse() * local_pos
	print("AnchorManager: saving glb_position for ", uuid, " → ", glb_pos)
	SupabaseManager.update_anchor_glb_position(uuid, glb_pos)


func _place_virtual_marker(anchor: Anchor) -> void:
	"""
	Compute LOCAL position for a desktop-placed anchor and add a static marker.
	(No ML2 tracking — refreshed each session when calibration reruns.)
	"""
	print("AnchorManager: desktop anchor '", anchor.name, "' glb_position=", anchor.glb_position)
	var local_pos: Vector3 = _calibration * anchor.glb_position
	print("AnchorManager: desktop anchor '", anchor.name, "' → local_pos=", local_pos.snappedf(0.001))
	var marker := _make_marker(Color(1.0, 0.55, 0.0), anchor.name)  # orange = desktop-placed
	marker.position = local_pos
	get_parent().add_child(marker)


# ── Callbacks ──────────────────────────────────────────────────────────────────

func get_anchor_near(pos: Vector3, radius: float) -> Anchor:
	for uuid in _tracked_nodes:
		var node: Node3D = _tracked_nodes[uuid]
		if is_instance_valid(node) and node.global_position.distance_to(pos) <= radius:
			return _all_anchors[uuid]
	return null


func _on_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	"""
	Fires once per anchor per session — either a new anchor was just created,
	or an existing anchor finished loading from ML2 storage.
	anchor_node.position is in LOCAL space (relative to XROrigin3D).
	"""
	print("AnchorManager: tracked ", ml2_uuid, " (new=", is_new, ")")
	var uuid_str := str(ml2_uuid)
	_tracked_nodes[uuid_str] = anchor_node
	_retry_uuids.erase(uuid_str)

	if not is_localized:
		var map_uuid := ""
		if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
			map_uuid = Engine.get_singleton("OpenXRMlLocalizationMapExtension").get_localization_map_uuid()
		is_localized = true
		localized_space_uuid = map_uuid
		print("AnchorManager: LOCALIZED — space UUID: ", map_uuid)
		space_localized.emit(map_uuid)

	if is_new:
		# User just placed a brand-new reference anchor.
		var new_anchor := Anchor.new()
		new_anchor.ml2_id = uuid_str
		new_anchor.name = str(_next_num)
		new_anchor.is_reference = true
		new_anchor.space_id = localized_space_uuid
		_next_num += 1
		_all_anchors[uuid_str] = new_anchor
		SupabaseManager.insert_anchor(new_anchor)

		if _calibrated:
			# Wait one frame — XR runtime populates position after the signal fires.
			await get_tree().process_frame
			_write_glb_position(uuid_str, anchor_node.position)
		else:
			_pending_save[uuid_str] = anchor_node

		anchor_node.add_child(_make_marker(Color(0.2, 0.8, 1.0), new_anchor.name))
		return

	# Existing anchor loaded from ML2 — is it a reference or content anchor?
	# Wait one frame before reading position: ML2 fires the signal before the XR
	# runtime has written the anchor's transform into the node.
	await get_tree().process_frame

	var loaded_name: String = (_all_anchors[uuid_str].name if _all_anchors.has(uuid_str) else "")
	if _ref_anchors.has(uuid_str):
		var ref: Anchor = _ref_anchors[uuid_str]
		_kabsch_src.append(ref.glb_position)
		_kabsch_nodes.append(anchor_node)
		print("AnchorManager: Kabsch pair #", _kabsch_src.size(), " added for ", uuid_str, " local=", anchor_node.position.snappedf(0.001))
		anchor_node.add_child(_make_marker(Color(1.0, 0.85, 0.0), loaded_name))  # yellow = reference
		_try_calibrate()
	else:
		anchor_node.add_child(_make_marker(Color(0.2, 0.8, 1.0), loaded_name))


func _on_anchor_untracked(uuid: StringName) -> void:
	print("AnchorManager: untracked ", uuid)
	_tracked_nodes.erase(str(uuid))


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


# ── Marker ─────────────────────────────────────────────────────────────────────

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
