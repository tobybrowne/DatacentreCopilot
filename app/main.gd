extends Node3D

enum AppMode { NONE, ANCHOR_EDITING, NAVIGATING, PROCEDURE }
var _app_mode := AppMode.NONE

var xr_interface: XRInterface

@onready var ui_panel: ViewportPanel3D = $XROrigin3D/UIPanel
@onready var space_label = $XROrigin3D/SpaceLabel
@onready var gesture_manager: GestureManager = $XROrigin3D/GestureManager
@onready var anchor_manager: AnchorManager = $XROrigin3D/AnchorManager
@onready var location_manager: LocationManager = $XROrigin3D/LocationManager
@onready var space_manager: SpaceManager = $XROrigin3D/SpaceManager
@onready var voice_manager: VoiceManager = $XROrigin3D/VoiceManager
@onready var world_mesh_manager: WorldMeshManager = $XROrigin3D/WorldMeshManager
@onready var route_manager: RouteManager = $XROrigin3D/RouteManager

const ANCHOR_DELETE_RADIUS := 0.10   # metres — how close to an anchor to target it for delete

# Tracking indicator
var _tracking_dot: MeshInstance3D
var _tracking_dot_mat: StandardMaterial3D

# Space name label
var _space_label: Label3D
var _current_space_name := ""
const LOOK_UP_THRESHOLD := 0.4  # radians (~23 degrees up)

# -- ML2 localization extension (commented out — events unreliable, using OpenXR core state instead)
# var _loc_ext = null  # OpenXRMlLocalizationMapExtension singleton, null if unavailable
# const LOC_CONFIDENCE_FAIR      := 1
# const LOC_CONFIDENCE_GOOD      := 2
# const LOC_CONFIDENCE_EXCELLENT := 3


# UUID poll timer
var _uuid_timer := 0.0
var _space_label_timer := 0.0
const SPACE_LABEL_INTERVAL := 3.0

# Anchor pinch state
var _spaces_synced := false

var _anchor_mode   := ""   # "create" | "delete"
var _anchor_target: Anchor = null
var _pending_procedure: Procedure = null
var _procedure_nav_pending := false  # true while waiting for nav signals to resolve a procedure start

# Progress ring — two separate mesh nodes so each has a plain, reliable material
const RING_R_IN    := 0.04
const RING_R_OUT   := 0.08
const RING_SEGS    := 48
const RING_START   := -PI / 2.0  # arc starts at top, fills clockwise

var _progress_root:     Node3D              = null
var _progress_arc_mesh: ImmediateMesh       = null
var _progress_bg_mat:   StandardMaterial3D  = null
var _progress_arc_mat:  StandardMaterial3D  = null


func _ready():
	PanelRouter.push("start_menu")
	PanelRouter.action_requested.connect(_on_panel_action)
	location_manager.space_picker_needed.connect(func(spaces: Array[Space]):
		var mode := "procedure" if _procedure_nav_pending else "navigate"
		PanelRouter.push("space_picker", { "spaces": spaces, "mode": mode }))
	location_manager.navigation_ready.connect(func(space_id: String):
		if _procedure_nav_pending:
			_procedure_nav_pending = false
			_enter_procedure_mode_for_id(space_id)
		else:
			_enter_nav_mode_for_id(space_id))
	ui_panel.visible = true
	gesture_manager.pinch_started.connect(_on_pinch_started)
	gesture_manager.pinch_held.connect(_on_pinch_held)
	gesture_manager.pinch_completed.connect(_on_pinch_completed)
	gesture_manager.pinch_ended.connect(_on_pinch_ended)
	gesture_manager.home_gesture_held.connect(_on_home_gesture_held)
	gesture_manager.home_gesture_completed.connect(_on_home_gesture_completed)
	gesture_manager.home_gesture_ended.connect(func(_hand: String): _clear_progress_indicator())
	voice_manager.next_step.connect(func():
		var sv := ui_panel.get_panel() as StepViewer
		if sv: sv.next_step())
	voice_manager.previous_step.connect(func():
		var sv := ui_panel.get_panel() as StepViewer
		if sv: sv.prev_step())
	voice_manager.confirm.connect(func(): pass)
	voice_manager.cancel.connect(func(): pass)
	voice_manager.go_home.connect(func(): _set_mode(AppMode.NONE); PanelRouter.pop_to_root())
	voice_manager.start_recording.connect(_on_start_recording)
	voice_manager.stop_recording.connect(_on_stop_recording)

	if OS.get_name() == "Android":
		OS.request_permissions()

	xr_interface = XRServer.find_interface("OpenXR")
	_create_tracking_indicator()
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
		if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
			var ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension")
			ext.localization_changed.connect(_on_localization_changed.bind(ext))

		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().transparent_bg = true
		get_viewport().use_xr = true

		var hand_mat = StandardMaterial3D.new()
		hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hand_mat.albedo_color = Color(0.0, 0.133, 0.357, 0.333)
		for mesh_path in [
			"XROrigin3D/LeftHand/LeftHandHumanoid/LeftHandHumanoid/Skeleton3D/LeftHandHumanoidMesh",
			"XROrigin3D/RightHand/RightHandHumanoid/RightHandHumanoid/Skeleton3D/RightHandHumanoidMesh"
		]:
			var mesh = get_node_or_null(mesh_path)
			if mesh:
				mesh.material_override = hand_mat
	else:
		print("OpenXR not initialized, please check if your headset is connected")


func _process(delta: float) -> void:
	# _update_tracking_indicator(delta)
	# _poll_localization_uuid(delta)
	# _poll_space_label(delta)
	pass

func _poll_space_label(delta: float) -> void:
	_space_label_timer += delta
	if _space_label_timer < SPACE_LABEL_INTERVAL:
		return
	_space_label_timer = 0.0
	var ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension") if Engine.has_singleton("OpenXRMlLocalizationMapExtension") else null
	print("Current UUID: ", ext.get_localization_map_uuid() if ext else "(no ext)")
	var current_space: Space = await space_manager.get_current_space()
	print("Space label value: ", current_space.name if current_space else "(none)")


func _on_localization_changed(_state: int, _confidence: int, _error_flags: int, _ext: Object) -> void:
	print("Localisation Changed")
	# var current_space: Space = await space_manager.get_current_space()
	# print("Space label value: ", current_space.name if current_space else "(none)")

	# if _spaces_synced:
	# 	return
	# _spaces_synced = true

	# var local_spaces: Array[Space] = space_manager.get_all_local_spaces()
	# var db_spaces: Array[Space] = await SupabaseManager.get_spaces()
	# var db_ids := db_spaces.map(func(s): return s.id)

	# for space in local_spaces:
	# 	if space.id in db_ids:
	# 		print("Space already in DB: ", space.name, " (", space.id, ")")
	# 	else:
	# 		print("Exporting new space: ", space.id)
	# 		var exported: Space = await space_manager.export_space(space)
	# 		if exported:
	# 			print("Exported space: ", exported.id)
	# 		else:
	# 			print("Failed to export space: ", space.id)


func _poll_localization_uuid(delta: float) -> void:
	_uuid_timer += delta
	if _uuid_timer < 1.0:
		return
	_uuid_timer = 0.0
	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		var ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension")
		print("localization map UUID: ", ext.get_localization_map_uuid())


# ── Tracking indicator ─────────────────────────────────────────────────────────

func _create_tracking_indicator() -> void:
	pass

func _update_tracking_indicator(_delta: float) -> void:
	pass

# -- ML2 localization extension indicator (commented out — use when events are reliable)
# func _update_tracking_indicator(_delta: float) -> void:
# 	if not _tracking_dot_mat:
# 		return
# 	if not _loc_ext:
# 		if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
# 			_loc_ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension")
# 			_loc_ext.localization_changed.connect(func(state, confidence, _err):
# 				print("localization_changed: state=", state, " confidence=", confidence))
# 	var confidence: int = _loc_ext.get_localization_confidence() if _loc_ext else -1
# 	var color: Color
# 	if not _loc_ext:
# 		color = Color(0.5, 0.5, 0.5)  # grey — extension unavailable
# 	elif confidence >= LOC_CONFIDENCE_GOOD:
# 		color = Color(0.0, 1.0, 0.2)
# 	elif confidence == LOC_CONFIDENCE_FAIR:
# 		color = Color(1.0, 0.55, 0.0)
# 	else:
# 		color = Color(1.0, 0.2, 0.2)
# 	_tracking_dot_mat.albedo_color = color


# ── Gesture signals ────────────────────────────────────────────────────────────

func _on_pinch_started(hand: String, position: Vector3) -> void:
	var step_viewer := ui_panel.get_panel() as StepViewer
	if step_viewer:
		if hand == "left":
			step_viewer.prev_step()
		elif hand == "right":
			step_viewer.next_step()

	if hand == "right" and _app_mode == AppMode.ANCHOR_EDITING:
		var near: Anchor = anchor_manager.get_anchor_near(position, ANCHOR_DELETE_RADIUS)
		_anchor_mode   = "delete" if near != null else "create"
		_anchor_target = near


func _on_pinch_held(hand: String, position: Vector3, duration: float) -> void:
	if hand == "right" and _app_mode == AppMode.ANCHOR_EDITING:
		_update_progress_indicator(position, minf(duration / gesture_manager.hold_time, 1.0))


func _on_pinch_completed(hand: String, position: Vector3) -> void:
	if hand == "right" and _app_mode == AppMode.ANCHOR_EDITING:
		_clear_progress_indicator()
		if _anchor_mode == "create":
			anchor_manager.place_anchor(Transform3D(Basis.IDENTITY, position))
		else:
			anchor_manager.remove_anchor(_anchor_target)
		_anchor_mode   = ""
		_anchor_target = null


func _on_pinch_ended(hand: String) -> void:
	if hand == "right" and _app_mode == AppMode.ANCHOR_EDITING:
		_clear_progress_indicator()
		_anchor_mode   = ""
		_anchor_target = null


func _on_home_gesture_held(_hand: String, position: Vector3, duration: float) -> void:
	_update_progress_indicator(position, minf(duration / gesture_manager.hold_time, 1.0))


func _on_home_gesture_completed(_hand: String) -> void:
	_clear_progress_indicator()
	_set_mode(AppMode.NONE)
	PanelRouter.pop_to_root()


# ── Progress ring ──────────────────────────────────────────────────────────────

func _update_progress_indicator(pos: Vector3, progress: float) -> void:
	if not _progress_root:
		_create_progress_indicator()

	_progress_root.global_position = pos

	# Manually face the camera — billboard material mode is unreliable in XR.
	var cam := get_viewport().get_camera_3d()
	if cam and cam.global_position.distance_to(pos) > 0.01:
		_progress_root.look_at(cam.global_position, Vector3.UP)

	# Swap colours when in delete mode.
	var color := Color(0.2, 0.8, 1.0) if _anchor_mode == "create" else Color(1.0, 0.3, 0.2)
	_progress_bg_mat.albedo_color  = Color(color.r, color.g, color.b, 0.2)
	_progress_arc_mat.albedo_color = color

	# Rebuild only the arc portion each frame.
	_progress_arc_mesh.clear_surfaces()
	if progress > 0.0:
		var n_draw: int = max(1, int(RING_SEGS * progress))
		_progress_arc_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for i in n_draw:
			_ring_quad(_progress_arc_mesh, i)
		_progress_arc_mesh.surface_end()


func _create_progress_indicator() -> void:
	_progress_root = Node3D.new()
	add_child(_progress_root)

	# Background — full dim ring, built once.
	var bg_mi   := MeshInstance3D.new()
	var bg_mesh := ImmediateMesh.new()
	_progress_bg_mat = _make_ring_mat(Color(0.2, 0.8, 1.0, 0.2))
	bg_mi.material_override = _progress_bg_mat
	bg_mi.mesh = bg_mesh
	bg_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in RING_SEGS:
		_ring_quad(bg_mesh, i)
	bg_mesh.surface_end()
	_progress_root.add_child(bg_mi)

	# Arc — empty mesh that gets rebuilt every frame.
	var arc_mi := MeshInstance3D.new()
	_progress_arc_mesh = ImmediateMesh.new()
	_progress_arc_mat  = _make_ring_mat(Color(0.2, 0.8, 1.0, 1.0))
	arc_mi.material_override = _progress_arc_mat
	arc_mi.mesh = _progress_arc_mesh
	_progress_root.add_child(arc_mi)


func _make_ring_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color  = color
	mat.cull_mode     = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	return mat


func _ring_quad(mesh: ImmediateMesh, i: int) -> void:
	# One annular quad (two triangles) at segment i of RING_SEGS.
	var a0 := RING_START - float(i)     / RING_SEGS * TAU
	var a1 := RING_START - float(i + 1) / RING_SEGS * TAU
	mesh.surface_add_vertex(Vector3(cos(a0) * RING_R_OUT, sin(a0) * RING_R_OUT, 0))
	mesh.surface_add_vertex(Vector3(cos(a0) * RING_R_IN,  sin(a0) * RING_R_IN,  0))
	mesh.surface_add_vertex(Vector3(cos(a1) * RING_R_OUT, sin(a1) * RING_R_OUT, 0))
	mesh.surface_add_vertex(Vector3(cos(a0) * RING_R_IN,  sin(a0) * RING_R_IN,  0))
	mesh.surface_add_vertex(Vector3(cos(a1) * RING_R_IN,  sin(a1) * RING_R_IN,  0))
	mesh.surface_add_vertex(Vector3(cos(a1) * RING_R_OUT, sin(a1) * RING_R_OUT, 0))


func _clear_progress_indicator() -> void:
	if _progress_root:
		_progress_root.queue_free()
		_progress_root    = null
		_progress_arc_mesh = null
		_progress_bg_mat   = null
		_progress_arc_mat  = null


# ── Gesture recording ─────────────────────────────────────────────────────────

var _gesture_replayer: GestureReplayer = null

func _on_start_recording() -> void:
	# Remove any existing replayer.
	if _gesture_replayer:
		_gesture_replayer.queue_free()
		_gesture_replayer = null
	gesture_manager.start_recording()
	print("Gesture recording started")

func _on_stop_recording() -> void:
	if not gesture_manager.is_recording():
		return
	var frames := gesture_manager.stop_recording()
	print("Gesture recording stopped: ", frames.size(), " frames")
	if frames.is_empty():
		return

	# Spawn replayer 1m in front of the camera.
	var camera := $XROrigin3D/XRCamera3D as Camera3D
	_gesture_replayer = GestureReplayer.new()
	add_child(_gesture_replayer)
	_gesture_replayer.global_transform = Transform3D(Basis.IDENTITY, camera.global_position + -camera.global_basis.z)
	_gesture_replayer.play(frames, true)


# ── Panel actions ─────────────────────────────────────────────────────────────

func _on_panel_action(action: String, data: Dictionary) -> void:
	match action:
		"localise_space":
			_localise_space(data.get("space") as Space)
		"localise_space_load_anchors":
			_enter_anchor_editing(data.get("space") as Space)
		"start_nav_for_space":
			_enter_nav_mode(data.get("space") as Space)
		"navigate":
			location_manager.request_navigation(data.get("building_id", ""))
		"update_space":
			pass  # TODO
		"start_procedure":
			_start_procedure(data.get("procedure") as Procedure)
		"start_nav_for_procedure":
			_enter_procedure_mode(data.get("space") as Space)
		"goto_step":
			_on_goto_step(data.get("anchor_id", ""))
		"goto_cleared":
			route_manager.clear_goto_route()


func _ensure_space_local(space: Space) -> bool:
	var local_ids := space_manager.get_all_local_spaces().map(func(s: Space): return s.id)
	if space.id in local_ids:
		return true
	print("main: space not local — importing")
	var ok := await space_manager.import_space(space)
	if not ok:
		push_warning("main: import failed for space ", space.id)
	return ok


func _localise_space(space: Space) -> void:
	if not space:
		return
	if not await _ensure_space_local(space):
		return
	await location_manager.localize_to_space(space.id)


func _set_mode(new_mode: AppMode) -> void:
	if _app_mode == new_mode:
		return
	_anchor_mode = ""
	_anchor_target = null
	_clear_progress_indicator()
	location_manager.clear_markers()
	anchor_manager.clear_markers()
	route_manager.clear_goto_route()
	_app_mode = new_mode
	ui_panel.visible = new_mode == AppMode.NONE or new_mode == AppMode.PROCEDURE
	print("main: mode → ", AppMode.keys()[new_mode])


func _enter_nav_mode(space: Space) -> void:
	if not space:
		return
	print("main: entering nav mode for '", space.name, "' (", space.id, ")")
	if not await _ensure_space_local(space):
		return
	_set_mode(AppMode.NAVIGATING)
	location_manager.calibrate_to_space(space.id)


func _enter_nav_mode_for_id(space_id: String) -> void:
	print("main: entering nav mode for space ", space_id, " (coarse detected)")
	_set_mode(AppMode.NAVIGATING)
	location_manager.calibrate_to_space(space_id)


func _enter_procedure_mode(space: Space) -> void:
	if not space:
		return
	_procedure_nav_pending = false
	print("main: entering procedure mode for '", space.name, "' (", space.id, ")")
	if not await _ensure_space_local(space):
		return
	_set_mode(AppMode.PROCEDURE)
	print("PROCEDURE: CALIBRATING TO SPACE: ", space.id)
	location_manager.calibrate_to_space(space.id)
	if _pending_procedure:
		PanelRouter.push("step_viewer", { "procedure": _pending_procedure })
		_pending_procedure = null


func _enter_procedure_mode_for_id(space_id: String) -> void:
	print("main: entering procedure mode for space ", space_id, " (coarse detected)")
	_set_mode(AppMode.PROCEDURE)
	location_manager.calibrate_to_space(space_id)
	if _pending_procedure:
		PanelRouter.push("step_viewer", { "procedure": _pending_procedure })
		_pending_procedure = null


func _start_procedure(procedure: Procedure) -> void:
	if not procedure:
		return
	if location_manager._calibrated:
		_set_mode(AppMode.PROCEDURE)
		PanelRouter.push("step_viewer", { "procedure": procedure })
		return
	_pending_procedure = procedure
	_procedure_nav_pending = true
	location_manager.request_navigation(procedure.building_id)


func _on_goto_step(dest_anchor_id: String) -> void:
	if dest_anchor_id.is_empty():
		push_warning("main: goto_step has no anchor_id")
		return
	var camera := $XROrigin3D/XRCamera3D as Camera3D
	var start_id: String = await location_manager.create_content_anchor(camera.global_position)
	if start_id.is_empty():
		push_warning("main: could not create start anchor for GOTO route")
		return
	await route_manager.fetch_and_display_goto(start_id, dest_anchor_id, location_manager)


func _enter_anchor_editing(space: Space) -> void:
	if not space:
		return
	print("main: entering anchor editing mode for '", space.name, "' (", space.id, ")")
	await _localise_space(space)
	_set_mode(AppMode.ANCHOR_EDITING)
	for anchor in location_manager.get_space_anchors(space.id):
		anchor_manager.load_anchor(anchor.ml2_id)

