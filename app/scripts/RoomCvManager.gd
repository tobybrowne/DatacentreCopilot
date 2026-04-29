# Not currently used, experimental script for room recognition via CV.

extends Node

const SERVICE_URL := "https://room-finder.tobybrowne.co.uk/jobs/room-inference"

var _http: HTTPRequest
var _label: Label

func _ready() -> void:
	_http = HTTPRequest.new()
	add_child(_http)
	_http.request_completed.connect(_on_request_completed)

	var cv_camera = get_node_or_null("/root/Main/XROrigin3D/CVCameraManager")
	if cv_camera:
		cv_camera.frame_captured.connect(_on_frame_captured)
	else:
		push_warning("LocationManager: CVCameraManager not found")

func _on_frame_captured(image: Image) -> void:
	var jpeg := image.save_jpg_to_buffer()
	if jpeg.is_empty():
		push_error("LocationManager: failed to encode JPEG")
		return

	# build multipart/form-data body
	var boundary := "boundary%d" % Time.get_unix_time_from_system()
	var body := PackedByteArray()
	body.append_array(("--%s\r\n" % boundary).to_utf8_buffer())
	body.append_array("Content-Disposition: form-data; name=\"file\"; filename=\"frame.jpg\"\r\n".to_utf8_buffer())
	body.append_array("Content-Type: image/jpeg\r\n\r\n".to_utf8_buffer())
	body.append_array(jpeg)
	body.append_array(("\r\n--%s--\r\n" % boundary).to_utf8_buffer())

	var headers := [
		"Content-Type: multipart/form-data; boundary=%s" % boundary,
		"Content-Length: %d" % body.size(),
	]

	var err := _http.request_raw(SERVICE_URL, headers, HTTPClient.METHOD_POST, body)
	if err != OK:
		push_error("LocationManager: request failed to send (err %d)" % err)


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		push_error("LocationManager: request failed — result=%d code=%d" % [result, response_code])
		return

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		push_error("LocationManager: failed to parse response JSON")
		return

	var data: Dictionary = json.get_data()
	var room: String = data.get("result", {}).get("predicted_room", "unknown")

	if not _label:
		var space_label_3d = get_node_or_null("../SpaceLabel")
		if space_label_3d and space_label_3d.get_panel():
			_label = space_label_3d.get_panel().get_node_or_null("MarginContainer/Label")
		if not _label:
			push_warning("LocationManager: could not find SpaceLabel label node")
			return

	_label.text = room
