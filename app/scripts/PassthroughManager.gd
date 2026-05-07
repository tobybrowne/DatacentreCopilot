extends Node

var _blackout: MeshInstance3D = null
var _ar_visible := true


func setup(camera: Camera3D) -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2(10.0, 10.0)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0, 0, 0, 1)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.no_depth_test = true
	mat.render_priority = 100
	_blackout = MeshInstance3D.new()
	_blackout.mesh = quad
	_blackout.material_override = mat
	_blackout.position = Vector3(0, 0, -0.5)
	_blackout.visible = false
	camera.add_child(_blackout)


func toggle() -> void:
	_ar_visible = not _ar_visible
	if _blackout:
		_blackout.visible = not _ar_visible


func is_ar_visible() -> bool:
	return _ar_visible
