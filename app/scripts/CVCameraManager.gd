extends Node

# Camera ID 0 is the ML2 main RGB camera (autofocus) - sharper general-purpose
# images. Camera ID 1 is the CV (computer vision) camera - wide-angle, fixed focus,
# optimised for close-range feature tracking but soft at normal distances. Switch
# the ID in CVCameraPlugin.kt to change which camera is opened.

const SAVE_DIR := "user://cv_frames/"
const VIDEO_DIR := "user://cv_videos/"

@export var auto_capture: bool = false
@export var capture_interval: float = 2.0

signal frame_captured(image: Image)
signal recording_started
signal recording_stopped(path: String)

var _cv_camera = null
var _timer: Timer

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(VIDEO_DIR))

	if not Engine.has_singleton("CVCamera"):
		push_warning("CVCamera plugin not available")
		return

	print("CVCamera: initializing")

	_cv_camera = Engine.get_singleton("CVCamera")
	_cv_camera.camera_opened.connect(_on_camera_opened)
	_cv_camera.camera_closed.connect(_on_camera_closed)
	_cv_camera.camera_error.connect(_on_camera_error)
	_cv_camera.frame_available.connect(_on_frame_available)
	_cv_camera.recording_started.connect(_on_recording_started)
	_cv_camera.recording_stopped.connect(_on_recording_stopped)

	OS.request_permissions()
	_cv_camera.openCamera(4096, 3072) # upto 4096x3072


func _on_camera_opened() -> void:
	print("CVCamera: ready, saving frames to %s" % ProjectSettings.globalize_path(SAVE_DIR))

	_cv_camera.setNoiseReduction(true)
	# _cv_camera.setExposure(2.0, 1600)

	if auto_capture and _timer == null:
		_timer = Timer.new()
		_timer.wait_time = capture_interval
		_timer.autostart = true
		_timer.timeout.connect(func(): _cv_camera.captureFrame())
		add_child(_timer)
		_cv_camera.captureFrame()

# One-shot capture: triggers a single frame and awaits the decoded Image
# (the same 640x480 image emitted by frame_captured). Returns null if the plugin
# is unavailable (e.g. desktop simulator).
func capture_frame() -> Image:
	if not _cv_camera:
		push_warning("CVCamera: plugin not available")
		return null
	_cv_camera.captureFrame()
	return await frame_captured


func _on_frame_available(data: PackedByteArray) -> void:
	var image := Image.new()
	var err := image.load_jpg_from_buffer(data)
	if err != OK:
		push_error("CVCamera: failed to decode JPEG: %d" % err)
		return

	var filename := SAVE_DIR + "frame_%d.jpg" % Time.get_unix_time_from_system()
	err = image.save_jpg(filename)
	if err != OK:
		push_error("CVCamera: failed to save %s: %d" % [filename, err])
	else:
		print("CVCamera: saved %s" % filename)

	image.resize(640, 480, Image.INTERPOLATE_BILINEAR)
	frame_captured.emit(image)

# width/height default to 1920x1080; the CV camera supports up to 4096x3072 but
# high resolutions may not be supported by all MediaRecorder encoder profiles.
func start_recording(width: int = 1920, height: int = 1080) -> void:
	if not _cv_camera:
		push_warning("CVCamera: plugin not available")
		return
	var filename := ProjectSettings.globalize_path(
		VIDEO_DIR + "video_%d.mp4" % Time.get_unix_time_from_system()
	)
	print("CVCamera: starting recording to %s" % filename)
	_cv_camera.startRecording(filename, width, height)

func stop_recording() -> void:
	if _cv_camera:
		_cv_camera.stopRecording()

func _on_recording_started() -> void:
	print("CVCamera: recording started")
	recording_started.emit()

func _on_recording_stopped(path: String) -> void:
	print("CVCamera: recording saved to %s" % path)
	recording_stopped.emit(path)

func _on_camera_closed() -> void:
	print("CVCamera: closed")

func _on_camera_error(code: int) -> void:
	push_error("CVCamera: error code %d" % code)

func _exit_tree() -> void:
	if _cv_camera:
		_cv_camera.closeCamera()
