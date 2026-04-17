extends Node3D
class_name ContextMenu3D

signal item_selected(index: int, label: String)
signal dismissed

const ITEM_SPACING  := 0.065
const HIT_RADIUS    := 0.05
const ITEM_W        := 0.22
const ITEM_H        := 0.048
const PINCH_OFFSET  := 0.05   # gap between pinch point and first item
const PINCH_DOT_R   := 0.006  # radius of the pinch marker sphere

var _items: Array[Dictionary] = []   # {node, label, bg_mat}
var _gesture_manager: GestureManager
var _hovered := -1


func open(world_pos: Vector3, options: Array[String], gm: GestureManager) -> void:
	_gesture_manager = gm
	global_position = world_pos
	_build(options)


func _build(options: Array[String]) -> void:
	_build_pinch_marker(options.size())

	for i in options.size():
		var item_root := Node3D.new()
		item_root.position = Vector3(0.0, -PINCH_OFFSET - i * ITEM_SPACING, 0.0)
		add_child(item_root)

		var quad := QuadMesh.new()
		quad.size = Vector2(ITEM_W, ITEM_H)

		var bg_mat := StandardMaterial3D.new()
		bg_mat.shading_mode  = BaseMaterial3D.SHADING_MODE_UNSHADED
		bg_mat.transparency  = BaseMaterial3D.TRANSPARENCY_ALPHA
		bg_mat.albedo_color  = Color(0.08, 0.08, 0.12, 0.88)
		bg_mat.no_depth_test = true

		var bg := MeshInstance3D.new()
		bg.mesh              = quad
		bg.material_override = bg_mat
		item_root.add_child(bg)

		var lbl := Label3D.new()
		lbl.text        = options[i]
		lbl.font_size   = 52
		lbl.pixel_size  = 0.00028
		lbl.no_depth_test = true
		lbl.position   = Vector3(0.0, 0.0, 0.001)
		lbl.modulate    = Color.WHITE
		item_root.add_child(lbl)

		_items.append({"node": item_root, "label": options[i], "bg_mat": bg_mat})


func _build_pinch_marker(_item_count: int) -> void:
	var color := Color(0.4, 0.85, 1.0)

	# Glowing dot at the pinch point (menu origin).
	var dot_mesh := SphereMesh.new()
	dot_mesh.radius         = PINCH_DOT_R
	dot_mesh.height         = PINCH_DOT_R * 2.0
	dot_mesh.radial_segments = 12
	dot_mesh.rings          = 6

	var dot_mat := StandardMaterial3D.new()
	dot_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dot_mat.albedo_color = color
	dot_mat.no_depth_test = true

	var dot := MeshInstance3D.new()
	dot.mesh              = dot_mesh
	dot.material_override = dot_mat
	add_child(dot)

	# Tether from pinch dot down to the first item.
	var line_mesh := ImmediateMesh.new()
	var line_mat := StandardMaterial3D.new()
	line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	line_mat.albedo_color = Color(color.r, color.g, color.b, 0.6)
	line_mat.no_depth_test = true

	var line := MeshInstance3D.new()
	line.mesh              = line_mesh
	line.material_override = line_mat
	add_child(line)

	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	line_mesh.surface_add_vertex(Vector3(0.0, -PINCH_DOT_R, 0.0))
	line_mesh.surface_add_vertex(Vector3(0.0, -PINCH_OFFSET + ITEM_H * 0.5, 0.0))
	line_mesh.surface_end()


func close() -> void:
	queue_free()


func _process(_delta: float) -> void:
	if not _gesture_manager:
		return

	# Face camera each frame — look_at points -Z toward camera, quads face +Z so flip 180°
	var camera := get_viewport().get_camera_3d()
	if camera and global_position.distance_to(camera.global_position) > 0.01:
		look_at(camera.global_position, Vector3.UP)
		rotate_object_local(Vector3.UP, PI)

	# Ray hover detection — check both hands, prefer right. When an item is
	# hit, also report the closest-approach point to GestureManager so the
	# hand beam visually terminates at the menu instead of shooting through.
	var new_hovered := -1
	for hand in ["right", "left"]:
		if not _gesture_manager.ray_active.get(hand, false):
			continue
		var origin : Vector3 = _gesture_manager.ray_origins[hand]
		var dir    : Vector3 = _gesture_manager.ray_directions[hand]
		for i in _items.size():
			var item_world := (_items[i]["node"] as Node3D).global_position
			var to_item    := item_world - origin
			var proj       := to_item.dot(dir)
			if proj <= 0.0:
				continue
			var closest := origin + dir * proj
			if closest.distance_to(item_world) < HIT_RADIUS:
				new_hovered = i
				_gesture_manager.set_hit_point(hand, closest)
				break
		if new_hovered != -1:
			break

	if new_hovered != _hovered:
		_hovered = new_hovered
		_update_highlight()


func _update_highlight() -> void:
	for i in _items.size():
		var mat: StandardMaterial3D = _items[i]["bg_mat"]
		if i == _hovered:
			mat.albedo_color = Color(0.2, 0.55, 1.0, 0.92)
		else:
			mat.albedo_color = Color(0.08, 0.08, 0.12, 0.88)


func get_hovered() -> int:
	return _hovered
