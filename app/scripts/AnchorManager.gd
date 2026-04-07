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
var _tracked_nodes: Dictionary = {} # ml2_uuid → Node3D

var _retry_uuids: Dictionary = {}   # ml2_uuid → retry_count
const RETRY_DELAY := 3.0

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
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr:
		xr.session_begun.connect(_on_session_begun)
		if xr.is_initialized():
			_on_session_begun()


func _on_session_begun() -> void:
	pass  # LocationManager drives loading; nothing to do here


# ── Public API ────────────────────────────────────────────────────────────────

func set_anchor_registry(all_anchors: Dictionary) -> void:
	_all_anchors = all_anchors

func set_next_num(n: int) -> void:
	_next_num = n

func load_anchor(uuid: String) -> void:
	if not _ml_mgr:
		return
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
	for uuid in _tracked_nodes:
		var node: Node3D = _tracked_nodes[uuid]
		if is_instance_valid(node) and node.global_position.distance_to(pos) <= radius:
			# Find by ml2_id
			for anchor in _all_anchors.values():
				if str(anchor.ml2_id) == uuid:
					return anchor
	return null


# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_anchor_tracked(anchor_node: Node3D, ml2_uuid: StringName, is_new: bool) -> void:
	var uuid_str := str(ml2_uuid)
	print("AnchorManager: tracked ", ml2_uuid, " (new=", is_new, ")")
	_tracked_nodes[uuid_str] = anchor_node
	_retry_uuids.erase(uuid_str)

	# if not is_localized:
	# 	var map_uuid := ""
	# 	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
	# 		map_uuid = Engine.get_singleton("OpenXRMlLocalizationMapExtension").get_localization_map_uuid()
	# 	is_localized = true
	# 	localized_space_uuid = map_uuid
	# 	print("AnchorManager: LOCALIZED — space UUID: ", map_uuid)
	# 	space_localized.emit(map_uuid)

	if is_new:
		var location_manager: LocationManager = get_parent().get_node_or_null("LocationManager")
		var new_anchor := Anchor.new()
		new_anchor.ml2_id = uuid_str
		new_anchor.name = str(_next_num)
		new_anchor.is_reference = true
		new_anchor.space_id = location_manager.get_current_space_id() if location_manager else ""
		_next_num += 1
		_all_anchors[uuid_str] = new_anchor
		SupabaseManager.insert_anchor(new_anchor)

	anchor_tracked.emit(anchor_node, ml2_uuid, is_new)


func _on_anchor_untracked(uuid: StringName) -> void:
	print("AnchorManager: untracked ", uuid)
	_tracked_nodes.erase(str(uuid))
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
