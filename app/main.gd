extends Node3D

var xr_interface: XRInterface

@onready var procedure_panel = $XROrigin3D/ProcedurePanel
@onready var step_viewer = $XROrigin3D/StepViewer
@onready var pinch_step_control = $XROrigin3D/PinchStepControl
@onready var anchor_manager: AnchorManager = $XROrigin3D/AnchorManager

const PINCH_DIST           := 0.015  # metres — finger gap to count as pinching
const PINCH_HOLD_TIME      := 3.0    # seconds to hold before action fires
const ANCHOR_DELETE_RADIUS := 0.10   # metres — how close to an anchor to target it for delete

# Tracking indicator
var _tracking_dot: MeshInstance3D
var _tracking_dot_mat: StandardMaterial3D

# -- ML2 localization extension (commented out — events unreliable, using OpenXR core state instead)
# var _loc_ext = null  # OpenXRMlLocalizationMapExtension singleton, null if unavailable
# const LOC_CONFIDENCE_FAIR      := 1
# const LOC_CONFIDENCE_GOOD      := 2
# const LOC_CONFIDENCE_EXCELLENT := 3


# UUID poll timer
var _uuid_timer := 0.0

# Pinch state
var _pinch_hold_time := 0.0
var _pinch_fired     := false
var _pinch_mode      := ""   # "create" | "delete"
var _pinch_target: Anchor = null   # uuid of anchor targeted for deletion

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
	procedure_panel.procedure_selected.connect(_on_procedure_selected)
	pinch_step_control.prev_requested.connect(step_viewer.prev_step)
	pinch_step_control.next_requested.connect(step_viewer.next_step)

	xr_interface = XRServer.find_interface("OpenXR")
	_create_tracking_indicator()
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
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
	_check_for_anchor_action(delta)
	_update_tracking_indicator(delta)
	_poll_localization_uuid(delta)


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
	var camera := $XROrigin3D/XRCamera3D
	_tracking_dot_mat = StandardMaterial3D.new()
	_tracking_dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_tracking_dot_mat.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED

	var sphere := SphereMesh.new()
	sphere.radius = 0.004
	sphere.height = 0.008

	_tracking_dot = MeshInstance3D.new()
	_tracking_dot.mesh = sphere
	_tracking_dot.material_override = _tracking_dot_mat
	_tracking_dot.position = Vector3(0.11, 0.07, -0.3)
	camera.add_child(_tracking_dot)

func _update_tracking_indicator(_delta: float) -> void:
	if not _tracking_dot_mat:
		return
	if not xr_interface:
		_tracking_dot_mat.albedo_color = Color(0.5, 0.5, 0.5)
		return
	var confidence := XRPose.XR_TRACKING_CONFIDENCE_NONE
	var head_tracker := XRServer.get_tracker("head")

	# print("Head tracker: ", head_tracker, " all trackers: ", XRServer.get_trackers(XRServer.TRACKER_ANY))
	if head_tracker:
		var pose: XRPose = head_tracker.get_pose("default")
		# print("Head pose: ", pose)
		if pose:
			confidence = pose.tracking_confidence
			# print("Tracking confidence: ", confidence)
	match confidence:
		XRPose.XR_TRACKING_CONFIDENCE_HIGH:
			_tracking_dot_mat.albedo_color = Color(0.0, 1.0, 0.2)
		XRPose.XR_TRACKING_CONFIDENCE_LOW:
			_tracking_dot_mat.albedo_color = Color(1.0, 0.55, 0.0)
		_:
			_tracking_dot_mat.albedo_color = Color(1.0, 0.2, 0.2)

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


# ── Pinch → anchor create / delete ────────────────────────────────────────────

func _check_for_anchor_action(delta: float) -> void:
	var tracker := XRServer.get_tracker("/user/hand_tracker/right")
	if not tracker is XRHandTracker:
		_end_pinch()
		return

	var ht := tracker as XRHandTracker
	if not (ht.get_hand_joint_flags(5) & 4) or not (ht.get_hand_joint_flags(10) & 4):
		_end_pinch()
		return

	var thumb_pos := ht.get_hand_joint_transform(5).origin
	var index_pos := ht.get_hand_joint_transform(10).origin
	var pinch_pos := (thumb_pos + index_pos) * 0.5

	if thumb_pos.distance_to(index_pos) >= PINCH_DIST:
		_end_pinch()
		return

	if _pinch_fired:
		return

	if _pinch_hold_time == 0.0:
		var near: Anchor = anchor_manager.get_anchor_near(pinch_pos, ANCHOR_DELETE_RADIUS)
		_pinch_mode   = "delete" if near != null else "create"
		_pinch_target = near

	_pinch_hold_time += delta
	_update_progress_indicator(pinch_pos, minf(_pinch_hold_time / PINCH_HOLD_TIME, 1.0))

	if _pinch_hold_time >= PINCH_HOLD_TIME:
		_pinch_fired = true
		_clear_progress_indicator()
		if _pinch_mode == "create":
			anchor_manager.place_anchor(Transform3D(Basis.IDENTITY, pinch_pos))
		else:
			anchor_manager.remove_anchor(_pinch_target)


func _end_pinch() -> void:
	_pinch_hold_time = 0.0
	_pinch_fired     = false
	_pinch_mode      = ""
	_pinch_target    = null
	_clear_progress_indicator()


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
	var color := Color(0.2, 0.8, 1.0) if _pinch_mode == "create" else Color(1.0, 0.3, 0.2)
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


# ── Signals ───────────────────────────────────────────────────────────────────

func _on_procedure_selected(procedure: Procedure):
	print("Switching to: ", procedure.id)
	procedure_panel.visible = false
	step_viewer.visible = true
	step_viewer.setup(procedure.steps)
