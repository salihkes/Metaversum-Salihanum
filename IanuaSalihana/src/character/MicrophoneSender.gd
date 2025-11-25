extends Node

# WebSocket client for sending microphone audio
var _client = WebSocketPeer.new()
var _connected = false
var _registered = false

# Audio capture
var _audio_effect_capture: AudioEffectCapture = null
var _recording = false

# Connection settings - connects to voice chat server
@export var websocket_url: String = "ws://37.247.99.180:3246"
@export var username: String = "Player1"
@export var room: String = "default"
@export var auto_connect: bool = false  # Changed to false - will connect on first VR button press

# Audio settings (must match server expectations)
const AUDIO_CHANNELS = 2
const AUDIO_SAMPLE_RATE = 48000
const AUDIO_BITS_PER_SAMPLE = 16
const CHUNK_SIZE = 2048  # Frames per chunk

# Stats
var _chunks_sent = 0
var _chunk_index = 0

# Timing
var _send_timer = 0.0
var _send_interval = 0.05  # Send audio every 50ms

# Ping/pong for keepalive
var _ping_timer = 0.0
var _ping_interval = 10.0
var _last_pong_time = 0.0
var _connection_timeout = 30.0

# Registration timeout
var _registration_timer = 0.0
var _registration_timeout = 5.0  # If not registered within 5 seconds, reconnect

# Connection timeout
var _connection_timer = 0.0
var _connection_timeout_duration = 10.0  # If stuck in CONNECTING for 10 seconds, reconnect
var _is_connecting = false

signal connected_to_voice_server
signal disconnected_from_voice_server

func _ready():
	print("========================================")
	print("MicrophoneSender initializing...")
	print("========================================")
	
	# Get username from network controller
	var network_controller = get_node_or_null("/root/NetworkController")
	if network_controller and network_controller._username != "":
		username = network_controller._username
		print("Got username from NetworkController: ", username)
	else:
		print("Using default username: ", username)
	
	# Get the AudioEffectCapture from the Record bus
	_setup_audio_capture()
	
	# Configure WebSocket
	_setup_websocket()
	
	# Check if microphone permissions are available
	print("Checking microphone setup...")
	var workspace = get_parent()
	if workspace:
		var audio_player = workspace.get_node_or_null("AudioStreamPlayer")
		if audio_player:
			print("  - AudioStreamPlayer found: ", audio_player.name)
			print("  - Stream type: ", audio_player.stream)
			print("  - Bus: ", audio_player.bus)
			print("  - Playing: ", audio_player.playing)
		else:
			print("  - WARNING: AudioStreamPlayer not found!")
	
	# Auto-connect if enabled (disabled by default - VR will trigger connection on first button press)
	if auto_connect:
		connect_to_voice_server()
	
	print("========================================")

func _setup_audio_capture():
	"""Setup audio capture from the Record bus"""
	print("Setting up audio capture from Record bus...")
	
	var bus_idx = AudioServer.get_bus_index("Record")
	if bus_idx == -1:
		printerr("ERROR: Record bus not found! Make sure default_bus_layout.tres has a Record bus")
		printerr("Available buses:")
		for i in range(AudioServer.get_bus_count()):
			printerr("  - Bus %d: %s" % [i, AudioServer.get_bus_name(i)])
		return
	
	print("  - Found Record bus at index: ", bus_idx)
	print("  - Number of effects on Record bus: ", AudioServer.get_bus_effect_count(bus_idx))
	
	# Find the AudioEffectCapture effect
	for i in range(AudioServer.get_bus_effect_count(bus_idx)):
		var effect = AudioServer.get_bus_effect(bus_idx, i)
		print("    - Effect %d: %s" % [i, effect.get_class()])
		if effect is AudioEffectCapture:
			_audio_effect_capture = effect
			print("  ✓ Found AudioEffectCapture on Record bus!")
			break
	
	if not _audio_effect_capture:
		printerr("ERROR: AudioEffectCapture not found on Record bus!")
		printerr("Please add AudioEffectCapture to the Record bus in default_bus_layout.tres")
		return
	
	# Clear any existing captured audio
	_audio_effect_capture.clear_buffer()
	print("  ✓ AudioEffectCapture ready")
	print("    - Buffer length: ", _audio_effect_capture.get_buffer_length_frames(), " frames")
	print("    - Can get buffer: ", _audio_effect_capture.can_get_buffer(_audio_effect_capture.get_buffer_length()))

func _setup_websocket():
	"""Configure WebSocket client"""
	_client.encode_buffer_max_size = 16000000
	_client.outbound_buffer_size = 16000000
	_client.inbound_buffer_size = 16000000

func connect_to_voice_server():
	"""Connect to voice chat server"""
	if _connected:
		return
	
	# Reset connection state
	_is_connecting = false
	_connection_timer = 0.0
	
	# Create a NEW WebSocketPeer instance (fixes issue where it goes to CLOSED immediately)
	_client = WebSocketPeer.new()
	_setup_websocket()  # Reconfigure the new client
	
	var err = _client.connect_to_url(websocket_url)
	if err != OK:
		printerr("MicrophoneSender: Failed to connect - Error: %s" % err)

func disconnect_from_voice_server():
	"""Disconnect from voice server"""
	_recording = false
	_connected = false
	_registered = false
	_is_connecting = false
	_connection_timer = 0.0
	_registration_timer = 0.0
	if _client.get_ready_state() != WebSocketPeer.STATE_CLOSED:
		_client.close()

func _process(delta):
	# Poll WebSocket
	_client.poll()
	
	# Track if we're stuck in CONNECTING state
	var current_state = _client.get_ready_state()
	if current_state == WebSocketPeer.STATE_CONNECTING:
		if not _is_connecting:
			_is_connecting = true
			_connection_timer = 0.0
		else:
			_connection_timer += delta
			if _connection_timer >= _connection_timeout_duration:
				print("MicrophoneSender: Connection timeout - reconnecting...")
				disconnect_from_voice_server()
				await get_tree().create_timer(1.0).timeout
				connect_to_voice_server()
	else:
		_is_connecting = false
		_connection_timer = 0.0
	
	# Handle connection state
	_handle_connection_state()
	
	# Send audio if connected and registered
	if _connected and _registered and _recording:
		_send_timer += delta
		if _send_timer >= _send_interval:
			_capture_and_send_audio()
			_send_timer = 0.0
	
	# Check registration timeout - if connected but not registered
	if _connected and not _registered:
		_registration_timer += delta
		if _registration_timer >= _registration_timeout:
			print("MicrophoneSender: Registration timeout - reconnecting...")
			disconnect_from_voice_server()
			await get_tree().create_timer(1.0).timeout
			connect_to_voice_server()
			_registration_timer = 0.0
	
	# Ping/pong keepalive
	if _connected:
		_ping_timer += delta
		if _ping_timer >= _ping_interval:
			_send_ping()
			_ping_timer = 0.0
		
		# Check for timeout
		var time_since_pong = Time.get_ticks_msec() / 1000.0 - _last_pong_time
		if time_since_pong > _connection_timeout:
			print("MicrophoneSender: Connection timeout")
			_handle_connection_timeout()

func _handle_connection_state():
	"""Handle WebSocket connection state"""
	var state = _client.get_ready_state()
	
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				_last_pong_time = Time.get_ticks_msec() / 1000.0
				_registration_timer = 0.0  # Reset registration timer
				_register_with_server()
			
			# Process incoming messages
			while _client.get_available_packet_count() > 0:
				var packet = _client.get_packet()
				_handle_packet(packet)
		
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				_registered = false
				_recording = false
				disconnected_from_voice_server.emit()

func _handle_packet(packet):
	"""Handle incoming WebSocket packet"""
	var msg_text = packet.get_string_from_utf8() if packet is PackedByteArray else packet
	
	var json = JSON.new()
	if json.parse(msg_text) != OK:
		return
	
	var data = json.get_data()
	if not data.has("type"):
		return
	
	match data.type:
		"registered":
			_registered = true
			_recording = true  # Start recording after registration
			_last_pong_time = Time.get_ticks_msec() / 1000.0
			_registration_timer = 0.0  # Reset registration timer
			connected_to_voice_server.emit()
		
		"error":
			printerr("MicrophoneSender: Server error - ", data.get("message", "Unknown error"))
		
		"ping":
			# Server sent ping, respond with pong
			var pong_message = {"type": "pong"}
			_client.send_text(JSON.stringify(pong_message))
		
		"pong":
			# Server responded to our ping
			_last_pong_time = Time.get_ticks_msec() / 1000.0

func _register_with_server():
	"""Register as a streamer with voice chat server"""
	var registration = {
		"type": "register",
		"username": username,
		"room": room,
		"user_type": "streamer"  # This is a SENDER
	}
	
	_client.send_text(JSON.stringify(registration))

func _capture_and_send_audio():
	"""Capture audio from Record bus and send to server"""
	if not _audio_effect_capture:
		print("ERROR: No audio effect capture!")
		return
	
	var frames_available = _audio_effect_capture.get_frames_available()
	if frames_available < CHUNK_SIZE:
		# This is normal - just not enough audio yet
		return
	
	# Read audio frames
	var audio_frames = _audio_effect_capture.get_buffer(CHUNK_SIZE)
	if audio_frames.size() == 0:
		print("WARNING: Got 0 audio frames from capture buffer")
		return
	
	# Check if audio has actual content (not just silence)
	var has_audio = false
	for frame in audio_frames:
		if abs(frame.x) > 0.01 or abs(frame.y) > 0.01:
			has_audio = true
			break
	
	# Convert Vector2 frames to PCM16 bytes
	var pcm_data = PackedByteArray()
	pcm_data.resize(CHUNK_SIZE * 4)  # 2 channels * 2 bytes per sample
	
	var byte_index = 0
	for frame in audio_frames:
		# Left channel
		var left_sample = int(clamp(frame.x * 32767.0, -32768.0, 32767.0))
		pcm_data.encode_s16(byte_index, left_sample)
		byte_index += 2
		
		# Right channel
		var right_sample = int(clamp(frame.y * 32767.0, -32768.0, 32767.0))
		pcm_data.encode_s16(byte_index, right_sample)
		byte_index += 2
	
	# Encode to base64
	var base64_audio = Marshalls.raw_to_base64(pcm_data)
	
	# Send to server
	var message = {
		"type": "audio_chunk",
		"audio_data": base64_audio,
		"chunk_info": {
			"index": _chunk_index,
			"sample_rate": AUDIO_SAMPLE_RATE,
			"channels": AUDIO_CHANNELS,
			"format": "pcm_s16le"
		}
	}
	
	_client.send_text(JSON.stringify(message))
	
	_chunks_sent += 1
	_chunk_index += 1

func _send_ping():
	"""Send ping to keep connection alive"""
	if _connected and _registered:
		var ping_message = {"type": "ping"}
		_client.send_text(JSON.stringify(ping_message))

func _handle_connection_timeout():
	"""Handle connection timeout"""
	print("Voice server connection timed out")
	_connected = false
	_registered = false
	_recording = false
	_client.close()
	disconnected_from_voice_server.emit()

func set_voice_username(new_username: String):
	"""Update username for voice chat"""
	if new_username != username:
		var old_username = username
		username = new_username
		print("Voice chat sender username updated from ", old_username, " to: ", username)
		
		# MUST reconnect if already connected to update server-side registration
		if _connected:
			print("Disconnecting voice sender to reconnect with new username...")
			disconnect_from_voice_server()
			# Wait longer to ensure clean disconnect
			await get_tree().create_timer(2.0).timeout
			print("Reconnecting voice sender as: ", username)
			connect_to_voice_server()

func update_voice_username_from_network():
	"""Update username from network controller"""
	var network_controller = get_node_or_null("/root/NetworkController")
	if not network_controller:
		print("WARNING: NetworkController not found for voice username update")
		return
	
	print("DEBUG: NetworkController username = '%s', current voice username = '%s'" % [network_controller._username, username])
	
	if network_controller._username != "":
		var new_username = network_controller._username
		if new_username != username:
			print("VOICE SENDER: Updating username from '%s' to '%s'" % [username, new_username])
			set_voice_username(new_username)
		else:
			print("DEBUG: Voice sender username already matches: '%s'" % username)

func get_stats() -> Dictionary:
	"""Get audio streaming statistics"""
	return {
		"connected": _connected,
		"registered": _registered,
		"recording": _recording,
		"chunks_sent": _chunks_sent,
		"chunk_index": _chunk_index
	}

func _exit_tree():
	"""Cleanup when node is removed"""
	disconnect_from_voice_server()
	print("MicrophoneSender cleaned up")
