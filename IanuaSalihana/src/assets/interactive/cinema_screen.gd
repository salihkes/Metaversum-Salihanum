extends MeshInstance3D

## CinemaScreen.gd
## Displays streamed video (and audio) from a WebSocket server
## Default URL matches the Python media streamer at 127.0.0.1:3245.

@export var websocket_url: String = "ws://127.0.0.1:3245"

# WebSocket client
var _client := WebSocketPeer.new()
var _connected := false

# Texture for displaying the video
var _texture: ImageTexture
var _image := Image.new()
var _texture_initialized := false
var _frame_count := 0

# --- Audio: Using AudioStreamGenerator for streamed audio ---
var _audio_player_3d: AudioStreamPlayer3D
var _audio_generator := AudioStreamGenerator.new()
var _audio_playback: AudioStreamGeneratorPlayback
var _audio_buffer_size_ms := 1000 # Reasonably large for network jitter

# WAV / PCM assumptions (must match the Python side)
const WAV_HEADER_SIZE := 44
const AUDIO_CHANNELS := 2
const AUDIO_SAMPLE_RATE := 48000
const AUDIO_BITS_PER_SAMPLE := 16

# Spatial audio defaults
@export var volume_db := 0.0
@export var max_distance := 30.0
@export var attenuation_model := 0 # ATTENUATION_INVERSE_DISTANCE
@export var unit_size := 10.0


func _ready() -> void:
	print("CinemaScreen: initializing WebSocket media receiver...")

	# --- Set up 3D audio player ---
	_audio_player_3d = AudioStreamPlayer3D.new()
	add_child(_audio_player_3d)

	_audio_player_3d.volume_db = volume_db
	_audio_player_3d.max_distance = max_distance
	_audio_player_3d.attenuation_model = attenuation_model
	_audio_player_3d.unit_size = unit_size
	_audio_player_3d.max_db = 3.0

	_audio_player_3d.emission_angle_enabled = true
	_audio_player_3d.emission_angle_degrees = 90.0
	_audio_player_3d.emission_angle_filter_attenuation_db = -12.0
	_audio_player_3d.attenuation_filter_cutoff_hz = 5000.0
	_audio_player_3d.attenuation_filter_db = -24.0
	_audio_player_3d.doppler_tracking = 0

	# Audio generator setup
	_audio_generator.mix_rate = AUDIO_SAMPLE_RATE
	_audio_generator.buffer_length = float(_audio_buffer_size_ms) / 1000.0
	_audio_player_3d.stream = _audio_generator
	_audio_player_3d.play()
	_audio_playback = _audio_player_3d.get_stream_playback()
	if _audio_playback == null:
		printerr("CinemaScreen: Failed to get AudioStreamGeneratorPlayback.")
	else:
		print("CinemaScreen: AudioStreamGenerator ready at ", AUDIO_SAMPLE_RATE, " Hz")

	# --- WebSocket configuration ---
	_client.encode_buffer_max_size = 160000000
	_client.outbound_buffer_size = 160000000
	_client.inbound_buffer_size = 160000000

	var err := _client.connect_to_url(websocket_url)
	if err != OK:
		printerr("CinemaScreen: Unable to connect to WebSocket server at ", websocket_url)
		return

	# --- Material / mesh setup ---
	if mesh:
		print("CinemaScreen: Mesh has ", mesh.get_surface_count(), " surfaces")
	else:
		print("CinemaScreen: WARNING - No mesh set on MeshInstance3D")

	if get_surface_override_material(0) == null:
		var material := StandardMaterial3D.new()
		material.flags_transparent = false
		material.flags_unshaded = true
		material.emission_enabled = true
		material.emission_energy_multiplier = 1.5
		set_surface_override_material(0, material)
		print("CinemaScreen: Created new material on surface 0")
	else:
		var existing_material := get_surface_override_material(0)
		existing_material.flags_transparent = false
		existing_material.flags_unshaded = true
		existing_material.emission_enabled = true
		existing_material.emission_energy_multiplier = 1.5
		print("CinemaScreen: Using existing material on surface 0")


func _process(delta: float) -> void:
	_client.poll()

	var state := _client.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			print("CinemaScreen: Connected to WebSocket server at ", websocket_url)
			_connected = true

		while _client.get_available_packet_count() > 0:
			var packet = _client.get_packet()
			if packet is String:
				_parse_message(packet)
			elif packet is PackedByteArray:
				var msg_text: String = (packet as PackedByteArray).get_string_from_utf8()
				_parse_message(msg_text)

	elif state == WebSocketPeer.STATE_CLOSING:
		_connected = false
	elif state == WebSocketPeer.STATE_CLOSED:
		if _connected:
			var code := _client.get_close_code()
			var reason := _client.get_close_reason()
			print("CinemaScreen: WebSocket closed. Code: %d, reason: %s" % [code, reason])
		_connected = false

		# Simple reconnect logic
		await get_tree().create_timer(5.0).timeout
		var err := _client.connect_to_url(websocket_url)
		if err != OK:
			printerr("CinemaScreen: Reconnect failed to ", websocket_url)


func _parse_message(msg_text) -> void:
	var json := JSON.new()
	var parse_result := json.parse(msg_text)
	if parse_result != OK:
		printerr("CinemaScreen: Failed to parse JSON: ", json.get_error_message(), " at line ", json.get_error_line())
		return

	var data = json.get_data()
	if not (data is Dictionary):
		return

	if data.has("type") and data.type == "media_chunk":
		if data.has("audio_data"):
			_handle_simple_audio(data.audio_data)
		if data.has("video_data") and data.video_data != "":
			_handle_video_frame(data.video_data)
		elif not data.has("audio_data"):
			printerr("CinemaScreen: media_chunk missing both audio and video data.")


func _handle_video_frame(base64_video_data: String) -> void:
	var image_data := Marshalls.base64_to_raw(base64_video_data)
	var err := _image.load_jpg_from_buffer(image_data)
	if err != OK:
		printerr("CinemaScreen: Failed to load video frame image from buffer: ", err)
		return

	_frame_count += 1

	if not _texture_initialized:
		_texture = ImageTexture.create_from_image(_image)
		_texture_initialized = true
		var material := get_surface_override_material(0)
		if material:
			material.albedo_texture = _texture
			material.emission_texture = _texture
			print("CinemaScreen: Applied texture to material (", _image.get_width(), "x", _image.get_height(), ")")
	else:
		if _texture and _texture.get_width() == _image.get_width() and _texture.get_height() == _image.get_height():
			_texture.update(_image)
		else:
			_texture = ImageTexture.create_from_image(_image)
			var mat := get_surface_override_material(0)
			if mat:
				mat.albedo_texture = _texture
				mat.emission_texture = _texture


func _handle_simple_audio(base64_audio_data: String) -> void:
	if _audio_playback == null:
		_audio_playback = _audio_player_3d.get_stream_playback()
		if _audio_playback == null:
			printerr("CinemaScreen: Audio playback is null; cannot push frames.")
			return

	var audio_data := Marshalls.base64_to_raw(base64_audio_data)

	if audio_data.size() <= WAV_HEADER_SIZE:
		return

	var pcm_data := audio_data.slice(WAV_HEADER_SIZE)
	var pcm_data_len := pcm_data.size()

	var bytes_per_frame := AUDIO_CHANNELS * (AUDIO_BITS_PER_SAMPLE / 8)
	if bytes_per_frame == 0:
		printerr("CinemaScreen: Invalid bytes_per_frame calculation.")
		return

	var frame_count := pcm_data_len / bytes_per_frame
	if frame_count == 0:
		return

	var available_frames := _audio_playback.get_frames_available()
	if frame_count > available_frames:
		# We may overrun the buffer slightly; acceptable for streaming.
		pass

	var byte_index := 0
	for i in range(frame_count):
		if byte_index + 3 >= pcm_data_len:
			break

		var left_sample_int := pcm_data.decode_s16(byte_index)
		var right_sample_int := pcm_data.decode_s16(byte_index + 2)
		byte_index += 4

		var left_sample_float := float(left_sample_int) / 32768.0
		var right_sample_float := float(right_sample_int) / 32768.0

		var frame := Vector2(left_sample_float, right_sample_float)
		_audio_playback.push_frame(frame)


func set_audio_properties(new_volume_db: float, new_max_distance: float, new_attenuation_model: int) -> void:
	volume_db = new_volume_db
	max_distance = new_max_distance
	attenuation_model = new_attenuation_model

	if _audio_player_3d:
		_audio_player_3d.volume_db = volume_db
		_audio_player_3d.max_distance = max_distance
		_audio_player_3d.attenuation_model = attenuation_model


func _exit_tree() -> void:
	if _client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_client.close()
		print("CinemaScreen: WebSocket connection closed on exit.")
