extends Node3D

# WebSocket client for microphone audio
var _client = WebSocketPeer.new()
var _connected = false

# --- Audio System using AudioStreamGenerator ---
var _audio_player_3d = null
var _audio_generator = AudioStreamGenerator.new()
var _audio_playback = null
var _audio_buffer_size_ms = 500  # Smaller buffer for lower latency

# Audio format constants (should match microphoneStreamer.py)
const AUDIO_CHANNELS = 2
const AUDIO_SAMPLE_RATE = 48000
const AUDIO_BITS_PER_SAMPLE = 16

# Connection settings - NOW CONNECTS TO VOICE CHAT SERVER
@export var websocket_url: String = "ws://127.0.0.1:3246"  # Voice chat server
@export var username: String = "Player1"
@export var room: String = "default"
@export var auto_connect: bool = true
@export var reconnect_delay: float = 3600 #experiment to see if this is the issue

# Spatial audio settings
@export var max_distance: float = 30.0
@export var attenuation_model: int = 0  # ATTENUATION_INVERSE_DISTANCE
@export var volume_db: float = 0.0
@export var unit_size: float = 10.0
@export var emission_angle_degrees: float = 90.0
@export var emission_angle_filter_attenuation_db: float = -12.0

# Debug and stats
var _chunks_received = 0
var _last_chunk_time = 0.0
var _connection_attempts = 0

# Player audio management
var _player_audio_sources = {}  # username -> AudioStreamPlayer3D
var _registered = false

# Connection state management
var _reconnect_timer = 0.0
var _should_reconnect = false
var _force_close_timer = 0.0
var _is_force_closing = false
var _ping_timer = 0.0
var _ping_interval = 10.0  # Send ping every 10 seconds (less frequent than server)
var _last_pong_time = 0.0
var _connection_timeout = 30.0  # Consider connection dead after 30 seconds without pong (more aggressive)
var _cleanup_timer = 0.0
var _cleanup_interval = 5.0  # Check for stale audio sources every 5 seconds

signal connected_to_microphone
signal disconnected_from_microphone
signal audio_chunk_received(chunk_index: int)

func _ready():
	print("MicrophoneAudioPlayer initializing...")
	
	# Get the actual username from network controller
	var network_controller = get_node_or_null("/root/NetworkController")
	if network_controller and network_controller._username != "":
		username = network_controller._username
		print("Got username from NetworkController: ", username)
	else:
		print("Using default username: ", username)
	
	# Set up 3D audio player
	_audio_player_3d = AudioStreamPlayer3D.new()
	add_child(_audio_player_3d)
	
	# Configure 3D audio properties
	_setup_spatial_audio()
	
	# Setup audio generator
	_setup_audio_generator()
	
	# Configure WebSocket
	_setup_websocket()
	
	# For debugging: always connect even with default username
	print("DEBUG: Current username = '", username, "'")
	if auto_connect:
		print("DEBUG: Auto-connecting to voice server...")
		connect_to_voice_server()
	else:
		print("DEBUG: Auto-connect disabled")

func _setup_spatial_audio():
	"""Configure spatial audio properties"""
	_audio_player_3d.volume_db = volume_db
	_audio_player_3d.max_distance = max_distance
	_audio_player_3d.attenuation_model = attenuation_model
	_audio_player_3d.unit_size = unit_size
	_audio_player_3d.max_db = 3.0
	
	# Directional audio settings
	_audio_player_3d.emission_angle_enabled = true
	_audio_player_3d.emission_angle_degrees = emission_angle_degrees
	_audio_player_3d.emission_angle_filter_attenuation_db = emission_angle_filter_attenuation_db
	_audio_player_3d.attenuation_filter_cutoff_hz = 5000.0
	_audio_player_3d.attenuation_filter_db = -24.0
	_audio_player_3d.doppler_tracking = 0
	
	print("Spatial audio configured:")
	print("- Volume: %s dB" % volume_db)
	print("- Max distance: %s" % max_distance)
	print("- Attenuation model: %s" % attenuation_model)

func _setup_audio_generator():
	"""Setup AudioStreamGenerator for real-time audio"""
	_audio_generator.mix_rate = AUDIO_SAMPLE_RATE
	_audio_generator.buffer_length = float(_audio_buffer_size_ms) / 1000.0
	
	_audio_player_3d.stream = _audio_generator
	_audio_player_3d.play()
	
	_audio_playback = _audio_player_3d.get_stream_playback()
	if _audio_playback == null:
		printerr("Failed to get AudioStreamGeneratorPlayback!")
	else:
		print("AudioStreamGenerator initialized:")
		print("- Sample Rate: %s Hz" % AUDIO_SAMPLE_RATE)
		print("- Buffer length: %s ms" % _audio_buffer_size_ms)
		print("- Channels: %s" % AUDIO_CHANNELS)

func _setup_websocket():
	"""Configure WebSocket client"""
	# Set buffer sizes for audio streaming
	_client.encode_buffer_max_size = 16000000
	_client.outbound_buffer_size = 16000000
	_client.inbound_buffer_size = 16000000

func connect_to_voice_server():
	"""Connect to voice chat server and register as player"""
	if _connected:
		print("Already connected to voice server")
		return
	
	# Check if we need to wait for the connection to properly close
	var state = _client.get_ready_state()
	if state != WebSocketPeer.STATE_CLOSED:
		print("WebSocket not in closed state (%d), forcing close and waiting..." % state)
		_force_close_connection()
		return
	
	_connection_attempts += 1
	print("Connecting to voice server: %s (attempt %d)" % [websocket_url, _connection_attempts])
	
	var err = _client.connect_to_url(websocket_url)
	if err != OK:
		printerr("Failed to connect to voice server: %s" % err)
		# Remove automatic reconnection - just log the error
		print("Connection failed. Manual retry required.")

func _force_close_connection():
	"""Force close the WebSocket connection and wait for it to be fully closed"""
	_is_force_closing = true
	_force_close_timer = 0.0
	_client.close()
	_connected = false
	_registered = false

func disconnect_from_microphone():
	"""Disconnect from the microphone streaming server"""
	_should_reconnect = false
	if _client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_client.close()
		print("Disconnected from microphone server")
	_connected = false
	_registered = false

func _schedule_reconnect():
	"""Log disconnection but don't automatically reconnect"""
	print("Voice server disconnected. Manual reconnection required.")
	# Completely disable reconnection
	_should_reconnect = false

func _process(delta):
	# Handle ping/pong keepalive
	if _connected:
		_ping_timer += delta
		if _ping_timer >= _ping_interval:
			_send_ping()
			_ping_timer = 0.0
		
		# Check for connection timeout
		var time_since_pong = Time.get_ticks_msec() / 1000.0 - _last_pong_time
		if time_since_pong > _connection_timeout:
			print("DEBUG: Connection timeout - no pong received in %s seconds (last pong: %s seconds ago)" % [_connection_timeout, time_since_pong])
			_handle_connection_timeout()
		
		# Periodic cleanup of invalid audio sources
		_cleanup_timer += delta
		if _cleanup_timer >= _cleanup_interval:
			_cleanup_stale_audio_sources()
			_cleanup_timer = 0.0
	
	# Completely remove reconnection timer logic
	
	# Handle force close timer
	if _is_force_closing:
		_force_close_timer += delta
		# Wait up to 2 seconds for proper close, then create new client
		if _force_close_timer > 2.0 or _client.get_ready_state() == WebSocketPeer.STATE_CLOSED:
			print("WebSocket client reset - ready for manual reconnection")
			_client = WebSocketPeer.new()
			_setup_websocket()
			_is_force_closing = false
			_force_close_timer = 0.0
			# Don't automatically reconnect - wait for manual call
			return
	
	# Poll WebSocket for updates
	_client.poll()
	
	# Handle connection state changes
	_handle_connection_state()

func _handle_connection_state():
	"""Handle WebSocket connection state changes"""
	var state = _client.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				print("Connected to voice server")
				_connected = true
				_connection_attempts = 0
				_last_pong_time = Time.get_ticks_msec() / 1000.0  # Reset pong timer
				_register_with_server()
			
			# Process incoming messages
			while _client.get_available_packet_count() > 0:
				var packet = _client.get_packet()
				_handle_packet(packet)
		
		WebSocketPeer.STATE_CLOSING:
			if _connected:
				_connected = false
				_registered = false
				print("Voice server connection closing...")
		
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				var code = _client.get_close_code()
				var reason = _client.get_close_reason()
				print("Voice server connection closed: %d - %s" % [code, reason])
				_connected = false
				_registered = false
				disconnected_from_microphone.emit()
				
				# Don't call _schedule_reconnect() at all - just log
				print("Voice server disconnected. Manual reconnection required.")

func _handle_packet(packet):
	"""Handle incoming WebSocket packet"""
	var msg_text: String
	
	if packet is String:
		msg_text = packet
	elif packet is PackedByteArray:
		msg_text = packet.get_string_from_utf8()
	else:
		printerr("Received unexpected packet type")
		return
	
	_parse_audio_message(msg_text)

func _parse_audio_message(msg_text: String):
	"""Parse incoming message from voice server"""
	var json = JSON.new()
	var parse_result = json.parse(msg_text)
	
	if parse_result != OK:
		printerr("Failed to parse JSON: %s at line %d" % [json.get_error_message(), json.get_error_line()])
		return
	
	var data = json.get_data()
	if not data.has("type"):
		printerr("Message missing 'type' field")
		return
	
	match data.type:
		"registered":
			_registered = true
			_last_pong_time = Time.get_ticks_msec() / 1000.0  # Reset pong timer on registration
			print("DEBUG: Successfully registered with voice server as ", username)
			connected_to_microphone.emit()
		
		"ping":
			# Server sent ping, respond with pong
			print("DEBUG: Received ping from server, sending pong")
			var pong_message = {
				"type": "pong"
			}
			_client.send_text(JSON.stringify(pong_message))
		
		"pong":
			# Server responded to our ping
			print("DEBUG: Received pong from server")
			_last_pong_time = Time.get_ticks_msec() / 1000.0
		
		"audio_chunk":
			_handle_player_audio_chunk(data)
		
		"user_joined":
			print("User joined: %s" % data.username)
		
		"user_left":
			print("User left: %s" % data.username)
			_remove_player_audio_source(data.username)
		
		_:
			print("Received unhandled message type: %s" % data.type)

func _handle_player_audio_chunk(data):
	"""Handle audio chunk from any player (including self)"""
	print("DEBUG: Received audio chunk from ", data.get("username", "unknown"))
	
	if not data.has("username") or not data.has("audio_data"):
		printerr("Audio chunk missing username or audio_data")
		return
	
	var player_username = data.username
	print("DEBUG: Processing audio for player: ", player_username, " (audio data length: ", len(data.audio_data), ")")
	
	# Get or create audio source for this player
	var audio_source = _get_or_create_player_audio_source(player_username)
	if not audio_source:
		return
	
	# Process audio data
	var audio_data = Marshalls.base64_to_raw(data.audio_data)
	print("DEBUG: Decoded audio data length: ", audio_data.size(), " bytes")
	_process_pcm_audio_for_player(audio_source, audio_data)
	
	# Update stats
	_chunks_received += 1
	if data.has("chunk_info") and data.chunk_info.has("index"):
		audio_chunk_received.emit(data.chunk_info.index)
	print("DEBUG: Total chunks received so far: ", _chunks_received)

func _get_or_create_player_audio_source(player_username: String):
	"""Get existing or create new audio source for a player"""
	if player_username in _player_audio_sources:
		return _player_audio_sources[player_username]
	
	# Find the speaking player's character node in the scene
	var target_node = _find_player_character_node(player_username)
	if not target_node:
		print("WARNING: Could not find character node for player '%s', audio will not be spatialized correctly" % player_username)
		return null
	
	print("DEBUG: Found character node for player '%s' at: %s" % [player_username, target_node.get_path()])
	
	# Create new audio source for this player
	var audio_player = AudioStreamPlayer3D.new()
	var audio_generator = AudioStreamGenerator.new()
	
	# Configure audio generator
	audio_generator.mix_rate = AUDIO_SAMPLE_RATE
	audio_generator.buffer_length = float(_audio_buffer_size_ms) / 1000.0
	
	# Configure 3D audio
	audio_player.stream = audio_generator
	audio_player.volume_db = volume_db
	audio_player.max_distance = max_distance
	audio_player.attenuation_model = attenuation_model
	audio_player.unit_size = unit_size
	
	# IMPORTANT: Add to the speaking player's character node, not to local player!
	target_node.add_child(audio_player)
	audio_player.play()
	
	# Store reference
	_player_audio_sources[player_username] = {
		"player": audio_player,
		"generator": audio_generator,
		"playback": audio_player.get_stream_playback(),
		"target_node": target_node
	}
	
	print("Created spatial audio source for player '%s' attached to: %s" % [player_username, target_node.get_path()])
	return _player_audio_sources[player_username]

func _find_player_character_node(player_username: String) -> Node3D:
	"""Find the player's character node in the scene by username"""
	
	# Get the workspace scene
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if not workspace:
		print("DEBUG: Could not find workspace node")
		return null
	
	# First, check if this is the local player (current character this script is attached to)
	var my_character = get_parent()  # The character this MicrophoneAudioPlayer is attached to
	if my_character:
		# Check if the local player has the same username
		var network_controller = get_node_or_null("/root/NetworkController")
		if network_controller:
			# IMPORTANT: Check if this player_username is from an old Guest registration
			# but the network controller has the current logged-in username
			if network_controller._username == player_username:
				print("DEBUG: Found local player character for '%s'" % player_username)
				return my_character
			
			# Handle case where voice chat is still using old Guest name
			# but player has logged in (character node renamed)
			if player_username.begins_with("Guest") and my_character.name == network_controller._username:
				print("DEBUG: Found local player character - username mismatch (voice: '%s', actual: '%s')" % [player_username, network_controller._username])
				print("DEBUG: Voice chat should reconnect with new username soon...")
				return my_character
	
	# Look for remote players in the Players container
	var players_container = workspace.find_child("Players", true, false)
	if players_container:
		# Try to find by exact node name match
		var player_node = players_container.find_child(player_username, true, false)
		if player_node:
			print("DEBUG: Found remote player '%s' by name in Players container" % player_username)
			return player_node
		
		# If not found by name, check all children for username match
		for child in players_container.get_children():
			if child.has_method("get_username") and child.get_username() == player_username:
				print("DEBUG: Found remote player '%s' by username method" % player_username)
				return child
			elif child.name == player_username:
				print("DEBUG: Found remote player '%s' by node name" % player_username)
				return child
	
	print("DEBUG: Could not find character node for username '%s'" % player_username)
	return null

func _process_pcm_audio_for_player(audio_source, audio_data: PackedByteArray):
	"""Process PCM audio for a specific player's audio source"""
	
	# Validate that the audio source and its components are still valid
	if not is_instance_valid(audio_source.player):
		print("DEBUG: Audio player is no longer valid")
		return
	
	if audio_source.has("target_node") and not is_instance_valid(audio_source.target_node):
		print("DEBUG: Target node for audio source is no longer valid")
		return
	
	var playback = audio_source.playback
	if not playback:
		return
	
	if audio_data.size() < 4:
		return
	
	# Calculate frames and process audio (same as before)
	var bytes_per_frame = AUDIO_CHANNELS * (AUDIO_BITS_PER_SAMPLE / 8)
	var frame_count = audio_data.size() / bytes_per_frame
	
	if frame_count == 0:
		return
	
	# Process and push frames
	var byte_index = 0
	for i in range(frame_count):
		if byte_index + 3 >= audio_data.size():
			break
		
		var left_sample = audio_data.decode_s16(byte_index)
		var right_sample = audio_data.decode_s16(byte_index + 2)
		byte_index += 4
		
		var left_float = float(left_sample) / 32768.0
		var right_float = float(right_sample) / 32768.0
		
		var frame = Vector2(left_float, right_float)
		playback.push_frame(frame)

func _remove_player_audio_source(player_username: String):
	"""Remove audio source when player leaves"""
	if player_username in _player_audio_sources:
		var audio_source = _player_audio_sources[player_username]
		
		# Clean up the audio player
		if is_instance_valid(audio_source.player):
			audio_source.player.queue_free()
		
		# Remove from our tracking
		_player_audio_sources.erase(player_username)
		print("Removed audio source for player: %s" % player_username)

func _register_with_server():
	"""Register as a player with the voice chat server"""
	var registration = {
		"type": "register",
		"username": username,
		"room": room,
		"user_type": "player"  # Changed from "streamer" - this is a RECEIVER
	}
	
	var message = JSON.stringify(registration)
	print("DEBUG: Sending registration message: ", message)
	_client.send_text(message)
	print("Sent registration for user: %s in room: %s as PLAYER" % [username, room])

# Public API functions

func set_volume(db: float):
	"""Set audio volume in decibels"""
	volume_db = db
	if _audio_player_3d:
		_audio_player_3d.volume_db = db

func set_max_distance(distance: float):
	"""Set maximum audio distance"""
	max_distance = distance
	if _audio_player_3d:
		_audio_player_3d.max_distance = distance

func set_attenuation_model(model: int):
	"""Set audio attenuation model"""
	attenuation_model = model
	if _audio_player_3d:
		_audio_player_3d.attenuation_model = model

func get_connection_status() -> bool:
	"""Get current connection status"""
	return _connected

func get_audio_stats() -> Dictionary:
	"""Get audio streaming statistics"""
	return {
		"chunks_received": _chunks_received,
		"last_chunk_time": _last_chunk_time,
		"connected": _connected,
		"connection_attempts": _connection_attempts,
		"buffer_frames_available": _audio_playback.get_frames_available() if _audio_playback else 0
	}

func _exit_tree():
	"""Cleanup when node is removed"""
	disconnect_from_microphone()
	print("MicrophoneAudioPlayer cleaned up")

func set_voice_username(new_username: String):
	"""Update the username for voice chat"""
	if new_username != username:
		var old_username = username
		username = new_username
		print("Voice chat username updated from ", old_username, " to: ", username)
		
		# If already connected, MUST reconnect with new username
		if _connected:
			print("Disconnecting voice chat to reconnect with new username...")
			disconnect_from_microphone()
			# Wait longer to ensure clean disconnect
			await get_tree().create_timer(2.0).timeout
			print("Reconnecting voice chat as: ", username)
			connect_to_voice_server()

func update_voice_username_from_network():
	"""Update username from network controller"""
	var network_controller = get_node_or_null("/root/NetworkController")
	if network_controller and network_controller._username != "":
		var new_username = network_controller._username
		if new_username != username:
			print("Updating voice username from ", username, " to ", new_username)
			set_voice_username(new_username)

func _cleanup_stale_audio_sources():
	"""Clean up audio sources whose target nodes are no longer valid"""
	var players_to_remove = []
	
	for player_username in _player_audio_sources.keys():
		var audio_source = _player_audio_sources[player_username]
		
		# Check if the audio player is still valid
		if not is_instance_valid(audio_source.player):
			print("Voice audio player for '%s' is no longer valid, removing" % player_username)
			players_to_remove.append(player_username)
			continue
		
		# Check if the target node is still valid
		if audio_source.has("target_node") and not is_instance_valid(audio_source.target_node):
			print("Voice audio target node for '%s' is no longer valid, removing" % player_username)
			players_to_remove.append(player_username)
	
	# Clean up invalid players
	for player_username in players_to_remove:
		_remove_player_audio_source(player_username)

func _send_ping():
	"""Send ping to server to keep connection alive"""
	if _connected and _registered:
		print("DEBUG: Sending ping to voice server")
		var ping_message = {
			"type": "ping"
		}
		_client.send_text(JSON.stringify(ping_message))

func _handle_connection_timeout():
	"""Handle connection timeout"""
	print("Voice server connection timed out")
	_connected = false
	_registered = false
	_client.close()
	disconnected_from_microphone.emit()
