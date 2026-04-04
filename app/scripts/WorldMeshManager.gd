# Manages spatial mesh from ML2's world mesh detection extension.
# Creates/updates/removes MeshInstance3D nodes for each detected mesh block.

class_name WorldMeshManager
extends Node3D

@export var bounding_extents := Vector3(10, 10, 10)
@export var lod: int = 1  # 0=minimum, 1=medium, 2=maximum
@export var mesh_material: Material

var _ext = null  # OpenXRMlWorldMeshDetectionExtension singleton
var _blocks: Dictionary = {}  # block_id (String) -> MeshInstance3D


func _ready() -> void:
	# Defer initialization to ensure OpenXR singletons are registered.
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

	_start_meshing()


func _start_meshing() -> void:
	if _ext == null or _ext.is_running():
		return
	# FLAG_COMPUTE_NORMALS (2) | FLAG_REMOVE_MESH_SKIRT (16)
	var mesh_flags := 2 | 16
	_ext.start(bounding_extents, lod, mesh_flags)


func _exit_tree() -> void:
	if _ext and _ext.is_running():
		_ext.stop()


func _on_block_updated(block_id: String, status: int, vertices: PackedVector3Array, indices: PackedInt32Array, normals: PackedVector3Array) -> void:
	var mesh_inst: MeshInstance3D
	if _blocks.has(block_id):
		mesh_inst = _blocks[block_id]
	else:
		mesh_inst = MeshInstance3D.new()
		mesh_inst.material_override = mesh_material
		add_child(mesh_inst)
		_blocks[block_id] = mesh_inst

	var arr_mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_INDEX] = indices
	if normals.size() > 0:
		arrays[Mesh.ARRAY_NORMAL] = normals
	arr_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh_inst.mesh = arr_mesh


func _on_block_deleted(block_id: String) -> void:
	if _blocks.has(block_id):
		var mesh_inst: MeshInstance3D = _blocks[block_id]
		mesh_inst.queue_free()
		_blocks.erase(block_id)


func _make_default_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.2, 0.6, 1.0, 0.5)
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	return mat
