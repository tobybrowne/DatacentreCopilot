class_name PlaneManager
extends Node

const POLL_INTERVAL := 3.0  # seconds between detection passes

var _ext: Object = null
var _timer := 0.0
var _detecting := false
var _beginning := false
var _plane_nodes: Array[MeshInstance3D] = []
var planes_data: Array = []

# Color per semantic type
const COLORS := {
	2: Color(0.2, 1.0, 0.3, 0.18),   # floor     — green
	3: Color(0.2, 0.5, 1.0, 0.18),   # wall      — blue
	1: Color(1.0, 0.9, 0.2, 0.18),   # ceiling   — yellow
	4: Color(0.8, 0.4, 1.0, 0.18),   # platform  — purple
	0: Color(0.8, 0.8, 0.8, 0.12),   # undefined — grey
}
const EDGE_COLORS := {
	2: Color(0.2, 1.0, 0.3, 0.9),
	3: Color(0.2, 0.5, 1.0, 0.9),
	1: Color(1.0, 0.9, 0.2, 0.9),
	4: Color(0.8, 0.4, 1.0, 0.9),
	0: Color(0.8, 0.8, 0.8, 0.6),
}

var _plane_shader: Shader = null


func _ready() -> void:
	if not Engine.has_singleton("OpenXRExtPlaneDetectionExtension"):
		push_warning("PlaneManager: OpenXRExtPlaneDetectionExtension not available")
		return
	_ext = Engine.get_singleton("OpenXRExtPlaneDetectionExtension")
	if not _ext.is_supported():
		push_warning("PlaneManager: XR_EXT_plane_detection not supported on this device")
		return
	_plane_shader = _make_shader()
	print("PlaneManager: ready, waiting for localization")

	# Only start detecting once the session is localized and the play space is valid.
	if Engine.has_singleton("OpenXRMlLocalizationMapExtension"):
		var loc_ext = Engine.get_singleton("OpenXRMlLocalizationMapExtension")
		loc_ext.localization_changed.connect(_on_localized)


func _on_localized(state: int, _confidence: int, _error_flags: int) -> void:
	if state == 1 and not _beginning and not _detecting:  # 1 = LOCALIZED
		print("PlaneManager: localized, starting detection")
		_timer = POLL_INTERVAL


func _process(delta: float) -> void:
	if not _ext or not _ext.is_supported():
		return

	if _detecting:
		var state: int = _ext.get_state()
		if state == 2:  # STATE_DONE
			_detecting = false
			_refresh_planes()
			_timer = 0.0
		elif state == 3 or state == 4:  # ERROR / FATAL
			_detecting = false
			_timer = 0.0
	else:
		_timer += delta
		if _timer >= POLL_INTERVAL and not _beginning:
			_begin()


func _begin() -> void:
	_beginning = true
	_detecting = _ext.begin_detection()
	_beginning = false


func _refresh_planes() -> void:
	var planes: Array = _ext.get_planes()
	planes_data = planes

	# Remove excess nodes
	while _plane_nodes.size() > planes.size():
		var node: MeshInstance3D = _plane_nodes.pop_back()
		node.queue_free()

	# Add missing nodes
	while _plane_nodes.size() < planes.size():
		var mi := MeshInstance3D.new()
		mi.mesh = QuadMesh.new()
		get_parent().add_child(mi)
		_plane_nodes.append(mi)

	for i in planes.size():
		var plane: Dictionary = planes[i]
		var mi: MeshInstance3D = _plane_nodes[i]
		var sem: int = plane["semantic_type"]
		var w: float = plane["width"]
		var h: float = plane["height"]

		(mi.mesh as QuadMesh).size = Vector2(w, h)
		mi.global_transform = plane["transform"]

		var mat := ShaderMaterial.new()
		mat.shader = _plane_shader
		mat.set_shader_parameter("fill_color", COLORS.get(sem, COLORS[0]))
		mat.set_shader_parameter("edge_color", EDGE_COLORS.get(sem, EDGE_COLORS[0]))
		mat.set_shader_parameter("edge_width", 0.04)
		mi.material_override = mat

	print("PlaneManager: updated ", planes.size(), " planes")


func _make_shader() -> Shader:
	var shader := Shader.new()
	shader.code = """
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;

uniform vec4 fill_color : source_color = vec4(0.2, 0.5, 1.0, 0.15);
uniform vec4 edge_color : source_color = vec4(0.2, 0.5, 1.0, 0.9);
uniform float edge_width : hint_range(0.0, 0.5) = 0.04;

void fragment() {
	vec2 uv = UV;
	float ex = edge_width;
	bool on_edge = uv.x < ex || uv.x > 1.0 - ex || uv.y < ex || uv.y > 1.0 - ex;
	vec4 color = on_edge ? edge_color : fill_color;
	ALBEDO = color.rgb;
	ALPHA = color.a;
}
"""
	return shader
