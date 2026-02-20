extends Node3D

const PanelScene = preload("res://documents_panel.tscn")

@export var follow_speed: float = 2.0
@export var distance: float = 0.8
@export var height_offset: float = -0.15
@export var lateral_offset: float = 0.4  # metres to the right of camera forward

var _camera: XRCamera3D
var _viewport: SubViewport
var _mesh_instance: MeshInstance3D
var _quad_size := Vector2(0.4, 0.4)


func _ready() -> void:
	_camera = get_parent().get_node_or_null("XRCamera3D")
	_build_panel()


func _build_panel() -> void:
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(800, 800)
	_viewport.transparent_bg = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_viewport)

	_viewport.add_child(PanelScene.instantiate())

	var quad := QuadMesh.new()
	quad.size = _quad_size

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _viewport.get_texture()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.mesh = quad
	_mesh_instance.material_override = mat
	add_child(_mesh_instance)


func _process(delta: float) -> void:
	if not _camera:
		return

	var cam_basis := _camera.global_transform.basis
	var cam_pos := _camera.global_position

	var forward := -cam_basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		return
	forward = forward.normalized()

	var right := cam_basis.x
	right.y = 0.0
	right = right.normalized()

	var target_pos := cam_pos \
		+ forward * distance \
		+ right * lateral_offset \
		+ Vector3(0.0, height_offset, 0.0)

	global_position = global_position.lerp(target_pos, follow_speed * delta)

	var target_y := atan2(-forward.x, -forward.z)
	rotation.y = lerp_angle(rotation.y, target_y, follow_speed * delta)
