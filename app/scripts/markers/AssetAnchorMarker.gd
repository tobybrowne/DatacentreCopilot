class_name AssetAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child

const COLOR          := Color(0.2, 0.5, 1.0)
const COLOR_INTERACT := Color(1.0, 1.0, 1.0)

const PROXIMITY_RADIUS := 0.50  # metres — palm must be within this distance
const DWELL_THRESHOLD  := 10.0  # seconds hand must dwell nearby to fire
const INTERACT_HOLD    := 1.5   # seconds to keep highlight after interaction

const _TRACKERS := {
	"left":  "/user/hand_tracker/left",
	"right": "/user/hand_tracker/right",
}

signal interacted

var _mat:        StandardMaterial3D
var _light:      OmniLight3D
var _lbl:        Label3D
var _asset_id:   String
var _asset_name: String
var _asset_type: String
var _logs:       LogsController3D = null

var _dwell_time := 0.0
var _hold_timer := 0.0
var _fired      := false


func get_asset_label() -> String:
	return _asset_name


func _ready() -> void:
	if anchor.id.is_empty():
		return
	var task = await Supabase.database.query(
		SupabaseQuery.new().from("assets").select().eq("anchor_id", anchor.id).range(0, 0)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		return

	var row: Dictionary = task.data[0]
	_asset_id = row.get("id", "")
	var name: String = row.get("name", "")
	var asset_type: String = row.get("asset_type", "")
	_asset_name = name
	_asset_type = asset_type
	add_to_group("asset_markers")
	interacted.connect(func(): ContextManager.on_asset_interacted(_asset_name, _asset_type))

	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.05
	sphere.height = 0.10
	mi.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLOR
	_mat.emission_enabled = true
	_mat.emission = COLOR
	_mat.emission_energy_multiplier = 2.0
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = _mat
	add_child(mi)

	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 0.5
	_light.omni_range = 0.5
	add_child(_light)

	_lbl = Label3D.new()
	_lbl.text = name if asset_type.is_empty() else "%s\n(%s)" % [name, asset_type]
	_lbl.position = Vector3(0, 0.10, 0)
	_lbl.font_size = 128
	_lbl.pixel_size = 0.0005
	_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_lbl.no_depth_test = true
	_lbl.modulate = COLOR
	add_child(_lbl)

	if not _asset_id.is_empty():
		var check = await Supabase.database.query(
			SupabaseQuery.new().from("log_assets").select(["log_id"]).eq("asset_id", _asset_id).range(0, 0)
		).completed
		if check.error == null and check.data != null and not check.data.is_empty():
			_logs = LogsController3D.new()
			_logs.world_anchored_fab = true
			_logs.fab_ray_enabled = false
			_logs.fab_local_pos = Vector3(0.20, 0, 0)
			_logs.tracked_node = self
			_logs.video_tmp_path = "user://asset_replay_%s.ogv" % _asset_id.left(8)
			_logs.refresh({"asset_id": _asset_id})
			get_parent().add_child(_logs)
			tree_exiting.connect(func(): if _logs: _logs.queue_free())


func _process(delta: float) -> void:
	if _mat == null:
		return

	var hand_nearby := _is_hand_nearby()

	if hand_nearby:
		_dwell_time += delta
		if not _fired and _dwell_time >= DWELL_THRESHOLD:
			_fired = true
			_hold_timer = INTERACT_HOLD
			if not _asset_id.is_empty():
				LogManager.record_asset_interaction(_asset_id)
			interacted.emit()
	else:
		_dwell_time = 0.0
		_fired = false

	if _hold_timer > 0.0:
		_hold_timer = maxf(0.0, _hold_timer - delta)

	_set_color(COLOR_INTERACT if _hold_timer > 0.0 else COLOR)


func _is_hand_nearby() -> bool:
	var xr_origin := get_parent() as XROrigin3D
	if not xr_origin:
		return false
	var xr_tf := xr_origin.global_transform

	for tracker_path: String in _TRACKERS.values():
		var tracker := XRServer.get_tracker(tracker_path)
		if not tracker or not tracker is XRHandTracker:
			continue
		var ht := tracker as XRHandTracker
		if not ht.has_tracking_data or not (ht.get_hand_joint_flags(0) & 4):
			continue
		var palm_world := (xr_tf * ht.get_hand_joint_transform(0)).origin
		if global_position.distance_to(palm_world) < PROXIMITY_RADIUS:
			return true
	return false


func _set_color(c: Color) -> void:
	_mat.albedo_color = c
	_mat.emission = c
	_light.light_color = c
	_lbl.modulate = c
