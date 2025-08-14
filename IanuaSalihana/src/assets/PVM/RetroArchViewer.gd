extends MeshInstance3D

# WebSocket client
var _client = WebSocketPeer.new()
var _connected = false

# Texture for displaying the video
var _texture = null
var _image = Image.new()
var _texture_initialized = false
var _frame_count = 0

# --- Audio Refactor: Using AudioStreamGenerator ---
var _audio_player_3d = null
var _audio_generator = AudioStreamGenerator.new()
var _audio_playback = null # To store the AudioStreamGeneratorPlayback object
var _audio_buffer_size_ms = 1000 # Keep buffer reasonably large for network jitter

# Assuming standard WAV header size for PCM
const WAV_HEADER_SIZE = 44
# Assuming format from previous context
const AUDIO_CHANNELS = 2
const AUDIO_SAMPLE_RATE = 48000 # Make sure this matches extracted audio
const AUDIO_BITS_PER_SAMPLE = 16
# --- End Audio Refactor ---

# Spatial audio settings
var _max_distance = 30.0
var _attenuation_model = 0  # ATTENUATION_INVERSE_DISTANCE
var _volume_db = 0.0
var _unit_size = 10.0

# Debug flag (can be removed later)
# var _saved_first_chunk = false # Less relevant now

func _ready():
	print("MediaReceiver initializing...")
	
	# Set up 3D audio player
	_audio_player_3d = AudioStreamPlayer3D.new()
	add_child(_audio_player_3d)
	
	# Configure 3D audio properties
	_audio_player_3d.volume_db = _volume_db
	_audio_player_3d.max_distance = _max_distance
	_audio_player_3d.attenuation_model = _attenuation_model
	_audio_player_3d.unit_size = _unit_size
	_audio_player_3d.max_db = 3.0
	
	# Additional spatial audio settings
	_audio_player_3d.emission_angle_enabled = true
	_audio_player_3d.emission_angle_degrees = 90.0
	_audio_player_3d.emission_angle_filter_attenuation_db = -12.0
	_audio_player_3d.attenuation_filter_cutoff_hz = 5000.0
	_audio_player_3d.attenuation_filter_db = -24.0
	_audio_player_3d.doppler_tracking = 0
	
	# --- Audio Refactor: Setup Generator ---
	_audio_generator.mix_rate = AUDIO_SAMPLE_RATE
	_audio_generator.buffer_length = float(_audio_buffer_size_ms) / 1000.0 # Convert ms to seconds
	_audio_player_3d.stream = _audio_generator
	_audio_player_3d.play() # Start playing immediately
	_audio_playback = _audio_player_3d.get_stream_playback()
	if _audio_playback == null:
		printerr("Failed to get AudioStreamGeneratorPlayback!")
	else:
		print("AudioStreamGenerator initialized. Sample Rate: " + str(AUDIO_SAMPLE_RATE) + " Hz, Buffer length: " + str(_audio_generator.buffer_length) + "s")
	# --- End Audio Refactor ---

	print("Audio player properties:")
	print("- volume_db: " + str(_audio_player_3d.volume_db))
	print("- max_distance: " + str(_audio_player_3d.max_distance))
	print("- attenuation_model: " + str(_audio_player_3d.attenuation_model))
	print("- unit_size: " + str(_audio_player_3d.unit_size))
	
	# Connect audio finished signal - NO LONGER NEEDED
	# _audio_player_3d.finished.connect(_on_audio_finished) 
	
	# Increase all packet size limits
	_client.encode_buffer_max_size = 160000000
	_client.outbound_buffer_size = 160000000
	_client.inbound_buffer_size = 160000000
	
	
	# Connect to the WebSocket server
	var err = _client.connect_to_url("ws://192.168.1.190:3248")
	if err != OK:
		print("Unable to connect to WebSocket server")
		return
	
	# Create a new material if it doesn't exist
	if get_surface_override_material(1) == null:
		print("Creating new material at slot 1")
		var material = StandardMaterial3D.new()
		
		# Configure material for optimal texture display
		material.flags_transparent = false
		material.flags_unshaded = true  # Ignore lighting
		material.emission_enabled = true
		material.emission_energy_multiplier = 1.5  # Make it brighter
		
		set_surface_override_material(1, material)
	else:
		print("Using existing material at slot 1")
		var material = get_surface_override_material(1)
		
		# Ensure material is properly configured
		material.flags_transparent = false
		material.flags_unshaded = true
		material.emission_enabled = true
		material.emission_energy_multiplier = 1.5
	
	# Debug mesh information
	print("Mesh has " + str(mesh.get_surface_count()) + " surfaces")
	print("Material override count: " + str(get_surface_override_material_count()))

func _process(delta):
	# Poll the WebSocket for updates
	_client.poll()
	
	# Process audio queue - NO LONGER NEEDED
	# _process_audio_queue() 
	
	# Check connection state
	var state = _client.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		if not _connected:
			print("Connected to WebSocket server")
			_connected = true
		
		# Check for received messages
		while _client.get_available_packet_count() > 0:
			var packet = _client.get_packet()
			# Always expect text now since we JSON stringify
			if packet is String:
				_parse_message(packet)
			elif packet is PackedByteArray: # Handle potential binary message if needed
				var msg_text = packet.get_string_from_utf8()
				_parse_message(msg_text)
			else:
				printerr("Received unexpected packet type")

	elif state == WebSocketPeer.STATE_CLOSING:
		# WebSocket is closing
		_connected = false
	
	elif state == WebSocketPeer.STATE_CLOSED:
		# WebSocket is closed
		var code = _client.get_close_code()
		var reason = _client.get_close_reason()
		print("WebSocket closed with code: %d, reason: %s" % [code, reason])
		_connected = false
		
		# Try to reconnect after a delay
		await get_tree().create_timer(5.0).timeout
		var err = _client.connect_to_url("ws://localhost:3245")
		if err != OK:
			print("Unable to reconnect to WebSocket server")
	
	# Process audio queue - NO LONGER NEEDED
	# _process_audio_queue()

# Helper function to parse incoming messages
func _parse_message(msg_text):
	var json = JSON.new()
	var parse_result = json.parse(msg_text)
	if parse_result == OK:
		var data = json.get_data()
		# Check message type
		if data.has("type"):
			if data.type == "media_chunk":
				if data.has("audio_data") and data.has("video_data"):
					# Process audio first (as it drives timing)
					_handle_simple_audio(data.audio_data)
					# Then update the video frame
					_handle_video_frame(data.video_data)
				else:
					printerr("Received media_chunk missing audio or video data.")
			# Add handlers for other types if needed (e.g., "status", "error")
			# elif data.type == "video": # Keep old handlers temporarily?
			#	 _handle_video_frame(data.data)
			# elif data.type == "simple_audio":
			#	 _handle_simple_audio(data.data) # Adapt if needed
			else:
				print("Received unhandled message type: " + data.type)
	else:
		printerr("Failed to parse JSON: " + json.get_error_message() + " at line " + str(json.get_error_line()))
		# printerr("Received raw data: " + msg_text) # Careful, can be very long

func _handle_video_frame(base64_video_data):
	# Decode base64 data
	var image_data = Marshalls.base64_to_raw(base64_video_data)
	
	# Load image from buffer
	var err = _image.load_jpg_from_buffer(image_data)
	if err != OK:
		printerr("Failed to load video frame image from buffer: " + str(err))
		return
	
	# Debug image info occasionally
	_frame_count += 1
	# if _frame_count % 60 == 0: # Log less often
	#	 print("Received frame " + str(_frame_count) + ", image size: " +
	#		   str(_image.get_width()) + "x" + str(_image.get_height()))
	
	# Create or update texture
	if not _texture_initialized:
		_texture = ImageTexture.create_from_image(_image)
		_texture_initialized = true
		# print("Created initial texture: " + str(_image.get_width()) + "x" + str(_image.get_height()))
		var material = get_surface_override_material(1)
		if material:
			material.albedo_texture = _texture
			material.emission_texture = _texture
			# print("Applied initial texture to material")
	else:
		# Update existing texture data for better performance than creating new ones
		if _texture != null and _texture.get_width() == _image.get_width() and _texture.get_height() == _image.get_height():
			_texture.update(_image)
		else:
			# Fallback: Create new texture if size changed or not initialized properly
			_texture = ImageTexture.create_from_image(_image)
			var material = get_surface_override_material(1)
			if material:
				material.albedo_texture = _texture
				material.emission_texture = _texture

func _handle_simple_audio(base64_audio_data):
	"""Handle an audio chunk by pushing raw frames to the generator"""
	if _audio_playback == null:
		printerr("Audio playback object is null, cannot push frames.")
		# Attempt to get it again? Might indicate an issue in _ready
		_audio_playback = _audio_player_3d.get_stream_playback()
		if _audio_playback == null: return

	# Decode base64 WAV data
	var audio_data = Marshalls.base64_to_raw(base64_audio_data)

	# --- Debug: Save the first received chunk (Optional) ---
	# if not _saved_first_chunk: ... (keep if needed for debugging format)

	# --- Extract PCM and Push Frames ---
	if audio_data.size() <= WAV_HEADER_SIZE:
		printerr("Audio data too small to contain header and PCM data. Size: " + str(audio_data.size()))
		return

	# Extract the raw PCM data (skip header)
	var pcm_data = audio_data.slice(WAV_HEADER_SIZE)
	var pcm_data_len = pcm_data.size()

	# Calculate number of stereo frames (16-bit stereo = 4 bytes per frame)
	var bytes_per_frame = AUDIO_CHANNELS * (AUDIO_BITS_PER_SAMPLE / 8)
	if bytes_per_frame == 0:
		printerr("Error: Calculated bytes_per_frame is zero.")
		return
	var frame_count = pcm_data_len / bytes_per_frame

	if frame_count == 0:
		# print("Received audio chunk with no PCM frames after header.") # Can be noisy
		return

	# Check buffer space (optional, but good practice)
	var available_frames = _audio_playback.get_frames_available()
	if frame_count > available_frames:
		# This might happen if network delivers faster than playback consumes
		# Or if buffer is too small / processing too slow
		# print("Audio buffer low (%d available, %d needed). Pushing anyway..." % [available_frames, frame_count])
		# Consider increasing buffer size if this happens often.
		pass # Push frames anyway for now

	# Process and push frames
	var byte_index = 0
	for i in range(frame_count):
		# Ensure we don't read past the end of the buffer
		if byte_index + 3 >= pcm_data_len:
			printerr("Audio data buffer overrun during frame parsing. Index: %d, Length: %d" % [byte_index, pcm_data_len])
			break

		# Read left and right channels (16-bit signed little-endian)
		var left_sample_int = pcm_data.decode_s16(byte_index)
		var right_sample_int = pcm_data.decode_s16(byte_index + 2)
		byte_index += 4

		# Convert to float range [-1.0, 1.0]
		var left_sample_float = float(left_sample_int) / 32768.0
		var right_sample_float = float(right_sample_int) / 32768.0

		# Create Vector2 frame and push it
		var frame = Vector2(left_sample_float, right_sample_float)
		# Check if push_frame succeeded (returns bool)
		if not _audio_playback.push_frame(frame):
			# This usually means the buffer is full.
			# print("Failed to push audio frame (buffer likely full).")
			# We might lose a few frames here if the buffer check above wasn't strict enough
			pass # Continue trying to push subsequent frames

	# --- End Audio Refactor ---

	# Update spatial properties if needed (could be sent in media_chunk)
	# if data.has("spatial"):
	#	 _update_spatial_audio(data.spatial)

# Legacy handler - REMOVE OR ADAPT if needed
# func _handle_old_audio_format(base64_data, duration):
#	 printerr("Old audio format handler called - not implemented for AudioStreamGenerator")

func _update_spatial_audio(spatial_info):
	"""Update spatial audio parameters"""
	if spatial_info.has("volume_db"):
		_audio_player_3d.volume_db = spatial_info.volume_db
	if spatial_info.has("max_distance"):
		_audio_player_3d.max_distance = spatial_info.max_distance
	if spatial_info.has("attenuation"):
		_audio_player_3d.attenuation_model = spatial_info.attenuation
	if spatial_info.has("unit_size"):
		_audio_player_3d.unit_size = spatial_info.unit_size

# Use this to change audio properties from outside if needed
func set_audio_properties(volume_db: float, max_distance: float, attenuation_model: int):
	_volume_db = volume_db
	_max_distance = max_distance
	_attenuation_model = attenuation_model
	
	if _audio_player_3d:
		_audio_player_3d.volume_db = volume_db
		_audio_player_3d.max_distance = max_distance
		_audio_player_3d.attenuation_model = attenuation_model
		
		# Print current settings
		print("Updated audio settings:")
		print("- volume_db: " + str(_audio_player_3d.volume_db))
		print("- max_distance: " + str(_audio_player_3d.max_distance))
		print("- attenuation_model: " + str(_audio_player_3d.attenuation_model))

func _exit_tree():
	# Close WebSocket connection when the node exits
	if _client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_client.close()
		print("WebSocket connection closed on exit.")
