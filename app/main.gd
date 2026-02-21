extends Node3D

var xr_interface: XRInterface

# load relevant nodes
@onready var procedure_panel = $XROrigin3D/ProcedurePanel
@onready var step_viewer = $XROrigin3D/StepViewer
@onready var pinch_step_control = $XROrigin3D/PinchStepControl
@onready var anchor_manager: AnchorManager = $XROrigin3D/AnchorManager
@onready var right_hand: XRNode3D = $XROrigin3D/RightHand

# Long right-hand pinch (hold 1 s) places an anchor at the hand position.
const PINCH_PLACE_DIST := 0.02   # metres — same threshold as PinchStepControl
const PINCH_PLACE_TIME := 1.0    # seconds to hold before placing
var _pinch_hold_time := 0.0

func _ready():
	# map scene signals to local functions
	procedure_panel.procedure_selected.connect(_on_procedure_selected)
	pinch_step_control.prev_requested.connect(step_viewer.prev_step)
	pinch_step_control.next_requested.connect(step_viewer.next_step)


	xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		print("OpenXR initialized successfully")

		# Turn off v-sync!
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)

		# Transparent background for AR passthrough
		get_viewport().transparent_bg = true

		# Change our main viewport to output to the HMD
		get_viewport().use_xr = true

		# Transparent blue hand material
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
	_update_anchor_placement(delta)


func _update_anchor_placement(delta: float) -> void:
	var tracker := XRServer.get_tracker("/user/hand_tracker/right")
	if not tracker is XRHandTracker:
		_pinch_hold_time = 0.0
		return

	var ht := tracker as XRHandTracker
	# Joint 5 = thumb tip, joint 10 = index tip. Flag 4 = position valid.
	if not (ht.get_hand_joint_flags(5) & 4) or not (ht.get_hand_joint_flags(10) & 4):
		_pinch_hold_time = 0.0
		return

	var dist := ht.get_hand_joint_transform(5).origin.distance_to(
			ht.get_hand_joint_transform(10).origin)

	if dist < PINCH_PLACE_DIST:
		_pinch_hold_time += delta
		if _pinch_hold_time >= PINCH_PLACE_TIME:
			_pinch_hold_time = -9999.0  # prevent re-trigger until hand opens
			anchor_manager.place_anchor(right_hand.global_transform)
	else:
		_pinch_hold_time = 0.0


func _on_procedure_selected(procedure: Procedure):
	"""
	Runs when a procedure is selected from the procedure panel
	"""
	print("Switching to: ", procedure.id)

	# 1. Hide the procedure panel
	procedure_panel.visible = false
	# (probably want to add animations, also nuke the underlying process)

	# 2. Show the StepViewer node and instantiate with steps
	step_viewer.visible = true
	step_viewer.setup(procedure.steps)
