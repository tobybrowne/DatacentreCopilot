extends Node3D

const _SHOW_HAND_HIGHLIGHT := false

@onready var ui_panel: ViewportPanel3D = $XROrigin3D/UIPanel
@onready var keyboard_panel: ViewportPanel3D = $XROrigin3D/KeyboardPanel3D
@onready var gesture_manager: GestureManager = $XROrigin3D/GestureManager
@onready var anchor_manager: AnchorManager = $XROrigin3D/AnchorManager
@onready var location_manager: LocationManager = $XROrigin3D/LocationManager
@onready var space_manager: SpaceManager = $XROrigin3D/SpaceManager
@onready var voice_manager: VoiceManager = $XROrigin3D/VoiceManager
@onready var route_manager: RouteManager = $XROrigin3D/RouteManager

var app_state: AppState
var progress_indicator: ProgressIndicator

var _gesture_replayer: PoseReplayer = null


func _ready() -> void:
	print("[main] _ready start")
	PanelRouter.push("start_menu")
	KeyboardManager.register(keyboard_panel)
	var note_manager := NoteManager.new()
	$XROrigin3D.add_child(note_manager)
	LogRecordManager.setup(gesture_manager, anchor_manager, CVCameraManager)

	progress_indicator = ProgressIndicator.new()
	add_child(progress_indicator)

	app_state = AppState.new()
	app_state.name = "AppState"
	var idle := IdleState.new()
	app_state.add_child(idle)
	var anchor_editing := AnchorEditingState.new()
	app_state.add_child(anchor_editing)
	var navigating := NavigatingState.new()
	app_state.add_child(navigating)
	var procedure := ProcedureState.new()
	app_state.add_child(procedure)
	add_child(app_state)

	app_state.setup(
		self,
		ui_panel,
		gesture_manager,
		location_manager,
		anchor_manager,
		space_manager,
		route_manager,
		note_manager,
		voice_manager,
		progress_indicator,
	)
	app_state.transition_to(AppState.States.IDLE)
	ContextManager.setup()
	location_manager.coarse_space_changed.connect(ContextManager.set_space)
	app_state.state_changed.connect(func(_from, to): ContextManager.set_app_state(AppState.States.find_key(to).to_lower()))
	PanelRouter.panel_changed.connect(func(panel_id, _data): ContextManager.set_panel(panel_id))
	CopilotManager.connect_voice_manager(voice_manager)
	CopilotManager.setup_hud($XROrigin3D/XRCamera3D)

	if OS.get_name() == "Android":
		OS.request_permissions()

	if XRMode.is_active():
		print("OpenXR initialized successfully")
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		get_viewport().transparent_bg = true
		get_viewport().use_xr = true
		# AR mode: swap background to camera feed for passthrough.
		CameraServer.set_monitoring_feeds(true)
		var world_env := $WorldEnvironment as WorldEnvironment
		if world_env and world_env.environment:
			world_env.environment.background_mode = Environment.BG_CAMERA_FEED

		var hand_mat := StandardMaterial3D.new()
		hand_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		hand_mat.albedo_color = Color(0.0, 0.133, 0.357, 0.333) if _SHOW_HAND_HIGHLIGHT else Color(0, 0, 0, 0)
		for mesh_path in [
			"XROrigin3D/LeftHand/LeftHandHumanoid/LeftHandHumanoid/Skeleton3D/LeftHandHumanoidMesh",
			"XROrigin3D/RightHand/RightHandHumanoid/RightHandHumanoid/Skeleton3D/RightHandHumanoidMesh"
		]:
			var mesh := get_node_or_null(mesh_path)
			if mesh:
				mesh.material_override = hand_mat
	else:
		print("OpenXR not initialized, please check if your headset is connected")
		# Desktop sim environment so there's something visible to test against.
		var sim_scene: PackedScene = load("res://assets/sponza/Sponza.gltf")
		if sim_scene:
			var sim_root: Node = sim_scene.instantiate()
			add_child(sim_root)
			_generate_sim_collision(sim_root)


func _generate_sim_collision(node: Node) -> void:
	if node is MeshInstance3D:
		(node as MeshInstance3D).create_trimesh_collision()
	for child in node.get_children():
		_generate_sim_collision(child)


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
	_gesture_replayer = PoseReplayer.new()
	add_child(_gesture_replayer)
	_gesture_replayer.global_transform = Transform3D(Basis.IDENTITY, camera.global_position + -camera.global_basis.z)
	_gesture_replayer.play(frames, true)
