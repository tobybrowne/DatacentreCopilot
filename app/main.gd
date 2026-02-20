extends Node3D

var xr_interface: XRInterface

func _ready():
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
