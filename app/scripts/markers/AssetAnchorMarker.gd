class_name AssetAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child

const COLOR          := Color(0.2, 0.5, 1.0)
const COLOR_INTERACT := Color(1.0, 1.0, 1.0)

const PROXIMITY_RADIUS := 0.50
const DWELL_THRESHOLD  := 10.0
const INTERACT_HOLD    := 1.5

const GAZE_RADIUS         := 1.5   # metres — must be within this to show fab
const GAZE_DOT_THRESHOLD  := 0.97  # cos(~14°)
const GAZE_HIDE_DELAY     := 0.4   # seconds before fab hides after losing gaze

const _TRACKERS := {
	"left":  "/user/hand_tracker/left",
	"right": "/user/hand_tracker/right",
}

const _FAB_SCENE  := preload("res://ui/standalone/asset_fab/asset_fab_3d.tscn")
const _INFO_SCENE := preload("res://ui/standalone/asset_info/asset_info_panel_3d.tscn")

signal interacted

var _mat:       StandardMaterial3D
var _light:     OmniLight3D
var _asset_id:  String
var _asset_name: String
var _asset_type: String
var _logs:      LogPlayerController = null

var _fab_3d:  ViewportPanel3D = null
var _info_3d: ViewportPanel3D = null
var _beam:    MeshInstance3D  = null

var _info_open      := false
var _gaze_hide_timer := 0.0

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
	_asset_id   = row.get("id", "")
	_asset_name = row.get("name", "")
	_asset_type = row.get("asset_type", "")

	add_to_group("asset_markers")
	interacted.connect(func(): ContextManager.on_asset_interacted(_asset_name, _asset_type))

	_build_orb()
	_build_fab()

	if not _asset_id.is_empty():
		var check = await Supabase.database.query(
			SupabaseQuery.new().from("log_assets").select(["log_id"]).eq("asset_id", _asset_id).range(0, 0)
		).completed
		if check.error == null and check.data != null and not check.data.is_empty():
			_logs = LogPlayerController.new()
			_logs.show_fab = false
			_logs.video_tmp_path = "user://asset_replay_%s.ogv" % _asset_id.left(8)
			_logs.refresh({"asset_id": _asset_id})
			_get_xr_origin().add_child(_logs)
			tree_exiting.connect(func(): if _logs: _logs.queue_free())


func _process(delta: float) -> void:
	if _mat == null:
		return

	# Dwell interaction
	var hand_nearby := _is_hand_nearby()
	if hand_nearby:
		_dwell_time += delta
		if not _fired and _dwell_time >= DWELL_THRESHOLD:
			_fired = true
			_hold_timer = INTERACT_HOLD
			if not _asset_id.is_empty():
				LogRecordManager.record_asset_interaction(_asset_id)
			interacted.emit()
	else:
		_dwell_time = 0.0
		_fired = false

	if _hold_timer > 0.0:
		_hold_timer = maxf(0.0, _hold_timer - delta)
	_set_color(COLOR_INTERACT if _hold_timer > 0.0 else COLOR)

	# Gaze → fab visibility (only when info panel not open)
	if _fab_3d and not _info_open:
		_fab_3d.global_position = global_position
		if _is_gazed_at():
			_gaze_hide_timer = GAZE_HIDE_DELAY
			if not _fab_3d.visible:
				_fab_3d.visible = true
		else:
			_gaze_hide_timer -= delta
			if _gaze_hide_timer <= 0.0 and _fab_3d.visible:
				_fab_3d.visible = false

	# Beam
	if _info_open and _beam and _info_3d:
		_update_beam()


func _build_orb() -> void:
	var mi := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.015
	sphere.height = 0.030
	mi.mesh = sphere
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = COLOR
	_mat.emission_enabled = true
	_mat.emission = COLOR
	_mat.emission_energy_multiplier = 2.5
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = _mat
	add_child(mi)

	_light = OmniLight3D.new()
	_light.light_color = COLOR
	_light.light_energy = 0.3
	_light.omni_range = 0.3
	add_child(_light)


func _build_fab() -> void:
	var xr_origin := _get_xr_origin()
	if not xr_origin:
		return
	_fab_3d = _FAB_SCENE.instantiate()
	_fab_3d.position = xr_origin.to_local(global_position)
	_fab_3d.visible = false
	xr_origin.add_child(_fab_3d)
	var fab := _fab_3d.get_panel() as AssetFab
	if fab:
		fab.info_requested.connect(_open_info)
		fab.setup(_asset_type)
	tree_exiting.connect(func(): if _fab_3d: _fab_3d.queue_free())


func _open_info() -> void:
	if _info_open:
		return
	_info_open = true
	_fab_3d.visible = false

	const MIN_DIST := 0.8

	var xr_origin := _get_xr_origin()
	var camera    := _get_camera()
	_info_3d      = _INFO_SCENE.instantiate()

	if camera:
		var cam_pos  := camera.global_position
		var to_asset := global_position - cam_pos
		to_asset.y   = 0.0
		var horiz    := to_asset.length()
		var dir: Vector3
		if horiz > 0.05:
			dir = to_asset / horiz
		else:
			dir = -camera.global_transform.basis.z
			dir.y = 0.0
			dir = dir.normalized() if dir.length_squared() > 0.001 else Vector3.FORWARD
		var spawn_world   := cam_pos + dir * maxf(MIN_DIST, horiz)
		_info_3d.position = xr_origin.to_local(spawn_world)
	else:
		_info_3d.position = xr_origin.to_local(global_position + Vector3(0.25, 0.05, 0))

	xr_origin.add_child(_info_3d)

	var panel := _info_3d.get_panel() as AssetInfoPanel
	if panel:
		panel.init({"asset_name": _asset_name, "asset_type": _asset_type, "has_logs": _logs != null})
		panel.close_requested.connect(_close_info)
		if _logs:
			panel.logs_requested.connect(_logs.open_browser)

	_beam = _create_beam()
	xr_origin.add_child(_beam)
	_update_beam()


func _close_info() -> void:
	_info_open = false
	if _logs:
		_logs.close()
	if _info_3d:
		_info_3d.queue_free()
		_info_3d = null
	if _beam:
		_beam.queue_free()
		_beam = null


func _create_beam() -> MeshInstance3D:
	var box := BoxMesh.new()
	box.size = Vector3(0.001, 0.001, 1.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.15, 0.15, 0.22, 0.95)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var mi := MeshInstance3D.new()
	mi.mesh = box
	mi.material_override = mat
	return mi


func _panel_edge_point() -> Vector3:
	var center := _info_3d.global_position
	var hw     := _info_3d.quad_size.x * 0.5
	var hh     := _info_3d.quad_size.y * 0.5
	var right  := _info_3d.global_transform.basis.x
	var up     := _info_3d.global_transform.basis.y
	var to_orb := global_position - center
	var px     := to_orb.dot(right)
	var py     := to_orb.dot(up)
	if absf(px) < 0.0001 and absf(py) < 0.0001:
		return center
	var t := INF
	if absf(px) > 0.0001: t = minf(t, hw / absf(px))
	if absf(py) > 0.0001: t = minf(t, hh / absf(py))
	return center + right * (px * t) + up * (py * t)


func _update_beam() -> void:
	var start := global_position
	var end   := _panel_edge_point()
	var dir   := end - start
	var dist  := dir.length()
	if dist < 0.001:
		return
	_beam.global_position = (start + end) * 0.5
	var up_ref := Vector3.RIGHT if absf(dir.normalized().dot(Vector3.UP)) > 0.99 else Vector3.UP
	_beam.look_at(end, up_ref)
	_beam.scale = Vector3(1.0, 1.0, dist)


func _is_gazed_at() -> bool:
	var camera := _get_camera()
	if not camera:
		return false
	var to_orb := global_position - camera.global_position
	var dist   := to_orb.length()
	if dist > GAZE_RADIUS:
		return false
	return to_orb.normalized().dot(-camera.global_transform.basis.z) > GAZE_DOT_THRESHOLD


func _is_hand_nearby() -> bool:
	var xr_origin := _get_xr_origin()
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


func _get_xr_origin() -> Node3D:
	var node := get_parent()
	while node:
		if node is XROrigin3D:
			return node
		node = node.get_parent()
	return null


func _get_camera() -> Camera3D:
	var xr_origin := _get_xr_origin()
	if xr_origin:
		var cam := xr_origin.get_node_or_null("XRCamera3D") as Camera3D
		if cam:
			return cam
	return get_viewport().get_camera_3d()
