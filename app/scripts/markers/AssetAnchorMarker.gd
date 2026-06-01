class_name AssetAnchorMarker
extends Node3D

var anchor: Anchor  # set before add_child

const COLOR          := Color(0.2, 0.5, 1.0)
const COLOR_INTERACT := Color(1.0, 1.0, 1.0)

const PROXIMITY_RADIUS := 0.50
const DWELL_THRESHOLD  := 10.0
const INTERACT_HOLD    := 1.5

const WORLD_MESH_LAYER := 1 << 19

const GAZE_RADIUS         := 1.5   # metres - must be within this to show fab
const GAZE_DOT_THRESHOLD  := 0.97  # cos(~14°)
const GAZE_HIDE_DELAY     := 0.4   # seconds before fab hides after losing gaze

const _TRACKERS := {
	"left":  "/user/hand_tracker/left",
	"right": "/user/hand_tracker/right",
}

const _INFO_SCENE := preload("res://ui/standalone/asset_info/asset_info_panel_3d.tscn")

const FAB_SIZE   := 0.10
const FAB_RADIUS := 0.055

static var _s_disc_shader: Shader = null
static var _s_ring_shader: Shader = null

signal interacted

var _asset: Asset = null
var _manuals: Array[Dictionary] = []
var _logs:      LogPlayerController = null


var _fab_3d:       Node3D         = null
var _fab_disc_mat: ShaderMaterial = null
var _fab_ring:     MeshInstance3D = null
var _fab_pressed   := {"left": false, "right": false}
var _info_3d: ViewportPanel3D = null
var _beam:    MeshInstance3D  = null

var _info_open       := false
var _gaze_hide_timer := 0.0
var _cached_live_data = null

var _dwell_time := 0.0
var _hold_timer := 0.0
var _fired      := false


func get_asset_label() -> String:
	return _asset.name if _asset else ""


func _ready() -> void:
	if anchor.id.is_empty():
		return
	var bsm := BuildingSessionManager.instance
	if not bsm:
		return
	var row := bsm.get_asset_row(anchor.id)
	if row.is_empty():
		return

	_asset = Asset.from_dict(row)
	add_to_group("asset_markers")
	interacted.connect(func(): ContextManager.set_interacted(_asset))
	_build_fab()

	if not _asset.id.is_empty():
		if bsm.asset_has_logs(_asset.id):
			_logs = LogPlayerController.new()
			_logs.show_fab = false
			_logs.video_tmp_path = "user://asset_replay_%s.ogv" % _asset.id.left(8)
			_logs.refresh({"asset_id": _asset.id})
			_get_xr_origin().add_child(_logs)
			tree_exiting.connect(func(): if _logs: _logs.queue_free())
		var ld := bsm.get_live_data(_asset.id)
		if not ld.is_empty():
			on_live_data(ld)
		LiveDataManager.register(_asset.id, self)
		tree_exiting.connect(func(): LiveDataManager.deregister(_asset.id))




func _process(delta: float) -> void:
	if _asset == null:
		return

	# Dwell interaction
	var hand_nearby := _is_hand_nearby()
	if hand_nearby:
		_dwell_time += delta
		if not _fired and _dwell_time >= DWELL_THRESHOLD:
			_fired = true
			_hold_timer = INTERACT_HOLD
			if not _asset.id.is_empty():
				LogRecordManager.record_asset_interaction(_asset.id)
			interacted.emit()
	else:
		_dwell_time = 0.0
		_fired = false

	if _hold_timer > 0.0:
		_hold_timer = maxf(0.0, _hold_timer - delta)

	# Gaze tracking for ContextManager (fab is always visible)
	if _fab_3d and not _info_open:
		_fab_3d.global_position = global_position
		var _cam := _get_camera()
		if _cam and _fab_3d.global_position.distance_squared_to(_cam.global_position) > 0.001:
			_fab_3d.look_at(_cam.global_position, Vector3.UP)
			_fab_3d.rotate_object_local(Vector3.UP, PI)
		if _is_gazed_at():
			_gaze_hide_timer = GAZE_HIDE_DELAY
			ContextManager.set_looking_at(_asset)
		else:
			_gaze_hide_timer -= delta
			if _gaze_hide_timer <= 0.0 and ContextManager.ctx_looking_at == _asset:
				ContextManager.set_looking_at(null)

		var gm := _get_gesture_manager()
		if gm:
			for hand in ["left", "right"]:
				var ray_origin: Vector3 = gm.ray_origins[hand]
				var ray_dir: Vector3 = gm.ray_directions[hand]
				if not gm.ray_active[hand]:
					_fab_pressed[hand] = false
					continue
				var to_fab: Vector3 = _fab_3d.global_position - ray_origin
				var t: float = to_fab.dot(ray_dir)
				var closest: Vector3 = ray_origin + ray_dir * t
				var perp_dist: float = closest.distance_to(_fab_3d.global_position)
				if t > 0.0 and perp_dist < FAB_RADIUS:
					# Actual front-surface intersection point, offset slightly toward camera so reticle renders in front
					var hit_depth: float = sqrt(max(0.0, FAB_RADIUS * FAB_RADIUS - perp_dist * perp_dist))
					var hit_point: Vector3 = ray_origin + ray_dir * (t - hit_depth) - ray_dir * 0.002
					gm.set_hit_point(hand, hit_point)
					gm.claim_ui(hand)
					if _fab_disc_mat:
						_fab_disc_mat.set_shader_parameter("color",
							Color(0.30, 0.30, 0.42, 0.95) if gm.is_ray_pinching(hand) else Color(0.26, 0.26, 0.36, 0.95))
					if gm.is_ray_pinching(hand) and not _fab_pressed[hand]:
						_fab_pressed[hand] = true
					elif not gm.is_ray_pinching(hand) and _fab_pressed[hand]:
						_fab_pressed[hand] = false
						if _fab_disc_mat:
							_fab_disc_mat.set_shader_parameter("color", Color(0.22, 0.22, 0.30, 0.95))
						_open_info()
				else:
					if _fab_disc_mat and _fab_pressed[hand]:
						_fab_disc_mat.set_shader_parameter("color", Color(0.22, 0.22, 0.30, 0.95))
					_fab_pressed[hand] = false

	# Beam
	if _info_open and _beam and _info_3d:
		_update_beam()


func _build_fab() -> void:
	var xr_origin := _get_xr_origin()
	if not xr_origin:
		return

	_fab_3d = Node3D.new()
	xr_origin.add_child(_fab_3d)
	tree_exiting.connect(func(): if _fab_3d: _fab_3d.queue_free())

	if not _s_disc_shader:
		_s_disc_shader = Shader.new()
		_s_disc_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 color : source_color = vec4(0.22, 0.22, 0.30, 0.95);
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	if (length(uv) > 1.0) discard;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""
	_fab_disc_mat = ShaderMaterial.new()
	_fab_disc_mat.shader = _s_disc_shader
	var quad := QuadMesh.new()
	quad.size = Vector2(FAB_SIZE, FAB_SIZE)
	var disc_mi := MeshInstance3D.new()
	disc_mi.mesh = quad
	disc_mi.material_override = _fab_disc_mat
	_fab_3d.add_child(disc_mi)

	var icon_path := AssetTypes.icon_path(_asset.asset_type if _asset else "")
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var icon := Sprite3D.new()
		icon.texture = load(icon_path)
		icon.pixel_size = 0.00028
		icon.render_priority = 1
		_fab_3d.add_child(icon)

	if not _s_ring_shader:
		_s_ring_shader = Shader.new()
		_s_ring_shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
void fragment() {
	vec2 uv = UV * 2.0 - 1.0;
	float d = length(uv);
	float ring = smoothstep(0.82, 0.86, d) * smoothstep(1.02, 0.98, d);
	if (ring < 0.01) discard;
	float pulse = 0.5 + 0.5 * sin(TIME * 7.54);
	ALBEDO = vec3(1.0, 0.15, 0.15);
	ALPHA = ring * pulse;
}
"""
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = _s_ring_shader
	var ring_quad := QuadMesh.new()
	ring_quad.size = Vector2(FAB_SIZE * 1.15, FAB_SIZE * 1.15)
	_fab_ring = MeshInstance3D.new()
	_fab_ring.mesh = ring_quad
	_fab_ring.material_override = ring_mat
	_fab_ring.visible = false
	_fab_3d.add_child(_fab_ring)


func _open_info() -> void:
	if _info_open:
		return
	_info_open = true
	if _fab_3d:
		_fab_3d.visible = false

	# Resolve manual lazily from session cache (already loaded by BuildingSessionManager)
	if _manuals.is_empty() and _asset:
		var bsm := BuildingSessionManager.instance
		var row := bsm.get_asset_row(anchor.id) if bsm else {}
		var model = row.get("asset_models", null)
		if model is Dictionary:
			var manual_id: String = model.get("manual_id", "")
			if not manual_id.is_empty():
				var manual := bsm.get_manual(manual_id)
				var url: String = manual.get("url", "")
				if not url.is_empty():
					_manuals = [{"title": manual.get("title", "Manual"), "url": url}]

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
		panel.init({
			"asset_name":   _asset.name if _asset else "",
			"asset_type":   _asset.asset_type if _asset else "",
			"manufacturer": _asset.manufacturer if _asset else "",
			"model_name":   _asset.model_name if _asset else "",
			"manuals":      _manuals,
			"has_logs":     _logs != null,
			"live_data":    _cached_live_data,
		})
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
	if _fab_3d:
		_fab_3d.visible = true


func on_live_data(record: Dictionary) -> void:
	var alarm: bool = record.get("alarm", false)
	if _fab_ring:
		_fab_ring.visible = alarm

	var raw = record.get("data", {})
	var data: Dictionary = raw if raw is Dictionary else {}
	if AssetTypes.is_power_type(_asset.asset_type):
		_cached_live_data = PowerAssetLiveData.from_dict(data)
	elif AssetTypes.is_cooling_type(_asset.asset_type):
		_cached_live_data = CoolingAssetLiveData.from_dict(data)

	if _info_open and _info_3d:
		var panel := _info_3d.get_panel() as AssetInfoPanel
		if panel and _cached_live_data:
			panel.update_live_data(_cached_live_data)


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


func _get_gesture_manager() -> GestureManager:
	var xr_origin := _get_xr_origin()
	if xr_origin:
		return xr_origin.get_node_or_null("GestureManager") as GestureManager
	return null
