class_name DollhouseMapManager
extends Node3D

## Voice-driven floating "dollhouse" map of the current building.
##
## On the `show_map` copilot tool, downloads each building space's GLB scan,
## places it at its stored offset_transformation (the building frame), recenters
## and auto-scales the assembly into a small hologram, and world-locks it in
## front of the user. A "you are here" marker tracks the user's position live.
##
## The room scans are stored per-space and never merged server-side: the
## offset_transformation already defines each room's pose relative to the
## reference space, so the whole building stitches together client-side at
## render time. Per-space GLBs are cached on-device so repeat opens are instant.
##
## Must be a child of XROrigin3D and given an AnchorManager + XRCamera3D ref.

const _CACHE_DIR := "user://dollhouse"
const _TARGET_SIZE := 0.6        # longest horizontal dim of the dollhouse, metres
const _MIN_SCALE := 0.005
const _MAX_SCALE := 0.2
const _SPAWN_DISTANCE := 1.0     # metres in front of the user
const _SPAWN_DROP := 0.4         # metres below eye level
const _FOLLOW_LERP := 5.0        # follow-mode position/yaw smoothing (higher = snappier)
const _FOLLOW_SCALE := 2.5       # fixed scale in follow mode - zoomed in around the user
const _FOLLOW_DISTANCE := 0.5    # metres in front of the user in follow mode (closer than spawn)
const _FOLLOW_DROP := 0.5        # metres below eye level in follow mode
const _FOLLOW_RADIUS := 12.0     # building metres around the user shown in follow mode (rest clipped)
const _STITCH_API := "https://room-finder.tobybrowne.co.uk"
const _TARGET_FACES := 15000     # decimation target per room scan (server-side)

# Two-hand manipulation (grab to move, two-hand pinch to scale + twist to rotate).
const _PINCH_THRESHOLD := 0.02   # thumb-index distance (m) counted as a pinch
const _GRAB_MARGIN := 0.08       # extra reach (m) around the model's box to start a grab
const _MANIP_MIN_SCALE := 0.1    # smallest user scale rel. to the auto-fit size (no upper limit)

var _anchor_manager: AnchorManager
var _camera: Camera3D
var _gesture_manager: GestureManager

var _container: Node3D = null     # world-locked root (moved/scaled/rotated by manipulation)
var _building_root: Node3D = null # auto-fit scale
var _mesh_holder: Node3D = null   # holds rooms + marker, offset so building centre is at origin
var _user_marker: Node3D = null
var _scan_material: ShaderMaterial = null  # shared room material; clip uniforms set per frame
var _building_centre := Vector3.ZERO
var _building_id := ""
var _building := false            # true while a map is shown
var _follow_mode := false         # nav mode: map follows the user + faces their heading
var _follow_snap := true          # snap to the user on the first follow frame, then smooth
var _pre_follow_scale := Vector3.ONE  # user's manual scale, restored when follow mode ends

# Manipulation state
var _building_aabb := AABB()      # scan bounds in the building frame (mesh_holder local space)
var _fit_scale := 1.0             # auto-fit scale applied to _building_root
var _grab := {"left": false, "right": false}
var _prev_pos := {"left": Vector3.ZERO, "right": Vector3.ZERO}
var _two_active := false
var _prev_mid := Vector3.ZERO
var _prev_dist := 0.0
var _prev_vec := Vector3.ZERO


func setup(anchor_manager: AnchorManager, camera: Camera3D, voice_manager: VoiceManager = null, gesture_manager: GestureManager = null) -> void:
	_anchor_manager = anchor_manager
	_camera = camera
	_gesture_manager = gesture_manager
	CopilotManager.function_called.connect(_on_copilot_function)
	if voice_manager and DevConfig.DOLLHOUSE_MAP_VOICE_SHORTCUT:
		voice_manager.show_map.connect(_on_voice_show_map)
	DirAccess.make_dir_recursive_absolute(_CACHE_DIR)


# Dev shortcut: local "show map" voice intent, bypasses the copilot WebSocket.
# No call_id, so _show_map's replies are suppressed (see _reply).
func _on_voice_show_map() -> void:
	print("DollhouseMapManager: voice shortcut - show map")
	await _show_map("")


func _on_copilot_function(fn_name: String, call_id: String, _args: Dictionary) -> void:
	match fn_name:
		"show_map":
			await _show_map(call_id)
		"hide_map":
			_hide_map()
			_reply(call_id, {"hidden": true})
		"follow_map":
			await _toggle_follow(call_id)


# Sends a tool result back to the copilot, unless this was triggered by the dev
# voice shortcut (empty call_id), in which case there's no call to answer.
func _reply(call_id: String, payload: Dictionary) -> void:
	if call_id.is_empty():
		return
	CopilotManager.send_function_output(call_id, JSON.stringify(payload))


# ── Show / hide ───────────────────────────────────────────────────────────────

func _show_map(call_id: String) -> void:
	if _building:
		_reply(call_id, {"error": "already building map"})
		return
	if not _anchor_manager or not _anchor_manager._calibrated:
		_reply(call_id, {"error": "not localised yet - the map needs the building to be calibrated first"})
		return

	_building = true
	_hide_map()

	var spaces := await _resolve_spaces()
	var with_scans: Array[Space] = []
	for s in spaces:
		if not s.glb_path.is_empty():
			with_scans.append(s)
	if with_scans.is_empty():
		_building = false
		_reply(call_id, {"error": "no scans available for this building"})
		return

	_container = Node3D.new()
	_container.name = "Dollhouse"
	get_parent().add_child(_container)
	_place_in_front()

	_building_root = Node3D.new()
	_container.add_child(_building_root)
	_mesh_holder = Node3D.new()
	_building_root.add_child(_mesh_holder)

	var hologram := _make_hologram_material()
	_scan_material = hologram
	var placed := 0
	for space in with_scans:
		var scene := await _load_space_scene(space)
		if scene == null:
			continue
		_apply_material(scene, hologram)
		var room := Node3D.new()
		room.transform = space.offset_transformation
		room.add_child(scene)
		_mesh_holder.add_child(room)
		placed += 1

	if placed == 0:
		_building = false
		_hide_map()
		_reply(call_id, {"error": "failed to load any scans"})
		return

	_fit_and_centre()
	_add_user_marker()

	_building = false
	_reply(call_id, {"shown": true, "rooms": placed})


func _hide_map() -> void:
	if _container:
		_container.queue_free()
		_container = null
	_building_root = null
	_mesh_holder = null
	_user_marker = null
	_scan_material = null
	_grab = {"left": false, "right": false}
	_two_active = false
	_follow_mode = false


# ── Nav (follow) mode ─────────────────────────────────────────────────────────

# Toggles navigation mode. Shows the map first if it isn't up. In follow mode the
# map keeps its current form but each frame eases toward a pose in front of the
# user, rotated to match their heading, so it tracks them as they walk.
func _toggle_follow(call_id: String) -> void:
	if not _container:
		await _show_map("")
		if not _container:
			_reply(call_id, {"error": "could not show map to follow"})
			return
	_follow_mode = not _follow_mode
	_follow_snap = true   # jump to the user on the first follow frame, then smooth
	if _follow_mode:
		# Follow mode owns scale/orientation - stash the manual scale and drop any
		# in-progress grab so prior manipulation has no effect while following.
		_pre_follow_scale = _container.scale
		_grab = {"left": false, "right": false}
		_two_active = false
	else:
		_container.scale = _pre_follow_scale   # hand the manual scale back
		if _scan_material:
			_scan_material.set_shader_parameter("clip_radius", -1.0)  # show whole building again
	_reply(call_id, {"following": _follow_mode})


func _update_follow(delta: float) -> void:
	if not _follow_mode or not _camera or not _container or not _anchor_manager:
		return
	var cam := _camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var target_pos := cam.origin + fwd * _FOLLOW_DISTANCE + Vector3(0, -_FOLLOW_DROP, 0)

	# Heading-up tracking: rotate the map so the user's in-building heading points
	# the way they're actually facing. The marker (centred, yawed to its building
	# heading) then always points "forward", and the rooms rotate around it.
	var yaw_world := atan2(fwd.x, fwd.z)
	var yaw_building: float = _user_building_pose().yaw
	var target_yaw := yaw_world - yaw_building

	var t := 1.0 if _follow_snap else clampf(_FOLLOW_LERP * delta, 0.0, 1.0)
	_follow_snap = false
	_container.global_position = _container.global_position.lerp(target_pos, t)
	_container.global_rotation.y = lerp_angle(_container.global_rotation.y, target_yaw, t)
	_container.scale = _container.scale.lerp(Vector3.ONE * _FOLLOW_SCALE, t)

	# Show only a disc of building around the user (centred on the marker = the
	# container origin), radius scaled with the model so it's _FOLLOW_RADIUS metres.
	if _scan_material:
		var total_scale: float = _container.scale.x * _fit_scale
		_scan_material.set_shader_parameter("clip_center", _container.global_position)
		_scan_material.set_shader_parameter("clip_radius", _FOLLOW_RADIUS * total_scale)


# ── Placement / scaling ───────────────────────────────────────────────────────

func _place_in_front() -> void:
	if not _camera or not _container:
		return
	var cam := _camera.global_transform
	var fwd := -cam.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	_container.global_position = cam.origin + fwd * _SPAWN_DISTANCE + Vector3(0, -_SPAWN_DROP, 0)
	# Face the dollhouse toward the user so it reads consistently.
	_container.global_rotation = Vector3(0, atan2(fwd.x, fwd.z), 0)


func _fit_and_centre() -> void:
	var bounds := _subtree_aabb(_mesh_holder, Transform3D.IDENTITY)
	if not bounds[1]:
		return
	var aabb: AABB = bounds[0]
	_building_centre = aabb.get_center()
	var size := aabb.size
	var max_dim := maxf(size.x, size.z)
	var scale := _TARGET_SIZE / max_dim if max_dim > 0.001 else 0.02
	scale = clampf(scale, _MIN_SCALE, _MAX_SCALE)
	_building_root.scale = Vector3.ONE * scale
	_mesh_holder.position = -_building_centre
	_building_aabb = aabb     # building-frame bounds, for grab hit-testing
	_fit_scale = scale


# Returns [AABB, valid] for the subtree under `node`, expressed in the local
# space of the node this recursion started from. `xf` is the accumulated
# transform from that origin down to `node`.
func _subtree_aabb(node: Node3D, xf: Transform3D) -> Array:
	var result := AABB()
	var valid := false
	if node is MeshInstance3D and node.mesh:
		result = xf * node.get_aabb()
		valid = true
	for child in node.get_children():
		if child is Node3D:
			var c := _subtree_aabb(child, xf * child.transform)
			if c[1]:
				result = result.merge(c[0]) if valid else c[0]
				valid = true
	return [result, valid]


# ── Manipulation (grab to move, two-hand pinch to scale + twist to rotate) ──────

func _update_manipulation() -> void:
	var xr := get_parent() as Node3D
	if not xr:
		return
	var l := _hand_pinch("left", xr)
	var r := _hand_pinch("right", xr)

	var was_left: bool = _grab["left"]
	var was_right: bool = _grab["right"]
	_grab["left"] = _eval_grab(was_left, l)
	_grab["right"] = _eval_grab(was_right, r)

	# Stop the state machine treating a map-grab as a context-menu / nav gesture.
	if _gesture_manager:
		if _grab["left"]: _gesture_manager.claim_ui("left")
		if _grab["right"]: _gesture_manager.claim_ui("right")

	if _grab["left"] and _grab["right"]:
		var mid: Vector3 = (l.pos + r.pos) * 0.5
		var dist: float = l.pos.distance_to(r.pos)
		var vec: Vector3 = r.pos - l.pos
		if _two_active:  # both grabbed last frame too - safe to apply deltas
			if _prev_dist > 0.001:
				_scale_about(mid, dist / _prev_dist)
			_container.global_position += mid - _prev_mid          # move with the hands
			_rotate_about_y(mid, _yaw_delta(_prev_vec, vec))       # twist to rotate
		_two_active = true
		_prev_mid = mid
		_prev_dist = dist
		_prev_vec = vec
		_prev_pos["left"] = l.pos
		_prev_pos["right"] = r.pos
		return

	_two_active = false
	# One-hand drag: only apply a delta if this hand was already grabbing last
	# frame, otherwise the first grab frame would jump by a stale prev position.
	if _grab["left"] and was_left:
		_container.global_position += (l.pos as Vector3) - _prev_pos["left"]
	elif _grab["right"] and was_right:
		_container.global_position += (r.pos as Vector3) - _prev_pos["right"]
	_prev_pos["left"] = l.pos
	_prev_pos["right"] = r.pos


# Returns {valid, pinching, pos} for a hand, pos in world space.
func _hand_pinch(hand: String, xr: Node3D) -> Dictionary:
	var tracker := XRServer.get_tracker("/user/hand_tracker/" + hand)
	if not tracker or not tracker is XRHandTracker:
		return {"valid": false, "pinching": false, "pos": Vector3.ZERO}
	var ht := tracker as XRHandTracker
	if not ht.has_tracking_data or not (ht.get_hand_joint_flags(5) & 4) or not (ht.get_hand_joint_flags(10) & 4):
		return {"valid": false, "pinching": false, "pos": Vector3.ZERO}
	var thumb: Vector3 = ht.get_hand_joint_transform(5).origin
	var index: Vector3 = ht.get_hand_joint_transform(10).origin
	return {
		"valid": true,
		"pinching": thumb.distance_to(index) < _PINCH_THRESHOLD,
		"pos": xr.global_transform * ((thumb + index) * 0.5),
	}


# A grab persists while pinching; it can only start when the pinch lands near the map.
func _eval_grab(was: bool, h: Dictionary) -> bool:
	if not h.valid or not h.pinching:
		return false
	if was:
		return true
	if not _mesh_holder:
		return false
	# Tight hit-test against the model's actual bounding box, not a diagonal sphere.
	# Convert the world pinch point into the building frame and grow the box by a
	# small real-world margin (divided out of the total render scale so the reach
	# stays constant in metres regardless of how big the model is zoomed).
	var total_scale: float = _container.scale.x * _fit_scale
	var local: Vector3 = _mesh_holder.to_local(h.pos)
	var margin: float = _GRAB_MARGIN / maxf(total_scale, 0.0001)
	return _building_aabb.grow(margin).has_point(local)


func _scale_about(pivot: Vector3, ratio: float) -> void:
	var cur := _container.scale.x
	if cur < 0.0001:
		return
	var target := maxf(cur * ratio, _MANIP_MIN_SCALE)  # no upper cap - expand freely
	var eff := target / cur
	_container.global_position = pivot + (_container.global_position - pivot) * eff
	_container.scale = Vector3.ONE * target


func _rotate_about_y(pivot: Vector3, angle: float) -> void:
	if absf(angle) < 0.00001:
		return
	var offset := _container.global_position - pivot
	_container.global_position = pivot + offset.rotated(Vector3.UP, angle)
	_container.global_rotation.y += angle


# Signed yaw between two horizontal vectors. Negate if the map rotates the wrong way.
func _yaw_delta(prev_vec: Vector3, vec: Vector3) -> float:
	var a := Vector2(prev_vec.x, prev_vec.z)
	var b := Vector2(vec.x, vec.z)
	if a.length() < 0.0001 or b.length() < 0.0001:
		return 0.0
	return -a.angle_to(b)


# ── User marker ───────────────────────────────────────────────────────────────

func _add_user_marker() -> void:
	_user_marker = Node3D.new()
	_user_marker.name = "UserMarker"

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.25, 0.1)

	# Sphere body at the user's feet, in building metres (scaled with the model).
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	sphere.mesh = sm
	sphere.material_override = mat
	_user_marker.add_child(sphere)

	# Cone pointing along the user's heading.
	var cone := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = 0.16
	cm.height = 0.4
	cone.mesh = cm
	cone.material_override = mat
	cone.position = Vector3(0, 0, -0.3)
	cone.rotation = Vector3(-PI / 2.0, 0, 0)  # point toward -Z (marker forward)
	_user_marker.add_child(cone)

	_mesh_holder.add_child(_user_marker)
	_update_user_marker()


# The user's position and heading-yaw in the building (mesh_holder) frame.
func _user_building_pose() -> Dictionary:
	var offsets := _anchor_manager.get_space_offsets()
	var current_offset: Transform3D = offsets.get(_anchor_manager.get_current_space_id(), Transform3D.IDENTITY)
	var here := current_offset * _anchor_manager.world_to_glb(_camera.position)
	var fwd_local := -_camera.transform.basis.z
	fwd_local.y = 0.0
	var ahead_local: Vector3 = _camera.position + (fwd_local.normalized() if fwd_local.length() > 0.001 else Vector3.FORWARD) * 0.5
	var ahead := current_offset * _anchor_manager.world_to_glb(ahead_local)
	var heading := ahead - here
	heading.y = 0.0
	var yaw := atan2(heading.x, heading.z) if heading.length() > 0.001 else 0.0
	return {"here": here, "yaw": yaw}


func _update_user_marker() -> void:
	if not is_instance_valid(_user_marker) or not _camera or not _anchor_manager:
		return
	var pose := _user_building_pose()
	var here: Vector3 = pose.here
	_user_marker.position = here
	_user_marker.rotation = Vector3(0, pose.yaw, 0)

	# Follow mode centres the map on the user (marker sits at the origin and the
	# building scrolls around them); otherwise centre on the building's middle.
	if _mesh_holder:
		_mesh_holder.position = -here if _follow_mode else -_building_centre


func _process(delta: float) -> void:
	if _container and not _building:
		if not _follow_mode:        # in follow mode the map tracks the user, not the hands
			_update_manipulation()
		_update_follow(delta)
		_update_user_marker()


# ── Data / assets ─────────────────────────────────────────────────────────────

func _resolve_spaces() -> Array[Space]:
	var bsm := BuildingSessionManager.instance
	if bsm and not bsm.spaces.is_empty():
		_building_id = bsm.building_id
		return bsm.spaces
	if bsm and not bsm.building_id.is_empty():
		return await SupabaseManager.get_spaces_for_building(bsm.building_id)
	return []


func _load_space_scene(space: Space) -> Node:
	var bytes := await _glb_bytes(space)
	if bytes.is_empty():
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	var err := doc.append_from_buffer(bytes, "", state)
	if err != OK:
		push_warning("DollhouseMapManager: GLB parse failed for %s (err %d)" % [space.id, err])
		return null
	return doc.generate_scene(state)


# Decimated per-space GLB bytes, cached on-device keyed by id + updated_at so a
# re-scanned room invalidates its cache automatically. The scans are decimated
# server-side (/stitch/lowpoly) because quadric decimation is too heavy to run on
# the headset and the full-resolution meshes tank the framerate.
func _glb_bytes(space: Space) -> PackedByteArray:
	var path := "%s/%s_%d_%d.glb" % [_CACHE_DIR, space.id, space.updated_at.hash(), _TARGET_FACES]
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_bytes(path)

	var http := HTTPRequest.new()
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json"])
	if SupabaseManager.auth_user:
		headers.append("Authorization: Bearer " + SupabaseManager.auth_user.access_token)
	var body := JSON.stringify({"space_id": space.id, "target_faces": _TARGET_FACES})
	var send_err := http.request(_STITCH_API + "/stitch/lowpoly", headers, HTTPClient.METHOD_POST, body)
	if send_err != OK:
		push_warning("DollhouseMapManager: lowpoly request failed to start for %s (err %d)" % [space.id, send_err])
		http.queue_free()
		return PackedByteArray()

	var result: Array = await http.request_completed
	http.queue_free()
	var code: int = result[1]
	if code != 200:
		push_warning("DollhouseMapManager: lowpoly HTTP %d for %s" % [code, space.id])
		return PackedByteArray()
	var bytes: PackedByteArray = result[3]

	_prune_stale_cache(space.id, path)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_buffer(bytes)
		f.close()
	return bytes


func _prune_stale_cache(space_id: String, keep_path: String) -> void:
	var dir := DirAccess.open(_CACHE_DIR)
	if not dir:
		return
	var keep := keep_path.get_file()
	for file in dir.get_files():
		if file.begins_with(space_id + "_") and file != keep:
			dir.remove(file)


# Faux-lit shader so surfaces read clearly without depending on scene lights or
# mesh normals (passthrough has no useful lighting, and the decimated GLBs may
# ship without normals). The per-fragment geometric normal comes from screen-
# space derivatives of view-space position, shaded against a fixed light dir;
# the large decimated triangles flat-shade into distinct facets. Cheaper and more
# reliable in AR than real shadow-mapped lights.
#
# CULL_BACK culls the camera-facing surfaces so the near wall + ceiling drop away
# and the interior is revealed (matches this scan winding).
const _SCAN_SHADER := """
shader_type spatial;
render_mode cull_back, unshaded;

// Orientation-based lighting in WORLD space so it's stable as you walk/orbit and
// so surfaces are told apart by which way they face: floors catch the sky tone,
// ceilings fall into the ground tone, walls land in between. A key light adds
// form, a fresnel rim picks out edges. If floors/ceilings look inverted (scan
// winding flips the derived normal), negate nw.y.
uniform vec3 sky_color : source_color = vec3(0.55, 0.82, 1.0);
uniform vec3 ground_color : source_color = vec3(0.06, 0.10, 0.18);
uniform vec3 key_color : source_color = vec3(1.0, 0.96, 0.88);
uniform vec3 rim_color : source_color = vec3(0.3, 0.55, 0.8);
uniform float key_strength = 0.55;
uniform float rim_strength = 0.5;

// Nav-mode radial clip: in follow mode only a disc of the building around the user
// is shown so it doesn't block the view. clip_radius < 0 disables it. clip_center
// is the disc centre in world space (the user marker), distance measured in the
// horizontal plane so floors above/below aren't clipped by height.
uniform float clip_radius = -1.0;
uniform vec3 clip_center = vec3(0.0);
uniform float clip_feather = 0.15;   // fraction of the radius used to darken toward the rim

void fragment() {
	vec3 nv = normalize(cross(dFdx(VERTEX), dFdy(VERTEX)));      // geometric normal, view space
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);  // -> world space

	float edge = 1.0;
	if (clip_radius > 0.0) {
		vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float d = length(wpos.xz - clip_center.xz);
		if (d > clip_radius) discard;
		edge = 1.0 - smoothstep(clip_radius * (1.0 - clip_feather), clip_radius, d);
	}

	// Hemisphere ambient by surface orientation.
	float h = nw.y * 0.5 + 0.5;
	vec3 col = mix(ground_color, sky_color, h);

	// Key light from above-front.
	vec3 key_dir = normalize(vec3(0.3, 0.9, 0.35));
	col += key_color * (clamp(dot(nw, key_dir), 0.0, 1.0) * key_strength);

	// Fresnel rim for edge definition.
	float fres = pow(1.0 - clamp(dot(nv, normalize(-VERTEX)), 0.0, 1.0), 3.0);
	col += rim_color * (fres * rim_strength);

	ALBEDO = col * edge;   // darken toward the clip boundary for a soft falloff
}
"""


func _make_hologram_material() -> ShaderMaterial:
	var shader := Shader.new()
	shader.code = _SCAN_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	return mat


func _apply_material(node: Node, mat: Material) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for child in node.get_children():
		_apply_material(child, mat)
