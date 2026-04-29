# Manages spatial mesh from ML2's world mesh detection extension.
# Creates/updates/removes MeshInstance3D nodes for each detected mesh block.

class_name WorldMeshManager
extends Node3D

@export var bounding_extents := Vector3(10, 10, 10)
# level-of-detail, passed directly to the ML2, to state the resolution of the meshes required
@export var lod: int = 1  # 0 = minimum, 1 = medium, 2 = maximum
@export var mesh_material: Material

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
	_ext.meshing_error.connect(func(err): push_warning("WorldMeshManager: %s" % err))

	if not mesh_material:
		mesh_material = _make_default_material()

	if not _ext.is_available():
		return

	# FLAG_COMPUTE_NORMALS (2) | FLAG_REMOVE_MESH_SKIRT (16)
	var mesh_flags := 2 | 16
	_ext.start(bounding_extents, lod, mesh_flags)


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

	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(arr_mesh.get_faces())
	coll.shape = shape


func _on_block_deleted(block_id: String) -> void:
	if _blocks.has(block_id):
		var body: StaticBody3D = _blocks[block_id]
		body.queue_free()
		_blocks.erase(block_id)


func _make_default_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return mat
