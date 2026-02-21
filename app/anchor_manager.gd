extends Node
class_name AnchorManager

# NOTE: remember that spatial anchors are attached to the SPACE and are indepenedent from the application
# this prevents us from just grabbing all anchors from the space, as they may be from other applications
# therefore we are capable to keep our own tracking

## Manages ML2 spatial anchors: create, load, persist, and visualise.
## Must be a child of XROrigin3D.

const SAVE_FILE := "user://spatial_anchors.json"

var _ml_mgr: Node  # OpenXRMlSpatialAnchorManager, created at runtime if available.
var _anchors_loaded := false

func _ready() -> void:
	if not ClassDB.class_exists("OpenXRMlSpatialAnchorManager"):
		push_warning("AnchorManager: OpenXRMlSpatialAnchorManager unavailable — spatial anchors disabled (editor / non-ML2 device).")
		return

	_ml_mgr = ClassDB.instantiate("OpenXRMlSpatialAnchorManager")

	_ml_mgr.connect("openxr_ml_spatial_anchor_tracked", _on_anchor_tracked)
	_ml_mgr.connect("openxr_ml_spatial_anchor_untracked", _on_anchor_untracked)
	_ml_mgr.connect("openxr_ml_spatial_anchor_create_failed", _on_create_failed)
	_ml_mgr.connect("openxr_ml_spatial_anchor_load_failed", _on_load_failed)

	# Wait until _ml_mgr is actually in the scene tree before touching XR session.
	_ml_mgr.tree_entered.connect(_on_mgr_entered_tree)
	get_parent().add_child.call_deferred(_ml_mgr)


func _on_mgr_entered_tree() -> void:
	# _ml_mgr is now in the tree under XROrigin3D — xr_origin is set.
	var xr := XRServer.find_interface("OpenXR") as OpenXRInterface
	if xr:
		xr.session_begun.connect(_load_anchors_from_db)
		if xr.is_initialized():
			_load_anchors_from_db()


func place_anchor(world_transform: Transform3D) -> void:
	"""
	Place a new anchor at this coordinate, and save it to ML2 storage and the saved anchor list.
	The co-ordinate is in Godot world space, but the addon will convert it to a headset-relative transform before sending to ML2.
	"""
	if not _ml_mgr:
		return
	print("AnchorManager: placing anchor at ", world_transform.origin)
	_ml_mgr.call("create_anchor", world_transform)


func remove_anchor(uuid: StringName) -> void:
	"""
	Deletes an anchor from both the ML2 storage and the saved anchor list.
	"""
	if not _ml_mgr:
		return
	_ml_mgr.call("untrack_anchor", uuid)
	SupabaseManager.remove_anchor(str(uuid))


# ── Persistence ───────────────────────────────────────────────────────────────

func _load_anchors_from_db() -> void:
	"""
	Reads the anchors form the database and tells ML2 to load them, which will eventually trigger the 'tracked' callback for each successfully loaded anchor.
	"""
	if _anchors_loaded:
		return
	_anchors_loaded = true

	var anchors_in_db: Array[Anchor] = await SupabaseManager.get_anchors()
	print("AnchorManager: loaded ", anchors_in_db.size(), " anchors from database.")

	for uuid: String in anchors_in_db.map(func(a): return a.id):
		print("AnchorManager: loading anchor ", uuid)
		_ml_mgr.call("load_anchor", StringName(uuid))

# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_anchor_tracked(anchor_node: Node3D, uuid: StringName, is_new: bool) -> void:
	"""
	Fires once per anchor per session, either when an existing anchor is loaded or when a new anchor is created.
	Runs after a node has been created for the anchor and added to the scene tree.
	Calling 'create_anchor' and 'load_anchor' will both eventually trigger this callback if successful.
	"""
	print("AnchorManager: tracked ", uuid, " (new=", is_new, ")")
	anchor_node.add_child(_make_marker())
	if is_new:
		var new_anchor := Anchor.new()
		new_anchor.id = uuid
		SupabaseManager.insert_anchor(new_anchor)


func _on_anchor_untracked(uuid: StringName) -> void:
	"""
	Fires after an anchor has been untracked (deleted)
	"""
	print("AnchorManager: untracked ", uuid)


func _on_create_failed(transform: Transform3D) -> void:
	"""
	Called when anchor creation fails.
	"""
	push_warning("AnchorManager: failed to create anchor at ", transform.origin)


func _on_load_failed(uuid: StringName) -> void:
	"""
	Called when anchor loading fails.
	"""
	push_warning("AnchorManager: failed to load anchor ", uuid)


# ── Marker ────────────────────────────────────────────────────────────────────

func _make_marker() -> Node3D:
	var root := Node3D.new()

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.10
	mi.mesh = sphere

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.8, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.8, 1.0)
	mat.emission_energy_multiplier = 2.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	root.add_child(mi)

	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 0.8, 1.0)
	light.light_energy = 0.5
	light.omni_range = 0.5
	root.add_child(light)

	return root
