extends Node

signal player_connected(player_id, username)
signal player_disconnected(player_id)
signal chat_message_received(username, message)
signal system_message_received(message)
signal login_response(success, message)
signal register_response(success, message)
signal texture_info_received(texture_name)
signal weather_update_received(weather_data)
signal object_spawned(net_id)
signal object_updated(net_id, transform: Transform3D)
signal object_despawned(net_id)

# WebSocket client
var _client = WebSocketPeer.new()
var _connected = false
var _client_id = -1
var _username = ""
var _players = {}
var _objects = {}
var _next_object_id = 1

# Local authority tracking for replicated objects
var _owned_objects: Dictionary = {} # net_id -> Node3D
var _owned_last_sent: Dictionary = {} # net_id -> Transform3D
var _owned_update_interval := 0.1
var _owned_timer := 0.0

# Received state tracking
var _obj_seq: Dictionary = {} # net_id -> int
var _obj_is_authority: Dictionary = {} # net_id -> bool
var _obj_last_update_ms: Dictionary = {} # net_id -> int
var _claim_min_interval_ms := 200
var _claim_distance := 3.0

# Sequence counter for object updates
var _seq_counter := 0

# Configuration
@export var server_url = "ws://127.0.0.1:8765"
@export var reconnect_delay = 3.0
@export var humanoid_scene: PackedScene
@export var countryball_scene: PackedScene

# References
var _local_player = null
var _player_container = null
var _world_scale = Vector3(1, 1, 1)
var _rain_system = null

func _ready():
	_client.inbound_buffer_size = 1600000
	_client.outbound_buffer_size = 1600000
	if humanoid_scene == null:
		humanoid_scene = load("res://src/character/humanoid.tscn")
	if countryball_scene == null:
		countryball_scene = load("res://src/countryball/countryball.tscn")
	
	# Find the workspace node to get world scale
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		_world_scale = workspace.scale
		
		# Create a container for all players as a child of workspace
		_player_container = Node3D.new()
		_player_container.name = "Players"
		workspace.add_child(_player_container)
		
		# Find existing local player in the scene (could be humanoid or countryball)
		var existing_player = workspace.find_child("humanoid", true, false)
		if not existing_player:
			existing_player = workspace.find_child("countryball", true, false)
		
		if existing_player:
			_local_player = existing_player
			print("Found existing local player in workspace:", existing_player.name)
			# Ensure the LocalPlayer node exists for local player identification
			_ensure_local_player_node(existing_player)
	else:
		# Fallback if workspace not found
		_player_container = Node3D.new()
		_player_container.name = "Players"
		add_child(_player_container)
	
	# Connect to server
	connect_to_server()
	
	# Create auth manager if it doesn't exist
	if not get_node_or_null("/root/AuthManager"):
		var auth_manager = load("res://src/networking/auth_manager.gd").new()
		auth_manager.name = "AuthManager"
		get_tree().root.add_child(auth_manager)
		
		# Connect signals
		connect("login_response", Callable(auth_manager, "handle_login_response"))
		connect("register_response", Callable(auth_manager, "handle_register_response"))
	
	# Initialize rain system
	_setup_rain_system()

func _setup_rain_system():
	"""Setup the rain system and add it to the workspace"""
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		# Check if rain system already exists
		_rain_system = workspace.find_child("RainSystem", true, false)
		
		if not _rain_system:
			# Load and instantiate the rain system scene
			var rain_scene = load("res://src/environment/rain_system.tscn")
			if rain_scene:
				_rain_system = rain_scene.instantiate()
				workspace.add_child(_rain_system)
				print("Rain system added to workspace")
			else:
				print("Failed to load rain system scene")
		else:
			print("Rain system already exists in workspace")
		
		# Update the rain system's local player reference
		if _rain_system and _rain_system.has_method("update_local_player_reference"):
			_rain_system.update_local_player_reference()

func _ensure_local_player_node(player: Node):
	"""Ensures the LocalPlayer node exists and removes it from non-local players"""
	if not player:
		return
	
	# Check if LocalPlayer node already exists
	var local_player_node = player.get_node_or_null("LocalPlayer")
	if not local_player_node:
		# Create LocalPlayer node for local player
		local_player_node = Node.new()
		local_player_node.name = "LocalPlayer"
		player.add_child(local_player_node)
		print("Added LocalPlayer node to:", player.name)

func _remove_local_player_node(player: Node):
	"""Removes the LocalPlayer node from remote players"""
	if not player:
		return
	
	var local_player_node = player.get_node_or_null("LocalPlayer")
	if local_player_node:
		local_player_node.queue_free()
		print("Removed LocalPlayer node from remote player:", player.name)

func _process(delta):
	# Handle main WebSocket connection
	_client.poll()
	
	var state = _client.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _client.get_available_packet_count():
			_handle_message(_client.get_packet().get_string_from_utf8())
	
	elif state == WebSocketPeer.STATE_CLOSING:
		# Keep polling to achieve proper close
		pass
	
	elif state == WebSocketPeer.STATE_CLOSED:
		var code = _client.get_close_code()
		var reason = _client.get_close_reason()
		print("WebSocket closed with code: %d, reason: %s" % [code, reason])
		
		if _connected:
			_connected = false
			_client_id = -1
			
			# Clean up remote players
			for player_id in _players.keys():
				_remove_player(player_id)
			_players.clear()
			
			# Try to reconnect after delay
			await get_tree().create_timer(reconnect_delay).timeout
			connect_to_server()

	# Periodic updates for owned replicated objects (optimized, thresholded)
	_owned_timer += delta
	if _owned_timer >= _owned_update_interval:
		_owned_timer = 0.0
		for net_id in _owned_objects.keys():
			var obj: Node3D = _owned_objects.get(net_id, null)
			if not obj or not is_instance_valid(obj):
				_owned_objects.erase(net_id)
				_owned_last_sent.erase(net_id)
				continue
			# Drop ownership if body is sleeping to reduce chatter
			if obj is RigidBody3D and obj.sleeping:
				_owned_objects.erase(net_id)
				_owned_last_sent.erase(net_id)
				continue
			var xf: Transform3D = obj.global_transform
			var should_send := true
			if _owned_last_sent.has(net_id):
				var prev: Transform3D = _owned_last_sent[net_id]
				var pos_delta = xf.origin.distance_to(prev.origin)
				var dot_fwd = xf.basis.z.dot(prev.basis.z)
				var rot_changed = dot_fwd < 0.999
				should_send = pos_delta > 0.02 or rot_changed
			if should_send:
				# Prefer path-aware updates
				if has_method("notify_object_update_with_path"):
					notify_object_update_with_path(obj.get_path(), xf)
				else:
					notify_object_update(obj)
				_owned_last_sent[net_id] = xf

	# Proximity-based claim attempts for non-owned objects (soccer ball style)
	if is_instance_valid(_local_player):
		var now_ms: int = Time.get_ticks_msec()
		var my_pos: Vector3 = _local_player.global_transform.origin
		for net_id in _objects.keys():
			if _owned_objects.has(net_id):
				continue # already sending via owned loop
			var obj: Node3D = _objects.get(net_id, null)
			if not obj or not is_instance_valid(obj):
				continue
			if obj is RigidBody3D and obj.sleeping:
				continue
			var dist = obj.global_transform.origin.distance_to(my_pos)
			if dist > _claim_distance:
				continue
			var last_ms = int(_obj_last_update_ms.get(net_id, 0))
			if now_ms - last_ms < _claim_min_interval_ms:
				continue
			# Attempt a claim/update if we are not current authority
			var is_auth = bool(_obj_is_authority.get(net_id, false))
			if not is_auth:
				if has_method("notify_object_update_with_path"):
					notify_object_update_with_path(obj.get_path(), obj.global_transform)
				else:
					notify_object_update(obj)

func connect_to_server():
	print("Connecting to server: ", server_url)
	var err = _client.connect_to_url(server_url)
	if err != OK:
		print("Failed to connect to server: ", err)
		await get_tree().create_timer(reconnect_delay).timeout
		connect_to_server()

func _handle_message(message):
	var data = JSON.parse_string(message)
	if data == null:
		print("Invalid JSON received")
		return
	
	print("Received message type: ", data.type)
	
	match data.type:
		"connected":
			_connected = true
			_client_id = data.client_id
			_username = data.username
			print("Connected to server with ID: ", _client_id)
			
			# Update voice chat username
			_update_voice_chat_username()
			
			# Use existing local player if available
			if _local_player != null:
				print("Using existing local player")
				# Rename the local player to match the username if authenticated
				if _username != "" and _username != "Guest" + str(_client_id):
					print("Renaming local player from 'humanoid' to:", _username)
					_local_player.name = _username
				
				# Ensure LocalPlayer node exists
				_ensure_local_player_node(_local_player)
				
				# Update rain system reference
				if _rain_system and _rain_system.has_method("update_local_player_reference"):
					_rain_system.update_local_player_reference()
				
				# Start sending transform updates
				_start_transform_updates()
			else:
				# Spawn new local player if none exists
				_spawn_local_player()
			
			# Request list of existing players
			_send_message({
				"type": "get_players"
			})
		
		"player_list":
			for player_data in data.players:
				var player_id = player_data.id
				var username = player_data.username
				var position_data = player_data.position
				var rotation_data = player_data.rotation
				var texture_name = player_data.get("texture", null)
				var accessories = player_data.get("accessories", null)
				var character_type = player_data.get("character_type", "humanoid")
				
				_spawn_remote_player(player_id, username, position_data, rotation_data, texture_name, accessories, character_type)
		
		"player_joined":
			var player_id = data.player_id
			var username = data.username
			var position_data = data.position
			var rotation_data = data.rotation
			var texture_name = data.get("texture", null)
			var accessories = data.get("accessories", null)
			var character_type = data.get("character_type", "humanoid")
			
			print("Player joined: ", username)
			_spawn_remote_player(player_id, username, position_data, rotation_data, texture_name, accessories, character_type)
		
		"player_left":
			# A player has left
			var player_id = data.player_id
			if player_id in _players:
				var username = _players[player_id].name
				print("Player left:", username, "with ID:", player_id)
				_remove_player(player_id)
				emit_signal("player_disconnected", player_id)
		
		"object_spawn":
			var net_id = str(data.net_id)
			var xf = _parse_transform(data.transform)
			_spawn_or_update_object(net_id, xf)
			object_spawned.emit(net_id)
			# If this came from us (not distinguishable here), leave ownership to grab logic
		
		"object_update":
			var net_id2 = str(data.net_id)
			var xfu = _parse_transform(data.transform)
			if data.has("node_path") and typeof(data.node_path) == TYPE_STRING and data.node_path != "":
				var node_by_path = get_tree().root.get_node_or_null(data.node_path)
				if node_by_path and node_by_path is Node3D:
					node_by_path.global_transform = xfu
					_objects[net_id2] = node_by_path
					object_updated.emit(net_id2, xfu)
					# record seq/authority
					_obj_seq[net_id2] = int(data.get("seq", int(_obj_seq.get(net_id2, 0)) + 1))
					_obj_is_authority[net_id2] = int(data.get("authority", -1)) == _client_id
					_obj_last_update_ms[net_id2] = Time.get_ticks_msec()
					return
			_update_object_transform(net_id2, xfu)
			object_updated.emit(net_id2, xfu)
			# record seq/authority
			_obj_seq[net_id2] = int(data.get("seq", int(_obj_seq.get(net_id2, 0)) + 1))
			_obj_is_authority[net_id2] = int(data.get("authority", -1)) == _client_id
			_obj_last_update_ms[net_id2] = Time.get_ticks_msec()
			# On external updates, ensure we don't claim ownership
			_unmark_owned(net_id2)
		
		"object_despawn":
			var net_id3 = str(data.net_id)
			_despawn_object(net_id3)
			object_despawned.emit(net_id3)
		
		"player_transform":
			var player_id = data.player_id
			if player_id != _client_id and player_id in _players:
				var player = _players[player_id]
				
				# Check if player is still valid before accessing properties
				if not is_instance_valid(player):
					print("Player object is no longer valid, removing from _players: ", player_id)
					_players.erase(player_id)
					return
				
				# Store previous position to calculate movement
				var prev_position = player.position
				
				# Create a transform from position and rotation
				var position = Vector3(data.position.x, data.position.y, data.position.z)
				var rotation = Vector3(data.rotation.x, data.rotation.y, data.rotation.z)
				
				# Apply transform
				player.position = position
				player.rotation = rotation
				
				# Also set the character model rotation
				if player.has_node("CharacterModel"):
					if "model_rotation_y" in data:
						player.get_node("CharacterModel").rotation.y = data.model_rotation_y
					else:
						# Fallback to main rotation if model rotation not provided
						player.get_node("CharacterModel").rotation.y = rotation.y
				
				# Calculate movement for animation
				var movement = position - prev_position
				var speed = movement.length() / 0.05  # 0.05 is the update interval
				
				# Animate the player based on movement
				if player.has_method("animate_remote_movement"):
					player.animate_remote_movement(speed, movement.normalized())
		
		"chat_message":
			# Display chat message from another player
			var player_id = data.player_id
			var username = data.username
			var cmessage = data.message
			
			print("Chat message from %s: %s" % [username, cmessage])
			emit_signal("chat_message_received", username, cmessage)
			
			# Also display the chat bubble
			display_chat_bubble(player_id, cmessage)
		
		"system_message":
			# Display system message
			var cmessage = data.message
			print("System message:", cmessage)
			emit_signal("system_message_received", cmessage)
			
			# Check for username changes
			if cmessage.contains(" is now known as "):
				var parts = cmessage.split(" is now known as ")
				if parts.size() == 2:
					var old_username = parts[0]
					var new_username = parts[1]
					
					# Update local player name if it's the local player
					if old_username == _username:
						_username = new_username
						print("Updating local username to:", new_username)
						
						if is_instance_valid(_local_player):
							print("Updating local player name from:", _local_player.name, "to:", new_username)
							_local_player.name = new_username
					else:
						# Update remote player name if needed
						for player_id in _players:
							var player = _players[player_id]
							if player.name == old_username:
								player.name = new_username
								print("Renamed remote player from", old_username, "to", new_username)
					
					# Try to apply texture after username change
					var texture_manager = get_node_or_null("/root/TextureManager")
					if texture_manager:
						await get_tree().create_timer(0.2).timeout  # Slightly longer delay
						# Request the texture if not already cached
						if not texture_manager.texture_cache.has(new_username):
							print("Requesting texture for", new_username)
							_send_message({
								"type": "get_texture",
								"texture_name": new_username
							})
						else:
							print("Applying cached texture for", new_username)
							texture_manager.apply_texture_by_username(new_username)
		
		"login_response":
			emit_signal("login_response", data.success, data.message)
		
		"register_response":
			emit_signal("register_response", data.success, data.message)
		
		"character_transform":
			var player_id = data.player_id
			var username = data.username
			var character_type = data.character_type
			
			print("Character transform for player:", username, "to:", character_type)
			
			# Handle local player transformation
			if player_id == _client_id and is_instance_valid(_local_player):
				await _transform_local_player(character_type)
				# Request texture for new character type after transformation
				_send_message({
					"type": "get_texture",
					"texture_name": username
				})
			
			# Handle remote player transformation
			elif player_id in _players:
				await _transform_remote_player(player_id, character_type)
				# Request texture for new character type after transformation
				_send_message({
					"type": "get_texture",
					"texture_name": username
				})
		
		"texture_info":
			var texture_name = data.texture_name
			emit_signal("texture_info_received", texture_name)
			
			# Apply texture to local player
			if is_instance_valid(_local_player):
				var texture_manager = get_node("/root/TextureManager")
				var texture = texture_manager.load_texture(texture_name)
				if texture:  # If texture was cached
					var character_model = _local_player.find_child("CharacterModel", true)
					if character_model:
						texture_manager.apply_texture_to_character(character_model, texture)
		
		"texture_data":
			var texture_name = data.texture_name
			var texture_data = data.data
			var character_type = data.get("character_type", "humanoid")  # Get character type from server
			
			print("Received texture data for:", texture_name, "character type:", character_type)
			
			# Get or create texture manager
			var texture_manager = get_node_or_null("/root/TextureManager")
			if not texture_manager:
				print("Creating TextureManager")
				texture_manager = load("res://src/networking/texture_manager.gd").new()
				texture_manager.name = "TextureManager"
				get_tree().root.add_child(texture_manager)
			
			# Process the texture data with character type
			var texture = texture_manager.process_texture_data(texture_name, texture_data, character_type)
			
			# Apply texture to all players with matching username AND character type
			print("Applying texture to all players with name:", texture_name, "and character type:", character_type)
			
			# Apply to local player if it matches name and character type
			if is_instance_valid(_local_player) and _local_player.name == texture_name:
				var local_character_type = _get_player_character_type(_local_player)
				if local_character_type == character_type:
					print("Applying texture to local player:", texture_name)
					texture_manager.apply_texture_to_player(_local_player, texture)
			
			# Apply to remote players with matching name and character type
			for player_id in _players:
				var player = _players[player_id]
				if player.name == texture_name:
					var remote_character_type = _get_player_character_type(player)
					if remote_character_type == character_type:
						print("Applying texture to remote player:", texture_name)
						texture_manager.apply_texture_to_player(player, texture)
			
			# Emit signal for other components
			emit_signal("texture_info_received", texture_name)
		
		"accessories_data":
			print("Received accessories data: ", data)
			var username = data.username
			var accessories = data.accessories
			var player_id = data.get("player_id", -1)
			
			print("Accessories for user: ", username, " - ", accessories)
			
			# Find player with matching username in all players (local and remote)
			var found = false
			
			# Check local player first
			if is_instance_valid(_local_player) and _local_player.name == username:
				print("Applying accessories to local player: ", username)
				apply_accessories_to_player(_local_player, accessories)
				found = true
			
			# Check remote players
			for pid in _players:
				var player = _players[pid]
				if player.name == username:
					print("Applying accessories to remote player: ", username)
					apply_accessories_to_player(player, accessories)
					found = true
			
			if not found:
				print("WARNING: Could not find player with username: ", username, " to apply accessories")
		
		"login_success":
			_username = data.username
			print("Login successful, username updated to: ", _username)
			
			# Update voice chat with new username
			_update_voice_chat_username()
			
			login_response.emit(true, "Login successful")
		
		"weather_update":
			var weather_data = data.weather
			print("Received weather update: ", weather_data)
			emit_signal("weather_update_received", weather_data)
			
			# Update rain system if available
			if _rain_system and _rain_system.has_method("handle_weather_update"):
				_rain_system.handle_weather_update(weather_data)

func _update_voice_chat_username():
	"""Update voice chat systems with current username"""
	if _username == "":
		return
		
	# Find all MicrophoneAudioPlayer nodes and update their usernames
	var players = get_tree().get_nodes_in_group("players")
	for player in players:
		var voice_player = player.find_child("MicrophoneAudioPlayer", true, false)
		if voice_player and voice_player.has_method("update_voice_username_from_network"):
			voice_player.update_voice_username_from_network()
	
	# Also check the local player specifically
	if _local_player:
		var voice_player = _local_player.find_child("MicrophoneAudioPlayer", true, false)
		if voice_player and voice_player.has_method("update_voice_username_from_network"):
			voice_player.update_voice_username_from_network()

func _spawn_local_player():
	if _local_player != null:
		return
	
	# Find existing local player in the scene first
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		var existing_player = workspace.find_child("humanoid", true, false)
		if existing_player:
			_local_player = existing_player
			print("Using existing local player from workspace")
			
			# Ensure LocalPlayer node exists
			_ensure_local_player_node(_local_player)
			
			# Update rain system reference
			if _rain_system and _rain_system.has_method("update_local_player_reference"):
				_rain_system.update_local_player_reference()
			
			# Start sending transform updates
			_start_transform_updates()
			return
	
	# Instantiate the humanoid scene if no existing player found
	_local_player = humanoid_scene.instantiate()
	_local_player.name = "LocalPlayer"
	_player_container.add_child(_local_player)
	
	# Ensure LocalPlayer node exists
	_ensure_local_player_node(_local_player)
	
	# Update rain system reference
	if _rain_system and _rain_system.has_method("update_local_player_reference"):
		_rain_system.update_local_player_reference()
	
	# Start sending transform updates
	_start_transform_updates()

func _spawn_remote_player(player_id, username, position_data, rotation_data, texture_name = null, accessories = null, character_type = "humanoid"):
	if player_id in _players:
		return
	
	# Choose the correct scene based on character type
	var player_scene = humanoid_scene
	if character_type == "countryball":
		player_scene = countryball_scene
	
	# Instantiate the appropriate scene
	var player = player_scene.instantiate()
	player.name = username
	print("Adding remote player:", username, "as", character_type)
	
	# LLM would never assing a local player, as a result I used the old method;
	# manually removing the camera. This is also the sole non vibe coded part
	# of this script. Kinda sad. -salih1
	player.get_node("CamOrigin").queue_free()
	player.get_node("XROrigin3D").queue_free()
	_player_container.add_child(player)
	
	# IMPORTANT: Remove LocalPlayer node from remote players
	_remove_local_player_node(player)
	
	# Disable input processing and physics for remote player
	player.set_as_remote_player()
	
	# Set initial transform
	var position = Vector3(position_data.x, position_data.y, position_data.z)
	var rotation = Vector3(rotation_data.x, rotation_data.y, rotation_data.z)
	player.position = position
	player.rotation = rotation
	
	# Also set the character model rotation
	if player.has_node("CharacterModel"):
		player.get_node("CharacterModel").rotation.y = rotation.y
	
	# Store reference
	_players[player_id] = player
	print("Spawned remote player: ", username)
	
	# Apply texture if available
	if texture_name:
		var texture_manager = get_node_or_null("/root/TextureManager")
		if not texture_manager:
			# Create texture manager if it doesn't exist
			texture_manager = load("res://src/networking/texture_manager.gd").new()
			texture_manager.name = "TextureManager"
			get_tree().root.add_child(texture_manager)
		
		# Check if texture is already cached
		if texture_manager.texture_cache.has(texture_name):
			var texture = texture_manager.texture_cache[texture_name]
			texture_manager.apply_texture_to_player(player, texture)
		else:
			# Connect to texture loaded signal for this specific player
			var texture_loaded_handler = func(loaded_texture_name, texture):
				if loaded_texture_name == texture_name:
					texture_manager.apply_texture_to_player(player, texture)
			
			texture_manager.texture_loaded.connect(texture_loaded_handler)
			texture_manager.load_texture(texture_name)
	
	# Apply accessories if provided
	if accessories:
		apply_accessories_to_player(player, accessories)

func _transform_local_player(character_type):
	if not is_instance_valid(_local_player):
		return
	
	print("Transforming local player to:", character_type)
	
	# Store current position and rotation
	var current_position = _local_player.global_position
	var current_rotation = _local_player.rotation
	var current_name = _local_player.name
	
	# Store current accessories before destroying the player
	var current_accessories = []
	if _local_player.has_node("CharacterModel/Accessories"):
		var accessories_node = _local_player.get_node("CharacterModel/Accessories")
		for child in accessories_node.get_children():
			current_accessories.append(child.name)
	
	# Store planetary system state
	var current_planet = null
	var current_planet_name = "Planet"
	if _local_player.has_method("get_current_planet"):
		current_planet = _local_player.get_current_planet()
	if "planet_name" in _local_player:
		current_planet_name = _local_player.planet_name
	
	# Remove old player
	_local_player.queue_free()
	
	# Wait a frame for the old player to be removed
	await get_tree().process_frame
	
	# Choose the correct scene
	var new_scene = humanoid_scene
	if character_type == "countryball":
		new_scene = countryball_scene
	
	# Create new player
	_local_player = new_scene.instantiate()
	_local_player.name = current_name
	
	# Add local player directly to workspace (same as original), not to player container
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		workspace.add_child(_local_player)
		print("Added new local player directly to workspace")
	else:
		_player_container.add_child(_local_player)
		print("Fallback: Added new local player to player container")
	
	# Ensure LocalPlayer node exists for the new local player
	_ensure_local_player_node(_local_player)
	
	# Update rain system reference
	if _rain_system and _rain_system.has_method("update_local_player_reference"):
		_rain_system.update_local_player_reference()
	
	# Restore position and rotation
	_local_player.global_position = current_position
	_local_player.rotation = current_rotation
	
	# Wait a frame for the new player to be fully initialized
	await get_tree().process_frame
	
	# The new character will automatically find the planet through _ready() -> _find_planet()
	# since it's now added to the workspace properly
	print("New character should automatically find planetary system")
	
	# Restore accessories
	if current_accessories.size() > 0:
		print("Restoring accessories after transformation:", current_accessories)
		apply_accessories_to_player(_local_player, current_accessories)
	
	# Start transform updates again
	_start_transform_updates()

func _transform_remote_player(player_id, character_type):
	if not player_id in _players:
		return
	
	var old_player = _players[player_id]
	print("Transforming remote player:", old_player.name, "to:", character_type)
	
	# Store current data
	var current_position = old_player.global_position
	var current_rotation = old_player.rotation
	var current_name = old_player.name
	
	# Store current accessories before destroying the player
	var current_accessories = []
	if old_player.has_node("CharacterModel/Accessories"):
		var accessories_node = old_player.get_node("CharacterModel/Accessories")
		for child in accessories_node.get_children():
			current_accessories.append(child.name)
	
	# Store planetary system state
	var current_planet = null
	var current_planet_name = "Planet"
	if old_player.has_method("get_current_planet"):
		current_planet = old_player.get_current_planet()
	if "planet_name" in old_player:
		current_planet_name = old_player.planet_name
	
	# Remove old player
	old_player.queue_free()
	
	# Wait a frame
	await get_tree().process_frame
	
	# Choose the correct scene
	var new_scene = humanoid_scene
	if character_type == "countryball":
		new_scene = countryball_scene
	
	# Create new player
	var new_player = new_scene.instantiate()
	new_player.name = current_name
	
	if new_player.has_node("XROrigin3D"):
		new_player.get_node("XROrigin3D").queue_free()

	if new_player.has_node("CamOrigin"):
		new_player.get_node("CamOrigin").queue_free()
		
	_player_container.add_child(new_player)
	
	# IMPORTANT: Remove LocalPlayer node from remote players
	_remove_local_player_node(new_player)
	
	# Disable input for remote player
	new_player.set_as_remote_player()
	
	# Restore position and rotation
	new_player.global_position = current_position
	new_player.rotation = current_rotation
	
	# Wait a frame for the new player to be fully initialized
	await get_tree().process_frame
	
	# Restore planetary system state WITHOUT repositioning
	if current_planet and new_player.has_method("set_planet"):
		print("Restoring planetary system to new remote character")
		# Set planetary system manually to avoid repositioning
		new_player.planet_node = current_planet
		new_player.planet_name = current_planet_name
		if new_player.has_method("_calc_gravity_direction"):
			new_player._calc_gravity_direction()
		print("Restored planetary system without repositioning")
	
	# Restore accessories
	if current_accessories.size() > 0:
		print("Restoring accessories after transformation:", current_accessories)
		apply_accessories_to_player(new_player, current_accessories)
	
	# Update reference
	_players[player_id] = new_player

func _remove_player(player_id):
	if player_id in _players:
		var player = _players[player_id]
		player.queue_free()
	_players.erase(player_id)

func _start_transform_updates():
	# Send transform updates every 0.05 seconds (20 times per second)
	while _connected and is_instance_valid(_local_player):
		var position = _local_player.position
		var rotation = _local_player.rotation
		
		# Get character model rotation if available
		var model_rotation_y = null
		if _local_player.has_node("CharacterModel"):
			model_rotation_y = _local_player.get_node("CharacterModel").rotation.y
		
		var message = {
			"type": "transform_update",
			"position": {"x": position.x, "y": position.y, "z": position.z},
			"rotation": {"x": rotation.x, "y": rotation.y, "z": rotation.z}
		}
		
		# Add model rotation if available
		if model_rotation_y != null:
			message["model_rotation_y"] = model_rotation_y
		
		_send_message(message)
		await get_tree().create_timer(0.05).timeout

func display_chat_bubble(player_id, message):
	var player = null
	
	# Check if it's the local player
	if player_id == _client_id and is_instance_valid(_local_player):
		player = _local_player
	# Check remote players
	elif player_id in _players:
		player = _players[player_id]
	
	if player and player.has_node("CharacterModel/ChatBubble"):
		var chat_bubble = player.get_node("CharacterModel/ChatBubble")
		var sprite = chat_bubble.get_node("Sprite3D")
		var label = player.get_node("ChatBubbleViewport/Control/TextureRect/RichTextLabel")
		
		# Set the message text
		label.text = message
		
		# Show the bubble
		sprite.visible = true
		
		# Hide after 3 seconds
		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(sprite) and is_instance_valid(label):
			sprite.visible = false

func _send_message(data):
	if _connected:
		var json_string = JSON.stringify(data)
		_client.send_text(json_string)

func send_chat_message(message):
	if not _connected:
		return
	
	_send_message({
		"type": "chat_message",
		"message": message
	})


# ---------------- Object Replication (Client) ----------------
func _spawn_or_update_object(net_id: String, xf: Transform3D):
	var obj = _objects.get(net_id, null)
	if obj and is_instance_valid(obj):
		obj.global_transform = xf
		return
	# Try to find an existing node by name under InteractiveObjects
	var parent_scene: Node = get_tree().current_scene
	if parent_scene == null:
		parent_scene = get_tree().get_root()
	var workspace = parent_scene.find_child("workspace", true, false)
	if not workspace:
		workspace = parent_scene
	var container = workspace.find_child("InteractiveObjects", true, false)
	var existing: Node3D = null
	if container:
		existing = container.find_child("NetObj_" + net_id, true, false)
	if existing and existing is Node3D:
		existing.global_transform = xf
		_objects[net_id] = existing
		return
	if not container:
		container = Node3D.new()
		container.name = "InteractiveObjects"
		workspace.add_child(container)

func _update_object_transform(net_id: String, xf: Transform3D):
	var obj = _objects.get(net_id, null)
	if obj and is_instance_valid(obj):
		obj.global_transform = xf
		return
	# Fallback: update by name if it exists (out-of-order messages)
	var parent_scene: Node = get_tree().current_scene
	if parent_scene == null:
		parent_scene = get_tree().get_root()
	var workspace = parent_scene.find_child("workspace", true, false)
	if not workspace:
		workspace = parent_scene
	var container = workspace.find_child("InteractiveObjects", true, false)
	if container:
		var found = container.find_child("NetObj_" + net_id, true, false)
		if found and found is Node3D:
			found.global_transform = xf
			_objects[net_id] = found

func _despawn_object(net_id: String):
	var obj = _objects.get(net_id, null)
	if obj and is_instance_valid(obj):
		obj.queue_free()
	_objects.erase(net_id)

func _serialize_transform(xf: Transform3D) -> Dictionary:
	return {
		"origin": {"x": xf.origin.x, "y": xf.origin.y, "z": xf.origin.z},
		"basis_x": {"x": xf.basis.x.x, "y": xf.basis.x.y, "z": xf.basis.x.z},
		"basis_y": {"x": xf.basis.y.x, "y": xf.basis.y.y, "z": xf.basis.y.z},
		"basis_z": {"x": xf.basis.z.x, "y": xf.basis.z.y, "z": xf.basis.z.z}
	}

func _parse_transform(d: Dictionary) -> Transform3D:
	var b = Basis(
		Vector3(d.basis_x.x, d.basis_x.y, d.basis_x.z),
		Vector3(d.basis_y.x, d.basis_y.y, d.basis_y.z),
		Vector3(d.basis_z.x, d.basis_z.y, d.basis_z.z)
	)
	return Transform3D(b, Vector3(d.origin.x, d.origin.y, d.origin.z))

func _find_or_assign_object_id(obj: Node3D) -> String:
	var id = obj.get_meta("net_id")
	if id != null and typeof(id) == TYPE_STRING and id != "":
		return id
	var new_id = str(_next_object_id)
	_next_object_id += 1
	obj.set_meta("net_id", new_id)
	return new_id

func notify_object_grabbed(obj: Node3D):
	var net_id = _find_or_assign_object_id(obj)
	_seq_counter += 1
	_send_message({
		"type": "object_grab",
		"net_id": net_id,
		"transform": _serialize_transform(obj.global_transform),
		"seq": _seq_counter,
		"authority": _client_id
	})
	# Assume local authority while held
	_mark_owned(net_id, obj)

func notify_object_released(obj: Node3D, throw_velocity: Vector3):
	var net_id = _find_or_assign_object_id(obj)
	_seq_counter += 1
	_send_message({
		"type": "object_release",
		"net_id": net_id,
		"transform": _serialize_transform(obj.global_transform),
		"velocity": {"x": throw_velocity.x, "y": throw_velocity.y, "z": throw_velocity.z},
		"seq": _seq_counter,
		"authority": _client_id
	})
	# Drop ownership on release
	_unmark_owned(net_id)

func notify_object_released_with_path(obj_path: NodePath, xf: Transform3D, throw_velocity: Vector3):
	var obj: Node = get_tree().root.get_node_or_null(obj_path)
	var net_id = ""
	if obj and obj is Node3D:
		net_id = _find_or_assign_object_id(obj)
	else:
		net_id = str(_next_object_id)
		_next_object_id += 1
	_seq_counter += 1
	_send_message({
		"type": "object_release",
		"net_id": net_id,
		"node_path": str(obj_path),
		"transform": _serialize_transform(xf),
		"velocity": {"x": throw_velocity.x, "y": throw_velocity.y, "z": throw_velocity.z},
		"seq": _seq_counter,
		"authority": _client_id
	})
	_unmark_owned(net_id)

func notify_object_update(obj: Node3D):
	var net_id = _find_or_assign_object_id(obj)
	_seq_counter += 1
	_send_message({
		"type": "object_update",
		"net_id": net_id,
		"transform": _serialize_transform(obj.global_transform),
		"seq": _seq_counter,
		"authority": _client_id
	})

func notify_object_update_with_path(obj_path: NodePath, xf: Transform3D):
	var obj: Node = get_tree().root.get_node_or_null(obj_path)
	var net_id = ""
	if obj and obj is Node3D:
		net_id = _find_or_assign_object_id(obj)
	else:
		net_id = str(_next_object_id)
		_next_object_id += 1
	_seq_counter += 1
	_send_message({
		"type": "object_update",
		"net_id": net_id,
		"node_path": str(obj_path),
		"transform": _serialize_transform(xf),
		"seq": _seq_counter,
		"authority": _client_id
	})

func apply_accessories_to_player(player, accessories):
	print("Applying accessories to player: ", player.name)
	
	if not player:
		print("ERROR: Player is null")
		return
	
	if not accessories:
		print("WARNING: No accessories to apply")
		return
	
	# Check if the player has the necessary node structure
	if not player.has_node("CharacterModel"):
		print("ERROR: Player doesn't have a CharacterModel node")
		return
		
	if not player.has_node("CharacterModel/Accessories"):
		print("ERROR: Player doesn't have a CharacterModel/Accessories node")
		return
	
	# Get the Accessories node
	var accessories_node = player.get_node("CharacterModel/Accessories")
	print("Found Accessories node: ", accessories_node)
	
	# Load and add each accessory
	print("Adding new accessories: ", accessories)
	for accessory_name in accessories:
		print("Attempting to add accessory: ", accessory_name)
		var success = load_and_add_accessory(accessories_node, accessory_name)
		print("Accessory add result: ", success)

# Load and add an accessory to a node
func load_and_add_accessory(accessories_node, accessory_name):
	# Construct the path to the accessory scene
	var accessory_path = "res://src/character/accessories/" + accessory_name + "/" + accessory_name + ".tscn"
	print("Looking for accessory at path: ", accessory_path)
	
	# Check if the accessory exists
	if ResourceLoader.exists(accessory_path):
		print("Accessory exists, loading: ", accessory_path)
		var accessory_scene = load(accessory_path)
		if accessory_scene:
			var accessory_instance = accessory_scene.instantiate()
			accessory_instance.name = accessory_name
			accessories_node.add_child(accessory_instance)
			print("Successfully added accessory: ", accessory_name)
			return true
		else:
			print("Failed to load accessory scene despite it existing: ", accessory_path)
			return false
	else:
		print("Failed to find accessory: ", accessory_name)
		return false

func _get_player_character_type(player: Node) -> String:
	"""Determine character type based on the player's scene structure"""
	if not player:
		return "humanoid"
	
	# Check if it's a countryball by looking for specific nodes or scene name
	if player.scene_file_path.contains("countryball") or player.has_node("CountryballModel"):
		return "countryball"
	else:
		return "humanoid"

func _mark_owned(net_id: String, obj: Node3D):
	_owned_objects[net_id] = obj
	_owned_last_sent.erase(net_id)

func _unmark_owned(net_id: String):
	_owned_objects.erase(net_id)
	_owned_last_sent.erase(net_id)
