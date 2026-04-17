extends Node
class_name AnchorManager

# NOTE: spatial anchors are attached to the SPACE, not the application.
# We track our own subset in Supabase so we only load anchors that belong to us.

## ML2 spatial anchor lifecycle: create, load, track, remove.
## Higher-level calibration and visualisation is handled by LocationManager.
## Must be a child of XROrigin3D.

var _ml_mgr: Node
var _next_num := 1

# Registry populated by LocationManager so get_anchor_near() can resolve UUIDs.
var _all_anchors: Dictionary = {}   # supabase_id → Anchor
var tracked_nodes: Dictionary = {} # ml2_uuid → Node3D (public so LocationManager can inject already-tracked anchors into Kabsch)

var _retry_uuids: Dictionary = {}   # ml2_uuid → retry_count
var _storage_pending: Array[String] = []  # UUIDs waiting for storage to become ready
var _storage_retry_timer := 0.0
const RETRY_DELAY := 3.0
const STORAGE_RETRY_INTERVAL := 2.0

var is_localized := false
var localized_space_uuid := ""

signal space_localized(uuid: String)
signal anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool)
signal anchor_untracked(uuid: StringName)


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


func _on_mgr_entered_tree() -> void:
	pass


func _process(delta: float) -> void:
	if _storage_pending.is_empty() or not _ml_mgr:
		return
	_storage_retry_timer -= delta
	if _storage_retry_timer > 0.0:
		return
	_storage_retry_timer = STORAGE_RETRY_INTERVAL
	print("AnchorManager: retrying ", _storage_pending.size(), " pending anchors")
	for uuid in _storage_pending.duplicate():
		_ml_mgr.call("load_anchor", StringName(uuid))


# ── Public API ────────────────────────────────────────────────────────────────

func set_anchor_registry(all_anchors: Dictionary) -> void:
	_all_anchors = all_anchors

func set_next_num(n: int) -> void:
	_next_num = n

func load_anchor(uuid: String) -> void:
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


func clear_markers() -> void:
	for node in tracked_nodes.values():
		if is_instance_valid(node):
			for child in node.get_children():
				child.queue_free()


func get_anchor_near(pos: Vector3, radius: float) -> Anchor:
	for uuid in tracked_nodes:
		var node: Node3D = tracked_nodes[uuid]
		if is_instance_valid(node) and node.global_position.distance_to(pos) <= radius:
			# Find by ml2_id
			for anchor in _all_anchors.values():
				if str(anchor.ml2_id) == uuid:
					return anchor
	return null


# ── Helpers ───────────────────────────────────────────────────────────────────

func _get_anchor_by_ml2(ml2_id: String) -> Anchor:
	for anchor in _all_anchors.values():
		if anchor.ml2_id == ml2_id:
			return anchor
	return null


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


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	var uuid_str := str(ml2_uuid)
	print("AnchorManager: tracked ", uuid_str, " (new=", is_new, ")")
	tracked_nodes[uuid_str] = anchor_node
	_retry_uuids.erase(uuid_str)
	_storage_pending.erase(uuid_str)

	if is_new:
		var location_manager: LocationManager = get_parent().get_node_or_null("LocationManager")
		var new_anchor := Anchor.new()
		new_anchor.ml2_id = uuid_str
		new_anchor.name = str(_next_num)
		new_anchor.anchor_type = Anchor.TYPE_REFERENCE
		new_anchor.space_id = location_manager.get_current_space_id() if location_manager else ""
		_next_num += 1
		_all_anchors[new_anchor.id] = new_anchor
		SupabaseManager.insert_anchor(new_anchor)
		# Newly created — no glb_position yet, show as incomplete (cyan)
		anchor_node.add_child(_make_marker(Color(0.2, 0.8, 1.0), new_anchor.name))
	else:
		var anchor := _get_anchor_by_ml2(uuid_str)
		var label := anchor.name if anchor else ""
		var color: Color
		if anchor and anchor.glb_position != null:
			color = Color(1.0, 0.85, 0.0)  # yellow — fully completed (has glb_position)
		else:
			color = Color(0.2, 0.8, 1.0)   # cyan — incomplete (no glb_position yet)
		anchor_node.add_child(_make_marker(color, label))

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
