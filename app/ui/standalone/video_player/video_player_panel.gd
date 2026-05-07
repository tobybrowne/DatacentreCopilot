class_name VideoPlayerPanel
extends BasePanel

# _PIN_STRIP_PX in ViewportPanel3D is 80 — controls must sit above that zone.
const PIN_STRIP_PX := 80.0
const CONTROLS_HEIGHT := 112.0

var _video_player: VideoStreamPlayer
var _play_pause_btn: Button
var _time_label: Label
var _seek_bar: HSlider
var _seeking: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(1280, 896)

	var bg := ColorRect.new()
	bg.color = Color(0.06, 0.06, 0.08, 1.0)
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# Close button pinned to top-right corner
	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(112, 112)
	close_btn.add_theme_font_size_override("font_size", BasePanel.FONT_BODY * 2)
	close_btn.anchor_left = 1.0
	close_btn.anchor_top = 0.0
	close_btn.anchor_right = 1.0
	close_btn.anchor_bottom = 0.0
	close_btn.offset_left = -128
	close_btn.offset_top = 16
	close_btn.offset_right = -16
	close_btn.offset_bottom = 128
	close_btn.z_index = 1
	_apply_square_btn_style(close_btn)
	close_btn.pressed.connect(func(): close_requested.emit())
	add_child(close_btn)

	# Video fills everything above the controls bar
	_video_player = VideoStreamPlayer.new()
	_video_player.anchor_left = 0.0
	_video_player.anchor_top = 0.0
	_video_player.anchor_right = 1.0
	_video_player.anchor_bottom = 1.0
	_video_player.offset_left = 0
	_video_player.offset_top = 0
	_video_player.offset_right = 0
	_video_player.offset_bottom = -(PIN_STRIP_PX + CONTROLS_HEIGHT)
	_video_player.expand = true
	_video_player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_video_player.finished.connect(_on_finished)
	add_child(_video_player)

	# Controls bar sits just above the pin strip
	var bar := ColorRect.new()
	bar.color = Color(0.10, 0.10, 0.14, 1.0)
	bar.anchor_left = 0.0
	bar.anchor_top = 1.0
	bar.anchor_right = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_left = 0
	bar.offset_top = -(PIN_STRIP_PX + CONTROLS_HEIGHT)
	bar.offset_right = 0
	bar.offset_bottom = -PIN_STRIP_PX
	add_child(bar)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	bar.add_child(margin)

	# Single row: [▶] [====seek====] [0:00 / 0:00]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 24)
	margin.add_child(row)

	_play_pause_btn = Button.new()
	_play_pause_btn.text = "▶"
	_play_pause_btn.custom_minimum_size = Vector2(88, 88)
	_play_pause_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_play_pause_btn.add_theme_font_size_override("font_size", BasePanel.FONT_BODY * 2)
	_apply_square_btn_style(_play_pause_btn)
	_play_pause_btn.pressed.connect(_on_play_pause)
	row.add_child(_play_pause_btn)

	_seek_bar = HSlider.new()
	_seek_bar.min_value = 0.0
	_seek_bar.max_value = 1.0
	_seek_bar.step = 0.001
	_seek_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seek_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_seek_bar.drag_started.connect(func(): _seeking = true)
	_seek_bar.drag_ended.connect(_on_seek_drag_ended)
	row.add_child(_seek_bar)

	_time_label = Label.new()
	_time_label.add_theme_font_size_override("font_size", BasePanel.FONT_SMALL * 2)
	_time_label.add_theme_color_override("font_color", BasePanel.COLOR_TEXT)
	_time_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_time_label.text = "--:-- / --:--"
	row.add_child(_time_label)


# data = { "path": "user://replay_video.ogv" }
func init(data: Dictionary) -> void:
	var path: String = data.get("path", "")
	if path.is_empty():
		return
	var stream := VideoStreamTheora.new()
	stream.file = path
	_video_player.stream = stream
	_video_player.play()
	_play_pause_btn.text = "■"


func _on_play_pause() -> void:
	if not _video_player.stream:
		return
	if not _video_player.is_playing() and not _video_player.paused:
		# video finished -- restart from the beginning
		_video_player.play()
		_play_pause_btn.text = "■"
	else:
		_video_player.paused = not _video_player.paused
		_play_pause_btn.text = "▶" if _video_player.paused else "■"


func _on_finished() -> void:
	_play_pause_btn.text = "▶"
	_seek_bar.set_value_no_signal(0.0)


func _on_seek_drag_ended(changed: bool) -> void:
	_seeking = false
	if changed:
		_video_player.stream_position = _seek_bar.value * _video_player.get_stream_length()


func _process(_delta: float) -> void:
	if not _video_player.is_playing():
		return
	var dur := _video_player.get_stream_length()
	var pos := _video_player.stream_position
	if dur > 0.0:
		_time_label.text = "%s / %s" % [_fmt_s(pos), _fmt_s(dur)]
		if not _seeking:
			_seek_bar.set_value_no_signal(pos / dur)


func _fmt_s(s: float) -> String:
	var si := int(s)
	return "%d:%02d" % [si / 60, si % 60]


func _apply_square_btn_style(btn: Button) -> void:
	var colors := {
		"normal":   Color(0.18, 0.18, 0.26, 0.9),
		"hover":    Color(0.25, 0.25, 0.36, 0.9),
		"pressed":  Color(0.30, 0.30, 0.48, 0.9),
		"disabled": Color(0.14, 0.14, 0.20, 0.6),
		"focus":    Color(0.18, 0.18, 0.26, 0.9),
	}
	for state in colors:
		var s := StyleBoxFlat.new()
		s.bg_color = colors[state]
		s.set_corner_radius_all(12)
		s.set_content_margin_all(0)
		btn.add_theme_stylebox_override(state, s)


func _exit_tree() -> void:
	if _video_player and _video_player.is_playing():
		_video_player.stop()
