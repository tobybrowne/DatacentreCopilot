# Manages spatial mesh from ML2's world mesh detection extension.
# Creates/updates/removes MeshInstance3D nodes for each detected mesh block.

class_name WorldMeshManager
extends Node3D

@export var bounding_extents := Vector3(10, 10, 10)
# level-of-detail, passed directly to the ML2, to state the resolution of the meshes required
@export var lod: int = 0  # 0 = minimum, 1 = medium, 2 = maximum
# true = depth-only occluder (production); false = visible blue mesh (debug)
@export var depth_occlude := true
# When false, collision shapes are never rebuilt — saves significant CPU when only occlusion is needed.
# Enable only when raycasting against the world mesh (e.g. panel placement).
@export var collision_enabled: bool = true
# How many mesh block updates to skip between collision shape rebuilds (only used when collision_enabled).
@export var collision_update_stride: int = 10
# Minimum area (m²) of disconnected mesh fragments to keep — raise to cull noisy floating geometry.
@export var disconnected_component_area: float = 0.5
# Maximum hole perimeter (m) to fill — larger values close more gaps in the mesh surface.
@export var fill_hole_length: float = 1.0
# Minimum time between mesh query cycles in milliseconds — reduces ML2 meshing load.
@export var min_query_interval_ms: int = 500
@export var mesh_material: Material
@export var enabled: bool = true:
	set(v):
		enabled = v
		for body: StaticBody3D in _blocks.values():
			if is_instance_valid(body):
				body.get_node("Mesh").visible = v

var _collision_update_counter: int = 0
var _mesh_flags: int = 0
var _restarting := false

# Godot has "collision layers", only objects on the same layer can collide with each other
# for some reason these are set using a bitmask :/
const COLLISION_LAYER := 1 << 19  # bit 20: world-mesh occluders

var _ext = null  # OpenXRMlWorldMeshDetectionExtension singleton
var _blocks: Dictionary = {}  # block_id (String) -> StaticBody3D (with MeshInstance3D + CollisionShape3D children)


func _ready() -> void:
	# defer initialization to ensure OpenXR singletons are registered
	# (queues this function to run at the end of the frame)
	call_deferred("_initialize")


func _initialize() -> void:
	if not Engine.has_singleton("OpenXRMlWorldMeshDetectionExtension"):
		push_warning("WorldMeshManager: singleton not registered")
		return

	_ext = Engine.get_singleton("OpenXRMlWorldMeshDetectionExtension")
	_ext.mesh_block_updated.connect(_on_block_updated)
	_ext.mesh_block_deleted.connect(_on_block_deleted)
	_ext.meshing_error.connect(_on_meshing_error)

	if not mesh_material:
		mesh_material = _make_depth_material() if depth_occlude else _make_debug_material()

	if not _ext.is_available():
		return

	# FLAG_PLANARIZE (8)
	# COMPUTE_NORMALS and REMOVE_MESH_SKIRT omitted — skirt kept to cover block seams for occlusion
	_mesh_flags = 8
	_ext.set_disconnected_component_area(disconnected_component_area)
	_ext.set_fill_hole_length(fill_hole_length)
	_ext.set_min_query_interval_ms(min_query_interval_ms)
	_ext.start(bounding_extents, lod, _mesh_flags)


func _exit_tree() -> void:
	if _ext and _ext.is_running():
		_ext.stop()


func _on_block_updated(block_id: String, status: int, vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> void:
	var body: StaticBody3D
	var mesh_inst: MeshInstance3D
	var coll: CollisionShape3D
	if _blocks.has(block_id):
		body = _blocks[block_id]
		mesh_inst = body.get_node("Mesh")
		coll = body.get_node("Collision")
	else:
		body = StaticBody3D.new()
		body.collision_layer = COLLISION_LAYER
		body.collision_mask = 0
		add_child(body)
		mesh_inst = MeshInstance3D.new()
		mesh_inst.name = "Mesh"
		mesh_inst.material_override = mesh_material
		mesh_inst.visible = enabled
		body.add_child(mesh_inst)
		coll = CollisionShape3D.new()
		coll.name = "Collision"
		body.add_child(coll)
		_blocks[block_id] = body

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if normals.size() > 0:
		arrays[Mesh.ARRAY_NORMAL] = normals
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_inst.mesh = arr_mesh

	if collision_enabled:
		_collision_update_counter += 1
		if collision_update_stride == 0 or _collision_update_counter >= collision_update_stride:
			_collision_update_counter = 0
			var shape := ConcavePolygonShape3D.new()
			shape.set_faces(arr_mesh.get_faces())
			coll.shape = shape


func _on_block_deleted(block_id: String) -> void:
	if _blocks.has(block_id):
		var body: StaticBody3D = _blocks[block_id]
		body.queue_free()
		_blocks.erase(block_id)


func _on_meshing_error(err: String) -> void:
	if _restarting:
		return
	push_warning("WorldMeshManager: %s — restarting" % err)
	_restarting = true
	if _ext.is_running():
		_ext.stop()
	_clear_blocks()
	await get_tree().create_timer(3.0).timeout
	if _ext.is_available():
		_ext.start(bounding_extents, lod, _mesh_flags)
	else:
		push_warning("WorldMeshManager: ext not available after error — not restarting")
	_restarting = false


func _clear_blocks() -> void:
	for body in _blocks.values():
		if is_instance_valid(body):
			body.queue_free()
	_blocks.clear()
	_collision_update_counter = 0


func _make_depth_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shaders/depth_occluder.gdshader")
	mat.render_priority = -100  # render before all AR content so depth is written first
	return mat


func _make_debug_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 0.6, 1.0, 1.0)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return mat
