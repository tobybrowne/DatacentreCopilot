class_name LogsController3D
extends Node3D

## Self-contained logs fab + browser + replay lifecycle.
## Add as a child of XROrigin3D. All panels are spawned as siblings (also
## children of XROrigin3D) so ViewportPanel3D ray/poke input works correctly.
##
## Set properties before add_child, then call refresh() each time the context
## changes (e.g. step changed) and play_log_id() for direct step-viewer replay.

const _FAB_SCENE     := preload("res://ui/standalone/logs_fab/logs_fab_3d.tscn")
const _BROWSER_SCENE := preload("res://ui/standalone/log_browser/log_browser_panel_3d.tscn")
const _VIDEO_SCENE   := preload("res://ui/standalone/video_player/video_player_panel_3d.tscn")

## Emitted whenever a replayer stops — natural end or explicit stop.
## Connect to reset the step-viewer replay button.
signal replay_ended

## Set before add_child to pin the fab at a world position instead of floating.
var world_anchored_fab := false
var fab_local_pos      := Vector3.ZERO

## Override to avoid temp-file collisions when multiple controllers are active.
var video_tmp_path := "user://replay_video.ogv"

var _fab_3d:        ViewportPanel3D = null
var _browser_3d:    ViewportPanel3D = null
var _video_3d:      ViewportPanel3D = null
var _replayer:      PoseReplayer    = null
var _replay_loading := false
var _init_data:     Dictionary      = {}


func _ready() -> void:
	_fab_3d = _FAB_SCENE.instantiate()
	if world_anchored_fab:
		_fab_3d.world_anchored = true
		_fab_3d.position = fab_local_pos
	get_parent().add_child(_fab_3d)
	var fab := _fab_3d.get_panel() as LogsFab
	if fab:
		fab.logs_requested.connect(_on_fab_pressed)
	tree_exiting.connect(_cleanup)


## Re-initialise the browser context (e.g. on step change). If the browser is
## open it reloads in-place; otherwise the context is stored for when it opens.
func refresh(init_data: Dictionary) -> void:
	_init_data = init_data
	stop()
	if _browser_3d:
		var panel := _browser_3d.get_panel() as LogBrowserPanel
		if panel:
			panel.init(_init_data)


## Direct replay of a specific log without opening the browser (step-viewer button).
func play_log_id(log_id: String) -> void:
	if _replay_loading or log_id.is_empty():
		return
	_replay_loading = true
	stop()
	var task = await Supabase.database.query(
		SupabaseQuery.new()
			.from("logs")
			.select(["geometry_recording_path", "camera_recording_path_ogv"])
			.eq("id", log_id)
			.range(0, 0)
	).completed
	if task.error != null or task.data == null or task.data.is_empty():
		_replay_loading = false
		return
	var row: Dictionary = task.data[0]
	var geo: String = row.get("geometry_recording_path", "") if row.get("geometry_recording_path") != null else ""
	var ogv: String = row.get("camera_recording_path_ogv", "") if row.get("camera_recording_path_ogv") != null else ""
	await _play_paths(geo, ogv, true)
	_replay_loading = false


## Stop any active replay/video without closing the browser.
func stop() -> void:
	_stop_replayer()
	_stop_video()


## Close the browser and stop everything.
func close() -> void:
	stop()
	_close_browser()


# ── Internal ──────────────────────────────────────────────────────────────────

func _on_fab_pressed() -> void:
	if _browser_3d:
		close()
		return
	if _init_data.is_empty():
		return
	_browser_3d = _BROWSER_SCENE.instantiate()
	get_parent().add_child(_browser_3d)
	var panel := _browser_3d.get_panel() as LogBrowserPanel
	if panel:
		panel.play_requested.connect(_on_play_requested)
		panel.stop_requested.connect(_on_stop_requested)
		panel.init(_init_data)


func _on_play_requested(_log_id: String, geo_path: String, ogv_path: String) -> void:
	if _replay_loading:
		return
	_replay_loading = true
	stop()
	var started := await _play_paths(geo_path, ogv_path, false)
	var panel := _browser_3d.get_panel() as LogBrowserPanel if _browser_3d else null
	if panel:
		if started:
			panel.notify_playback_started()
		else:
			panel.notify_playback_finished()
	_replay_loading = false


func _on_stop_requested() -> void:
	_replay_loading = false
	stop()


func _on_playback_finished() -> void:
	_replayer = null
	var panel := _browser_3d.get_panel() as LogBrowserPanel if _browser_3d else null
	if panel:
		panel.notify_playback_finished()
	replay_ended.emit()


func _play_paths(geo_path: String, ogv_path: String, loop: bool) -> bool:
	var started := false

	if not geo_path.is_empty():
		var dl = await Supabase.storage.from("log_bucket").download(geo_path, "", true).completed
		if dl.error != null:
			push_warning("LogsController3D: geo download failed — %s" % dl.error.message)
		else:
			var frames := PoseRec.frames_from_bytes(dl.data)
			if not frames.is_empty():
				var lm := get_parent().get_node_or_null("LocationManager") as LocationManager
				_replayer = PoseReplayer.new()
				_replayer.skeleton_enabled = true
				get_parent().add_child(_replayer)
				_replayer.global_transform = lm.get_calibration() if lm else Transform3D.IDENTITY
				_replayer.playback_finished.connect(_on_playback_finished)
				_replayer.play(frames, loop)
				started = true

	if not ogv_path.is_empty():
		var vdl = await Supabase.storage.from("log_bucket").download(ogv_path, "", true).completed
		if vdl.error != null:
			push_warning("LogsController3D: video download failed — %s" % vdl.error.message)
		else:
			_launch_video(vdl.data)
			started = true

	return started


func _stop_replayer() -> void:
	if _replayer:
		_replayer.queue_free()
		_replayer = null
		var panel := _browser_3d.get_panel() as LogBrowserPanel if _browser_3d else null
		if panel:
			panel.notify_playback_finished()
		replay_ended.emit()


func _stop_video() -> void:
	if _video_3d:
		_video_3d.queue_free()
		_video_3d = null
	if FileAccess.file_exists(video_tmp_path):
		DirAccess.remove_absolute(video_tmp_path)


func _close_browser() -> void:
	if _browser_3d:
		_browser_3d.queue_free()
		_browser_3d = null


func _launch_video(data: PackedByteArray) -> void:
	var f := FileAccess.open(video_tmp_path, FileAccess.WRITE)
	if not f:
		return
	f.store_buffer(data)
	f.close()
	_video_3d = _VIDEO_SCENE.instantiate()
	get_parent().add_child(_video_3d)
	var vp := _video_3d.get_panel() as VideoPlayerPanel
	if vp:
		vp.close_requested.connect(_stop_video)
		vp.init({"path": video_tmp_path})


func _cleanup() -> void:
	stop()
	_close_browser()
	if _fab_3d:
		_fab_3d.queue_free()
		_fab_3d = null
