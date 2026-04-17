extends Node3D

var xr_interface: XRInterface

@onready var ui_panel: ViewportPanel3D = $XROrigin3D/UIPanel
@onready var gesture_manager: GestureManager = $XROrigin3D/GestureManager
@onready var anchor_manager: AnchorManager = $XROrigin3D/AnchorManager
@onready var location_manager: LocationManager = $XROrigin3D/LocationManager
@onready var space_manager: SpaceManager = $XROrigin3D/SpaceManager
@onready var voice_manager: VoiceManager = $XROrigin3D/VoiceManager
@onready var route_manager: RouteManager = $XROrigin3D/RouteManager

var app_state: AppState
var progress_indicator: ProgressIndicator

var _gesture_replayer: GestureReplayer = null


func _ready() -> void:
	PanelRouter.push("start_menu")

	progress_indicator = ProgressIndicator.new()
	add_child(progress_indicator)

	app_state = AppState.new()
	app_state.name = "AppState"
	var idle := IdleState.new()
	idle.name = "idle"
	app_state.add_child(idle)
	var anchor_editing := AnchorEditingState.new()
	anchor_editing.name = "anchor_editing"
	app_state.add_child(anchor_editing)
	var navigating := NavigatingState.new()
	navigating.name = "navigating"
	app_state.add_child(navigating)
	var procedure := ProcedureState.new()
	procedure.name = "procedure"
	app_state.add_child(procedure)
	add_child(app_state)

	app_state.setup(
		self,
		ui_panel,
		gesture_manager,
		location_manager,
		anchor_manager,
		route_manager,
		voice_manager,
		progress_indicator,
	)
	app_state.transition_to("idle")

	voice_manager.go_home.connect(app_state.go_home)
	voice_manager.start_recording.connect(_on_start_recording)
	voice_manager.stop_recording.connect(_on_stop_recording)

	if OS.get_name() == "Android":
		OS.request_permissions()

	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().transparent_bg = true
		get_viewport().use_xr = true

		var hand_mat := StandardMaterial3D.new()
		hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hand_mat.albedo_color = Color(0.0, 0.133, 0.357, 0.333)
		for mesh_path in [
			"XROrigin3D/LeftHand/LeftHandHumanoid/LeftHandHumanoid/Skeleton3D/LeftHandHumanoidMesh",
			"XROrigin3D/RightHand/RightHandHumanoid/RightHandHumanoid/Skeleton3D/RightHandHumanoidMesh"
		]:
			var mesh := get_node_or_null(mesh_path)
			if mesh:
				mesh.material_override = hand_mat
	else:
		print("OpenXR not initialized, please check if your headset is connected")


# ── Gesture recording (debug, voice-triggered) ────────────────────────────────

func _on_start_recording() -> void:
	if _gesture_replayer:
		_gesture_replayer.queue_free()
		_gesture_replayer = null
	gesture_manager.start_recording()


func _on_stop_recording() -> void:
	if not gesture_manager.is_recording():
		return
	var frames := gesture_manager.stop_recording()
	if frames.is_empty():
		return
	var camera := $XROrigin3D/XRCamera3D as Camera3D
	_gesture_replayer = GestureReplayer.new()
	add_child(_gesture_replayer)
	_gesture_replayer.global_transform = Transform3D(Basis.IDENTITY, camera.global_position + -camera.global_basis.z)
	_gesture_replayer.play(frames, true)
