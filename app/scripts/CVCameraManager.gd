extends Node

# Camera ID 1 is the ML2 CV (computer vision) camera — wide-angle, fixed focus,
# optimised for close-range feature tracking. Images will appear soft/out of focus
# at normal distances. For sharper general-purpose images use camera ID 0 (main RGB
# camera with autofocus), but that requires changing the ID in CVCameraPlugin.kt.

const SAVE_DIR := "user://cv_frames/"

signal frame_captured(image: Image)

var _cv_camera = null
var _timer: Timer

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))

	if not Engine.has_singleton("CVCamera"):
		push_warning("CVCamera plugin not available")
		return

	print("CVCamera: initializing")

	_cv_camera = Engine.get_singleton("CVCamera")
	_cv_camera.camera_opened.connect(_on_camera_opened)
	_cv_camera.camera_closed.connect(_on_camera_closed)
	_cv_camera.camera_error.connect(_on_camera_error)
	_cv_camera.frame_available.connect(_on_frame_available)

	OS.request_permissions()
	_cv_camera.openCamera(4096, 3072) # upto 4096x3072
	

func _on_camera_opened() -> void:
	print("CVCamera: ready, saving frames to %s" % ProjectSettings.globalize_path(SAVE_DIR))

	_cv_camera.setNoiseReduction(true)  
	# _cv_camera.setExposure(2.0, 1600)


	_timer = Timer.new()
	_timer.wait_time = 2.0
	_timer.autostart = true
	_timer.timeout.connect(func(): _cv_camera.captureFrame())
	add_child(_timer)
	_cv_camera.captureFrame()

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

func _on_camera_closed() -> void:
	print("CVCamera: closed")

func _on_camera_error(code: int) -> void:
	push_error("CVCamera: error code %d" % code)

func _exit_tree() -> void:
	if _cv_camera:
		_cv_camera.closeCamera()
