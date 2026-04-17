# Drives the parent XRCamera3D with keyboard/mouse when OpenXR fails to init.
# Lets you iterate on UI/scene behaviour without wearing the headset.
# WASD = move, Space = jump, mouse = look, Esc = toggle mouse capture.

extends Node

@export var move_speed: float = 1.2
@export var mouse_sensitivity: float = 0.003
@export var eye_height: float = 1.6
@export var gravity: float = 9.8
@export var jump_speed: float = 4.0
@export var fov: float = 50.0

var _camera: XRCamera3D
var _yaw := 0.0
var _pitch := 0.0
var _vertical_velocity := 0.0
var _grounded := false


func _ready() -> void:
	_camera = get_parent() as XRCamera3D
	if not _camera:
		push_warning("DesktopXRSim must be a child of XRCamera3D")
		set_process(false)
		set_process_input(false)
		return

	if XRMode.is_active():
		set_process(false)
		set_process_input(false)
		return

	_camera.position = Vector3(0.0, eye_height + 1.0, 0.0)
	_camera.fov = fov
	_camera.current = true
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_yaw -= event.relative.x * mouse_sensitivity
		_pitch = clamp(_pitch - event.relative.y * mouse_sensitivity, -PI * 0.49, PI * 0.49)
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED


func _process(delta: float) -> void:
	var basis := Basis.from_euler(Vector3(_pitch, _yaw, 0.0))
	_camera.transform.basis = basis

	var flat_basis := Basis.from_euler(Vector3(0.0, _yaw, 0.0))
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= flat_basis.z
	if Input.is_key_pressed(KEY_S): dir += flat_basis.z
	if Input.is_key_pressed(KEY_A): dir -= flat_basis.x
	if Input.is_key_pressed(KEY_D): dir += flat_basis.x

	if dir.length_squared() > 0.0:
		_camera.position += dir.normalized() * move_speed * delta

	if Input.is_key_pressed(KEY_SPACE) and _grounded:
		_vertical_velocity = jump_speed
		_grounded = false

	_vertical_velocity -= gravity * delta
	_camera.position.y += _vertical_velocity * delta

	_resolve_floor()


func _resolve_floor() -> void:
	var space := _camera.get_world_3d().direct_space_state
	var from := _camera.global_position
	var to := from + Vector3.DOWN * (eye_height + 2.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		_grounded = false
		return
	var floor_y: float = hit["position"].y
	var target_y := floor_y + eye_height
	if _camera.global_position.y <= target_y:
		_camera.global_position.y = target_y
		if _vertical_velocity < 0.0:
			_vertical_velocity = 0.0
		_grounded = true
	else:
		_grounded = false
