extends Node

signal function_called(name: String, call_id: String, args: Dictionary)
signal transcript_received(role: String, text: String)
signal status_changed(state: String)
signal connected
signal disconnected

@export var service_url := "wss://room-finder.tobybrowne.co.uk/copilot/ws"
@export var instructions := "You are a helpful AR assistant."
@export var send_interval_ms := 100
@export var playback_volume_db := 16.0

var tools: Array = []

var _ws := WebSocketPeer.new()
var _mic_player: AudioStreamPlayer
var _capture: AudioEffectCapture
var _playback_player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback

var _engine_rate: float
var _target_rate := 24000.0
var _mic_buffer := PackedByteArray()
var _playback_queue := PackedVector2Array()

var _send_timer := 0.0
var _is_connected := false

const _CHUNK_BYTES := 4800  # 100ms @ 24kHz mono PCM16


func _ready() -> void:
	_engine_rate = float(AudioServer.get_mix_rate())
	_setup_mic()
	_setup_playback()
	_ws.connect_to_url(service_url)


func _setup_mic() -> void:
	AudioServer.add_bus()
	var bus_idx := AudioServer.bus_count - 1
	AudioServer.set_bus_name(bus_idx, "CopilotMic")
	AudioServer.set_bus_mute(bus_idx, true)

	_capture = AudioEffectCapture.new()
	_capture.buffer_length = 0.5
	AudioServer.add_bus_effect(bus_idx, _capture)

	_mic_player = AudioStreamPlayer.new()
	_mic_player.stream = AudioStreamMicrophone.new()
	_mic_player.bus = "CopilotMic"
	add_child(_mic_player)
	_mic_player.play()


func _setup_playback() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _target_rate
	gen.buffer_length = 0.1

	_playback_player = AudioStreamPlayer.new()
	_playback_player.stream = gen
	_playback_player.volume_db = playback_volume_db
	add_child(_playback_player)
	_playback_player.play()
	_playback = _playback_player.get_stream_playback()


func _process(delta: float) -> void:
	_ws.poll()

	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			if not _is_connected:
				_is_connected = true
				_on_ws_connected()
			_receive_messages()
			_drain_playback_queue()
			_send_timer += delta
			if _send_timer >= send_interval_ms / 1000.0:
				_send_timer = 0.0
				_capture_and_send()

		WebSocketPeer.STATE_CLOSED:
			if _is_connected:
				_is_connected = false
				disconnected.emit()


func _on_ws_connected() -> void:
	print("CopilotManager: connected")
	connected.emit()
	_send_session_update()


func _send_session_update() -> void:
	var session := {
		"modalities": ["text", "audio"],
		"instructions": instructions,
		"input_audio_format": "pcm16",
		"output_audio_format": "pcm16",
		"turn_detection": {
			"type": "server_vad",
			"threshold": 0.5,
			"silence_duration_ms": 600,
			"prefix_padding_ms": 300,
		},
		"input_audio_transcription": {"model": "whisper-1"},
		"tools": tools,
		"tool_choice": "auto" if tools.size() > 0 else "none",
	}
	_send({"type": "session_update", "session": session})


func _capture_and_send() -> void:
	var available := _capture.get_frames_available()
	if available <= 0:
		return

	var frames := _capture.get_buffer(available)
	_mic_buffer.append_array(_resample_to_pcm16(frames))

	while _mic_buffer.size() >= _CHUNK_BYTES:
		var chunk := _mic_buffer.slice(0, _CHUNK_BYTES)
		_mic_buffer = _mic_buffer.slice(_CHUNK_BYTES)
		_send({"type": "audio", "data": Marshalls.raw_to_base64(chunk)})


func _resample_to_pcm16(frames: PackedVector2Array) -> PackedByteArray:
	var ratio := _engine_rate / _target_rate
	var out_len := int(frames.size() / ratio)
	var result := PackedByteArray()
	result.resize(out_len * 2)

	for i in range(out_len):
		var src_pos := i * ratio
		var src_idx := int(src_pos)
		var frac := src_pos - src_idx
		var next_idx := mini(src_idx + 1, frames.size() - 1)
		var s0 := (frames[src_idx].x + frames[src_idx].y) * 0.5
		var s1 := (frames[next_idx].x + frames[next_idx].y) * 0.5
		var mono := s0 * (1.0 - frac) + s1 * frac
		var sample: int = int(clamp(mono, -1.0, 1.0) * 32767.0)
		if sample < 0:
			sample += 65536
		result[i * 2] = sample & 0xFF
		result[i * 2 + 1] = (sample >> 8) & 0xFF

	return result


func _receive_messages() -> void:
	while _ws.get_available_packet_count() > 0:
		var pkt := _ws.get_packet()
		var msg: Variant = JSON.parse_string(pkt.get_string_from_utf8())
		if not msg is Dictionary:
			continue
		_handle_message(msg)


func _handle_message(msg: Dictionary) -> void:
	var t: String = msg.get("type", "")
	match t:
		"audio":
			_queue_audio(msg["data"])
		"function_call":
			print("CopilotManager: function_call %s args=%s" % [msg["name"], msg["args"]])
			function_called.emit(msg["name"], msg["call_id"], msg["args"])
		"transcript":
			print("CopilotManager: [%s] %s" % [msg["role"], msg["text"]])
			transcript_received.emit(msg["role"], msg["text"])
		"status":
			print("CopilotManager: status → %s" % msg["state"])
			status_changed.emit(msg["state"])
		"error":
			push_warning("CopilotManager: %s" % msg.get("message", ""))


func _queue_audio(b64: String) -> void:
	var bytes := Marshalls.base64_to_raw(b64)
	var frame_count := bytes.size() / 2
	var new_frames := PackedVector2Array()
	new_frames.resize(frame_count)
	for i in range(frame_count):
		var lo: int = bytes[i * 2]
		var hi: int = bytes[i * 2 + 1]
		var s: int = lo | (hi << 8)
		if s >= 32768:
			s -= 65536
		new_frames[i] = Vector2(float(s) / 32768.0, float(s) / 32768.0)
	_playback_queue.append_array(new_frames)


func _drain_playback_queue() -> void:
	if _playback_queue.is_empty():
		return
	var space := _playback.get_frames_available()
	if space <= 0:
		return
	var to_push := mini(space, _playback_queue.size())
	_playback.push_buffer(_playback_queue.slice(0, to_push))
	_playback_queue = _playback_queue.slice(to_push)


func _send(msg: Dictionary) -> void:
	_ws.send_text(JSON.stringify(msg))


# --- Public API ---

func update_tools(new_tools: Array) -> void:
	tools = new_tools
	if _is_connected:
		_send_session_update()


func update_instructions(new_instructions: String) -> void:
	instructions = new_instructions
	if _is_connected:
		_send_session_update()


func inject_context(text: String) -> void:
	if _is_connected:
		_send({"type": "inject_context", "text": text})


func send_function_output(call_id: String, output: String) -> void:
	if _is_connected:
		_send({"type": "function_output", "call_id": call_id, "output": output})
