class_name WifiIndicator
extends Node3D

const _POSITION     := Vector3(0.098, 0.07, -0.3)
const _POLL_INTERVAL := 5.0

const _BAR_WIDTH   := 0.0025
const _BAR_DEPTH   := 0.002
const _BAR_HEIGHTS := [0.003, 0.005, 0.007]
const _BAR_SPACING := 0.004  # center-to-center

var _bars: Array[MeshInstance3D] = []
var _mats: Array[StandardMaterial3D] = []
var _poll_timer := _POLL_INTERVAL  # poll immediately on first frame


func _ready() -> void:
	position = _POSITION
	_build_bars()


func _process(delta: float) -> void:
	_poll_timer += delta
	if _poll_timer >= _POLL_INTERVAL:
		_poll_timer = 0.0
		_set_level(_read_wifi_level())


# ── Build ─────────────────────────────────────────────────────────────────────

func _build_bars() -> void:
	var max_h: float = _BAR_HEIGHTS[_BAR_HEIGHTS.size() - 1]
	for i in _BAR_HEIGHTS.size():
		var h: float = _BAR_HEIGHTS[i]
		var box := BoxMesh.new()
		box.size = Vector3(_BAR_WIDTH, h, _BAR_DEPTH)

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color  = Color(0.5, 0.5, 0.5)

		var mi := MeshInstance3D.new()
		mi.mesh = box
		mi.material_override = mat
		# align all bar bottoms, centering the group vertically on this node
		mi.position = Vector3(
			(i - 1) * _BAR_SPACING,
			-max_h * 0.5 + h * 0.5,
			0.0
		)
		add_child(mi)
		_bars.append(mi)
		_mats.append(mat)


# ── Display ───────────────────────────────────────────────────────────────────

func _set_level(level: int) -> void:
	# level: -1 unknown, 0 none, 1 poor, 2 fair, 3 good
	const _COLORS := [
		Color(1.0, 0.2, 0.2),   # 0 poor
		Color(1.0, 0.55, 0.0),  # 1 fair
		Color(0.0, 1.0, 0.2),   # 2 good
		Color(0.0, 1.0, 0.2),   # 3 excellent
	]
	for i in _bars.size():
		if level < 0:
			_mats[i].albedo_color = Color(0.5, 0.5, 0.5)
		elif i < level:
			_mats[i].albedo_color = _COLORS[clampi(level - 1, 0, 3)]
		else:
			_mats[i].albedo_color = Color(0.2, 0.2, 0.2)


# ── Signal reading ────────────────────────────────────────────────────────────

func _read_wifi_level() -> int:
	var rssi := _read_rssi_dbm()
	if rssi <= -999:
		return -1
	if rssi >= -60:
		return 3
	if rssi >= -70:
		return 2
	if rssi >= -85:
		return 1
	return 0


# Reads RSSI from the kernel's /proc/net/wireless (no permissions required).
# Returns dBm value, or -999 on failure.
func _read_rssi_dbm() -> int:
	var f := FileAccess.open("/proc/net/wireless", FileAccess.READ)
	if not f:
		return -999
	f.get_line()  # header line 1
	f.get_line()  # header line 2
	var line := f.get_line()
	f.close()
	if line.is_empty():
		return -999

	# Format: " wlan0: 0000   70.  -41.  -256. ..."
	# tokens[0]=iface, [1]=status, [2]=link, [3]=level, [4]=noise, ...
	var tokens: PackedStringArray = []
	for t: String in line.split(" "):
		var s := t.strip_edges()
		if not s.is_empty():
			tokens.append(s)

	if tokens.size() < 4:
		return -999

	var rssi := tokens[3].rstrip(".").to_int()
	# Some kernels report level as an unsigned byte offset from -256
	if rssi > 0:
		rssi -= 256
	return rssi
