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


var _client = WebSocketPeer.new()
var _connected = false
var _client_id = -1
var _username = ""
var _players = {}
var _objects = {}
var _next_object_id = 1
var _manual_disconnect = true
var _all_plots = []


var _user_texture = null
var _user_character_type = "humanoid"
var _user_flag_code = ""
var _user_accessories = []


var _saved_username = ""
var _saved_password = ""
var _credentials_path = "user://credentials.json"
var _pending_login_username = ""
var _pending_login_password = ""


var _owned_objects: Dictionary = {}
var _owned_last_sent: Dictionary = {}
var _owned_update_interval: = 0.1
var _owned_timer: = 0.0


var _obj_seq: Dictionary = {}
var _obj_is_authority: Dictionary = {}
var _obj_last_update_ms: Dictionary = {}
var _claim_min_interval_ms: = 200
var _claim_distance: = 3.0


var _seq_counter: = 0



@export var server_url = "wss://project.skeskin.com:2053"
@export var reconnect_delay = 3.0
@export var humanoid_scene: PackedScene
@export var countryball_scene: PackedScene
@export var countryball_oneside_scene: PackedScene


var _local_player = null
var _player_container = null
var _world_scale = Vector3(1, 1, 1)
var _rain_system = null
var _pending_spawn_position = null
var _monster_controller = null

func _ready():

	_client.inbound_buffer_size = 10000000
	_client.outbound_buffer_size = 10000000
	if humanoid_scene == null:
		humanoid_scene = load("res://src/character/humanoid.tscn")
	if countryball_scene == null:
		countryball_scene = load("res://src/countryball/countryball.tscn")
	if countryball_oneside_scene == null:
		countryball_oneside_scene = load("res://src/countryball/countryballoneside.tscn")



	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if not workspace:
		workspace = get_tree().get_root().find_child("localworkspace", true, false)

	if workspace:
		_monster_controller = workspace.find_child("MonsterController", true, false)
		if _monster_controller:
			print("MonsterController found in workspace scene")
		else:
			print("MonsterController not found in workspace, creating new one")
			_monster_controller = load("res://src/sidegames/pocketmonsters/monster_controller.gd").new()
			_monster_controller.name = "MonsterController"
			workspace.add_child(_monster_controller)
	else:
		print("Warning: No workspace found, creating MonsterController at root")
		_monster_controller = load("res://src/sidegames/pocketmonsters/monster_controller.gd").new()
		_monster_controller.name = "MonsterController"
		get_tree().root.add_child(_monster_controller)


	_load_credentials()

	var should_auto_connect = false

	if workspace:
		_world_scale = workspace.scale


		if workspace.name == "workspace":
			should_auto_connect = true
			print("Workspace named 'workspace' detected - will auto-connect")


		_player_container = Node3D.new()
		_player_container.name = "Players"
		workspace.add_child(_player_container)


		var existing_player = workspace.find_child("humanoid", true, false)
		if not existing_player:
			existing_player = workspace.find_child("countryball", true, false)

		if existing_player:
			_local_player = existing_player
			print("Found existing local player in workspace:", existing_player.name)

			_ensure_local_player_node(existing_player)
	else:

		_player_container = Node3D.new()
		_player_container.name = "Players"
		add_child(_player_container)


	if not get_node_or_null("/root/AuthManager"):
		var auth_manager = load("res://src/networking/auth_manager.gd").new()
		auth_manager.name = "AuthManager"
		get_tree().root.add_child(auth_manager)


		connect("login_response", Callable(auth_manager, "handle_login_response"))
		connect("register_response", Callable(auth_manager, "handle_register_response"))


	_setup_rain_system()


	if should_auto_connect:
		print("Auto-connecting to server...")
		connect_to_server()
	else:
		print("Network controller ready. Use /connect to connect to server.")

func _setup_rain_system():
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:

		_rain_system = workspace.find_child("RainSystem", true, false)

		if not _rain_system:

			var rain_scene = load("res://src/environment/rain_system.tscn")
			if rain_scene:
				_rain_system = rain_scene.instantiate()
				workspace.add_child(_rain_system)
				print("Rain system added to workspace")
			else:
				print("Failed to load rain system scene")
		else:
			print("Rain system already exists in workspace")


		if _rain_system and _rain_system.has_method("update_local_player_reference"):
			_rain_system.update_local_player_reference()

func _load_credentials():
	var old_config_path = "user://credentials.cfg"
	if FileAccess.file_exists(old_config_path):
		var config = ConfigFile.new()
		var err = config.load(old_config_path)
		if err == OK:
			_saved_username = config.get_value("auth", "username", "")
			_saved_password = config.get_value("auth", "password", "")
			if _saved_username != "" and _saved_password != "":
				print("Loaded saved credentials from OLD format (.cfg) for user: ", _saved_username)

				_save_credentials(_saved_username, _saved_password)
				print("Migrated credentials to new JSON format")
				return


	if FileAccess.file_exists(_credentials_path):
		var file = FileAccess.open(_credentials_path, FileAccess.READ)
		if file:
			var json_string = file.get_as_text()
			file.close()

			var json = JSON.new()
			var parse_result = json.parse(json_string)

			if parse_result == OK:
				var data = json.data
				if data.has("username") and data.has("password"):
					_saved_username = data.username
					_saved_password = data.password
					print("Loaded saved credentials for user: ", _saved_username)
				else:
					print("Invalid credentials file format")
			else:
				print("Failed to parse credentials file")
	else:
		print("No saved credentials found")

func _save_credentials(username: String, password: String):
	var data = {
		"username": username, 
		"password": password
	}

	var json_string = JSON.stringify(data)
	var file = FileAccess.open(_credentials_path, FileAccess.WRITE)

	if file:
		file.store_string(json_string)
		file.close()
		print("Saved credentials for user: ", username)
	else:
		print("Failed to save credentials")

func _ensure_local_player_node(player: Node):

	if not player:
		return


	var local_player_node = player.get_node_or_null("LocalPlayer")
	if not local_player_node:

		local_player_node = Node.new()
		local_player_node.name = "LocalPlayer"
		player.add_child(local_player_node)
		print("Added LocalPlayer node to:", player.name)

func _remove_local_player_node(player: Node):
	if not player:
		return

	var local_player_node = player.get_node_or_null("LocalPlayer")
	if local_player_node:
		local_player_node.queue_free()
		print("Removed LocalPlayer node from remote player:", player.name)

func _process(delta):

	_client.poll()

	var state = _client.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while _client.get_available_packet_count():
			_handle_message(_client.get_packet().get_string_from_utf8())

	elif state == WebSocketPeer.STATE_CLOSING:

		pass

	elif state == WebSocketPeer.STATE_CLOSED:
		var code = _client.get_close_code()
		var reason = _client.get_close_reason()


		if _connected:
			_connected = false
			_client_id = -1


			for player_id in _players.keys():
				_remove_player(player_id)
			_players.clear()


			if _monster_controller:

				var remote_monster_ids = _monster_controller.remote_monsters.keys()
				for net_id in remote_monster_ids:
					_monster_controller.despawn_remote_monster(net_id)


			if not _manual_disconnect:
				await get_tree().create_timer(reconnect_delay).timeout
				connect_to_server()


	_owned_timer += delta
	if _owned_timer >= _owned_update_interval:
		_owned_timer = 0.0
		for net_id in _owned_objects.keys():
			var obj: Node3D = _owned_objects.get(net_id, null)
			if not obj or not is_instance_valid(obj):
				_owned_objects.erase(net_id)
				_owned_last_sent.erase(net_id)
				continue

			if obj is RigidBody3D and obj.sleeping:
				_owned_objects.erase(net_id)
				_owned_last_sent.erase(net_id)
				continue
			var xf: Transform3D = obj.global_transform
			var should_send: = true
			if _owned_last_sent.has(net_id):
				var prev: Transform3D = _owned_last_sent[net_id]
				var pos_delta = xf.origin.distance_to(prev.origin)
				var dot_fwd = xf.basis.z.dot(prev.basis.z)
				var rot_changed = dot_fwd < 0.999
				should_send = pos_delta > 0.02 or rot_changed
			if should_send:

				if has_method("notify_object_update_with_path"):
					notify_object_update_with_path(obj.get_path(), xf)
				else:
					notify_object_update(obj)
				_owned_last_sent[net_id] = xf


	if is_instance_valid(_local_player):
		var now_ms: int = Time.get_ticks_msec()
		var my_pos: Vector3 = _local_player.global_transform.origin
		for net_id in _objects.keys():
			if _owned_objects.has(net_id):
				continue
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

			var is_auth = bool(_obj_is_authority.get(net_id, false))
			if not is_auth:
				if has_method("notify_object_update_with_path"):
					notify_object_update_with_path(obj.get_path(), obj.global_transform)
				else:
					notify_object_update(obj)

func connect_to_server():
	print("Connecting to server: ", server_url)
	_manual_disconnect = false
	var err = _client.connect_to_url(server_url)
	if err != OK:
		print("Failed to connect to server: ", err)
		await get_tree().create_timer(reconnect_delay).timeout
		connect_to_server()

func disconnect_from_server():
	if not _connected:
		print("Not connected to server")
		return false

	print("Manually disconnecting from server...")
	_manual_disconnect = true
	_client.close()
	_connected = false
	_client_id = -1


	for player_id in _players.keys():
		_remove_player(player_id)
	_players.clear()

	print("Disconnected from server")
	return true

func _handle_message(message):
	var data = JSON.parse_string(message)
	if data == null:
		print("Invalid JSON received")
		return



	match data.type:
		"connected":
			_connected = true
			_client_id = data.client_id


			var is_place_server = data.has("place_name")




			var current_is_guest = _username == "" or _username.begins_with("Guest")
			var new_is_guest = data.username.begins_with("Guest")

			if ( not is_place_server) or (current_is_guest and not new_is_guest):
				_username = data.username
				print("Connected to server with ID: ", _client_id, " Username updated to: ", _username)
			else:
				print("Connected to place server with ID: ", _client_id, " Keeping username: ", _username)


			if data.has("character_type"):
				_user_character_type = data.character_type



			if not is_place_server:
				_update_voice_chat_username()


			if _local_player != null:
				print("Using existing local player")

				if _username != "" and _username != "Guest" + str(_client_id):
					print("Renaming local player from 'humanoid' to:", _username)
					_local_player.name = _username


				_ensure_local_player_node(_local_player)


				if _rain_system and _rain_system.has_method("update_local_player_reference"):
					_rain_system.update_local_player_reference()

				# Check if existing player matches server's default character type
				var current_type = _get_player_character_type(_local_player)
				if current_type != _user_character_type:
					print("Transforming existing player from ", current_type, " to server default: ", _user_character_type)
					await _transform_local_player(_user_character_type, _user_flag_code)
				else:
					_start_transform_updates()
			else:

				_spawn_local_player()


			_send_message({
				"type": "get_players"
			})




			if _username.begins_with("Guest"):

				if OS.has_feature("web"):
					print("=== WEB SSO AUTO-LOGIN CHECK ===")
					await get_tree().create_timer(0.5).timeout
					_try_web_sso_login()
				else:

					var xr_interface = XRServer.find_interface("OpenXR")
					var is_vr = xr_interface and xr_interface.is_initialized()

					if _saved_username != "" and _saved_password != "" and is_vr:
						print("=== AUTO-LOGIN TRIGGERED (VR MODE) ===")
						print("Auto-logging in with saved credentials for user: ", _saved_username)


						_pending_login_username = _saved_username
						_pending_login_password = _saved_password

						await get_tree().create_timer(0.5).timeout
						_send_message({
							"type": "login", 
							"username": _saved_username, 
							"password": _saved_password
						})
						print("Auto-login request sent")

		"player_list":
			for player_data in data.players:
				var player_id = player_data.id
				var username = player_data.username
				var position_data = player_data.position
				var rotation_data = player_data.rotation
				var texture_name = player_data.get("texture", null)
				var accessories = player_data.get("accessories", null)
				var character_type = player_data.get("character_type", "humanoid")
				var flag_code = player_data.get("flag_code", "")
				var emotion = player_data.get("emotion", "neutral")

				_spawn_remote_player(player_id, username, position_data, rotation_data, texture_name, accessories, character_type, flag_code, emotion)

		"player_joined":
			var player_id = data.player_id
			var username = data.username
			var position_data = data.position
			var rotation_data = data.rotation
			var texture_name = data.get("texture", null)
			var accessories = data.get("accessories", null)
			var character_type = data.get("character_type", "humanoid")
			var flag_code = data.get("flag_code", "")
			var emotion = data.get("emotion", "neutral")

			print("Player joined: ", username)
			_spawn_remote_player(player_id, username, position_data, rotation_data, texture_name, accessories, character_type, flag_code, emotion)

		"player_left":

			var player_id = data.player_id
			if player_id in _players:
				var username = _players[player_id].name
				print("Player left:", username, "with ID:", player_id)
				_remove_player(player_id)
				emit_signal("player_disconnected", player_id)

		"player_identity_update":

			var player_id = data.player_id
			var username = data.username
			var texture = data.get("texture", null)
			var character_type = data.get("character_type", "humanoid")
			var accessories = data.get("accessories", [])

			if player_id in _players:
				var player_node = _players[player_id]
				player_node.name = username
				print("Updated player identity: ", username, " (", character_type, ")")


				if texture:
					_send_message({
						"type": "get_texture", 
						"texture_name": texture
					})




		"object_spawn":
			var net_id = str(data.net_id)
			var xf = _parse_transform(data.transform)
			_spawn_or_update_object(net_id, xf)
			object_spawned.emit(net_id)


		"object_update":
			var net_id2 = str(data.net_id)
			var xfu = _parse_transform(data.transform)
			if data.has("node_path") and typeof(data.node_path) == TYPE_STRING and data.node_path != "":
				var node_by_path = get_tree().root.get_node_or_null(data.node_path)
				if node_by_path and node_by_path is Node3D:
					node_by_path.global_transform = xfu
					_objects[net_id2] = node_by_path
					object_updated.emit(net_id2, xfu)

					_obj_seq[net_id2] = int(data.get("seq", int(_obj_seq.get(net_id2, 0)) + 1))
					_obj_is_authority[net_id2] = int(data.get("authority", -1)) == _client_id
					_obj_last_update_ms[net_id2] = Time.get_ticks_msec()
					return
			_update_object_transform(net_id2, xfu)
			object_updated.emit(net_id2, xfu)

			_obj_seq[net_id2] = int(data.get("seq", int(_obj_seq.get(net_id2, 0)) + 1))
			_obj_is_authority[net_id2] = int(data.get("authority", -1)) == _client_id
			_obj_last_update_ms[net_id2] = Time.get_ticks_msec()

			_unmark_owned(net_id2)

		"object_despawn":
			var net_id3 = str(data.net_id)
			_despawn_object(net_id3)
			object_despawned.emit(net_id3)

		"player_transform":
			var player_id = data.player_id
			if player_id != _client_id and player_id in _players:
				var player = _players[player_id]


				if not is_instance_valid(player):
					print("Player object is no longer valid, removing from _players: ", player_id)
					_players.erase(player_id)
					return


				var prev_position = player.position


				var position = Vector3(data.position.x, data.position.y, data.position.z)
				var rotation = Vector3(data.rotation.x, data.rotation.y, data.rotation.z)


				var on_floor = data.get("on_floor", true)


				player.position = position
				player.rotation = rotation


				if player.has_node("CharacterModel"):
					if "model_rotation_y" in data:
						player.get_node("CharacterModel").rotation.y = data.model_rotation_y
					else:

						player.get_node("CharacterModel").rotation.y = rotation.y


				var movement = position - prev_position
				var speed = movement.length() / 0.05


				if player.has_method("animate_remote_movement"):
					player.animate_remote_movement(speed, movement.normalized(), on_floor)

		"chat_message":

			var player_id = data.player_id
			var username = data.username
			var cmessage = data.message

			print("Chat message from %s: %s" % [username, cmessage])
			emit_signal("chat_message_received", username, cmessage)


			display_chat_bubble(player_id, cmessage)

		"system_message":

			var cmessage = data.message
			print("System message:", cmessage)
			emit_signal("system_message_received", cmessage)


			if cmessage.contains(" is now known as "):
				var parts = cmessage.split(" is now known as ")
				if parts.size() == 2:
					var old_username = parts[0]
					var new_username = parts[1]


					if old_username == _username:
						_username = new_username
						print("Updating local username to:", new_username)


						if not _all_plots.is_empty():
							print("NetworkController: Username changed, re-checking plots...")
							_check_user_plot()

						if is_instance_valid(_local_player):
							print("Updating local player name from:", _local_player.name, "to:", new_username)
							_local_player.name = new_username
					else:

						for player_id in _players:
							var player = _players[player_id]
							if player.name == old_username:
								player.name = new_username
								print("Renamed remote player from", old_username, "to", new_username)


					var texture_manager = get_node_or_null("/root/TextureManager")
					if texture_manager:
						await get_tree().create_timer(0.2).timeout

						if not texture_manager.texture_cache.has(new_username):
							print("Requesting texture for", new_username)
							_send_message({
								"type": "get_texture", 
								"texture_name": new_username
							})
						else:
							print("Applying cached texture for", new_username)
							texture_manager.apply_texture_by_username(new_username)

		"teleport":

			if is_instance_valid(_local_player):
				var position = Vector3(data.position.x, data.position.y, data.position.z)
				_local_player.position = position
				print("Teleported to position: ", position)

		"login_response":
			emit_signal("login_response", data.success, data.message)

		"register_response":
			emit_signal("register_response", data.success, data.message)

		"character_transform":
			var player_id = data.player_id
			var username = data.username
			var character_type = data.character_type
			var flag_code = data.get("flag_code", "")

			print("Character transform for player:", username, "to:", character_type, " flag:", flag_code)
			print("  player_id:", player_id, " _client_id:", _client_id, " username:", username, " _username:", _username)


			if username == _username:
				_user_character_type = character_type
				_user_flag_code = flag_code
				print("Stored character type for local player: ", character_type, " flag: ", flag_code)


			if (username == _username or player_id == _client_id) and is_instance_valid(_local_player):
				print("Transforming local player to:", character_type, " flag:", flag_code)
				await _transform_local_player(character_type, flag_code)

				_send_message({
					"type": "get_texture", 
					"texture_name": username
				})


			elif player_id in _players:
				print("Transforming remote player", player_id, "to:", character_type, " flag:", flag_code)
				await _transform_remote_player(player_id, character_type, flag_code)

				_send_message({
					"type": "get_texture", 
					"texture_name": username
				})

		"texture_info":
			var texture_name = data.texture_name
			emit_signal("texture_info_received", texture_name)


			if is_instance_valid(_local_player):
				var texture_manager = get_node("/root/TextureManager")
				var texture = texture_manager.load_texture(texture_name)
				if texture:
					var character_model = _local_player.find_child("CharacterModel", true)
					if character_model:
						texture_manager.apply_texture_to_character(character_model, texture)

		"texture_data":
			var texture_name = data.texture_name
			var texture_data = data.data
			var character_type = data.get("character_type", "humanoid")
			var flag_code = data.get("flag_code", "")

			print("Received texture data for:", texture_name, "character type:", character_type, "flag_code:", flag_code)


			if texture_name == _username:
				_user_texture = texture_name
				# Update stored flag_code for local player
				if character_type == "countryball_oneside" and flag_code != "":
					_user_flag_code = flag_code
				print("Stored texture for local player")


			var texture_manager = get_node_or_null("/root/TextureManager")
			if not texture_manager:
				print("Creating TextureManager")
				texture_manager = load("res://src/networking/texture_manager.gd").new()
				texture_manager.name = "TextureManager"
				get_tree().root.add_child(texture_manager)


			var texture = texture_manager.process_texture_data(texture_name, texture_data, character_type, flag_code)


			print("Applying texture to all players with name:", texture_name, "and character type:", character_type)


			if is_instance_valid(_local_player) and _username == texture_name:
				var local_character_type = _get_player_character_type(_local_player)
				if local_character_type == character_type:
					print("Applying texture to local player:", texture_name, " (username: ", _username, ")")
					texture_manager.apply_texture_to_player(_local_player, texture)


			for player_id in _players:
				var player = _players[player_id]
				if player.name == texture_name:
					var remote_character_type = _get_player_character_type(player)
					if remote_character_type == character_type:
						print("Applying texture to remote player:", texture_name)
						texture_manager.apply_texture_to_player(player, texture)


			emit_signal("texture_info_received", texture_name)

		"accessories_data":
			print("Received accessories data: ", data)
			var username = data.username
			var accessories = data.accessories
			var player_id = data.get("player_id", -1)

			print("Accessories for user: ", username, " - ", accessories)


			if username == _username:
				_user_accessories = accessories
				print("Stored accessories for local player: ", accessories)


			var found = false


			if is_instance_valid(_local_player) and (username == _username):
				print("Applying accessories to local player: ", username)
				apply_accessories_to_player(_local_player, accessories)
				found = true


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
			print("=== LOGIN SUCCESS ===")
			print("Login successful, username updated to: ", _username)


			if not _all_plots.is_empty():
				print("NetworkController: Login success, re-checking plots...")
				_check_user_plot()


			if _pending_login_username != "" and _pending_login_password != "":
				_save_credentials(_pending_login_username, _pending_login_password)
				_saved_username = _pending_login_username
				_saved_password = _pending_login_password
				print("Credentials saved for future auto-login")


				_pending_login_username = ""
				_pending_login_password = ""


			if is_instance_valid(_local_player) and _local_player.name.begins_with("Guest"):
				print("Renaming local player from '", _local_player.name, "' to: ", _username)
				_local_player.name = _username



			await get_tree().create_timer(0.2).timeout
			print("Updating voice chat with username: ", _username)
			_update_voice_chat_username()

			login_response.emit(true, "Login successful")

		"weather_update":
			var weather_data = data.weather
			print("Received weather update: ", weather_data)
			emit_signal("weather_update_received", weather_data)


			if _rain_system and _rain_system.has_method("handle_weather_update"):
				_rain_system.handle_weather_update(weather_data)

		"pck_manifest":
			# Server sent the PCK package manifest – hand it to the PCK manager
			print("Received PCK manifest from server")
			var pck_manager = get_node_or_null("/root/PCKManager")
			if pck_manager:
				pck_manager.handle_server_manifest(data.manifest)
			else:
				print("WARNING: PCKManager autoload not found, skipping PCK check")

		"emotion_update":
			var player_id = data.player_id
			var username = data.username
			var emotion = data.emotion
			
			print("Received emotion update for:", username, "emotion:", emotion)
			
			# Apply to local player if it's us
			if (username == _username or player_id == _client_id) and is_instance_valid(_local_player):
				_apply_emotion_to_player(_local_player, emotion)
			
			# Apply to remote player
			elif player_id in _players:
				var remote_player = _players[player_id]
				_apply_emotion_to_player(remote_player, emotion)

		"place_info":
			var place_name = data.place_name
			var server_url = data.server_url
			var scene_data = data.scene_data

			print("Received place info for: ", place_name)
			print("Place server URL: ", server_url)


			var scene_path = "user://places/" + place_name + ".tscn"
			var dir = DirAccess.open("user://")
			if not dir.dir_exists("user://places"):
				dir.make_dir("user://places")

			var file = FileAccess.open(scene_path, FileAccess.WRITE)
			if file:
				file.store_string(scene_data)
				file.close()
				print("Saved place scene to: ", scene_path)


			_switch_to_place_server(server_url, scene_path)

		"places_list":
			var places = data.places
			print("Available places: ", places)


			var chat_ui = get_tree().root.find_child("ChatUI", true, false)
			if chat_ui and chat_ui.has_method("add_message"):
				if places.size() == 0:
					chat_ui.add_message("System", "No places available", true)
				else:
					chat_ui.add_message("System", "Available places:", true)
					for place_name in places:
						chat_ui.add_message("System", "  - " + place_name + " (use /join " + place_name + ")", true)

		"plots_info":
			var plots = data.plots
			print("NetworkController: ===== RECEIVED PLOTS INFO =====")
			print("NetworkController: ", plots.size(), " plots received")
			print("NetworkController: Current username = ", _username)


			_all_plots = plots


			_check_user_plot()

		"plot_object_spawn":
			var net_id = str(data.net_id)
			var plot_id = data.plot_id
			var object_type = data.object_type
			var xf = _parse_transform(data.transform)

			print("Spawning plot object: ", object_type, " (", net_id, ") in plot ", plot_id)
			_spawn_plot_object(net_id, object_type, xf, plot_id)

		"plot_object_update":
			var net_id = str(data.net_id)
			var plot_id = data.plot_id
			var xf = _parse_transform(data.transform)

			print("Updating plot object: ", net_id, " in plot ", plot_id)
			_update_object_transform(net_id, xf)

		"plot_object_remove":
			var net_id = str(data.net_id)
			var plot_id = data.plot_id

			print("Removing plot object: ", net_id, " from plot ", plot_id)
			_despawn_object(net_id)

		"monster_spawn":

			if _monster_controller:
				_monster_controller.handle_monster_spawn(data)
			else:
				print("Warning: MonsterController not available for monster_spawn")

		"monster_update":

			if _monster_controller:
				_monster_controller.handle_monster_update(data)

		"monster_despawn":

			if _monster_controller:
				_monster_controller.handle_monster_despawn(data)

		"player_monsters_list":

			print("NetworkController: Received player_monsters_list message")
			print("NetworkController: Data: ", data)
			print("NetworkController: MonsterController reference: ", _monster_controller)
			print("NetworkController: Local player: ", _local_player)
			if _monster_controller and is_instance_valid(_monster_controller):
				print("NetworkController: Calling handle_player_monsters_list...")

				_monster_controller.handle_player_monsters_list(data, _local_player)
				print("NetworkController: handle_player_monsters_list completed")
			else:
				print("NetworkController: ERROR - MonsterController reference is null or invalid")

func _update_voice_chat_username():
	print("=== _update_voice_chat_username called ===")
	print("Current username: ", _username)

	if _username == "":
		print("WARNING: Username is empty, skipping voice chat update")
		return


	var players = get_tree().get_nodes_in_group("players")
	print("Found ", players.size(), " players in 'players' group")
	for player in players:
		var voice_player = player.find_child("MicrophoneAudioPlayer", true, false)
		if voice_player and voice_player.has_method("update_voice_username_from_network"):
			print("  - Updating MicrophoneAudioPlayer for: ", player.name)
			voice_player.update_voice_username_from_network()


	if _local_player:
		print("Checking local player: ", _local_player.name)
		var voice_player = _local_player.find_child("MicrophoneAudioPlayer", true, false)
		if voice_player and voice_player.has_method("update_voice_username_from_network"):
			print("  - Updating local player's MicrophoneAudioPlayer")
			voice_player.update_voice_username_from_network()


	var workspace = get_tree().get_root().find_child("workspace", true, false)
	print("Looking for MicrophoneSender in workspace...")
	if workspace:
		var mic_sender = workspace.find_child("MicrophoneSender", true, false)
		if mic_sender:
			print("  - Found MicrophoneSender, updating username to: ", _username)
			if mic_sender.has_method("update_voice_username_from_network"):
				mic_sender.update_voice_username_from_network()
			else:
				print("  - WARNING: MicrophoneSender doesn't have update_voice_username_from_network method")
		else:
			print("  - WARNING: MicrophoneSender not found in workspace")
	else:
		print("  - WARNING: Workspace not found")

	print("=== _update_voice_chat_username finished ===")

func _spawn_local_player():
	if _local_player != null:
		return


	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		var existing_player = workspace.find_child("humanoid", true, false)
		if existing_player:
			_local_player = existing_player
			print("Using existing local player from workspace")


			_ensure_local_player_node(_local_player)


			if _rain_system and _rain_system.has_method("update_local_player_reference"):
				_rain_system.update_local_player_reference()


			_start_transform_updates()
			return


	# Use the correct scene based on server's default character type
	var player_scene = humanoid_scene
	if _user_character_type == "countryball":
		player_scene = countryball_scene
	elif _user_character_type == "countryball_oneside":
		player_scene = countryball_oneside_scene
	
	_local_player = player_scene.instantiate()
	_local_player.name = "LocalPlayer"
	_player_container.add_child(_local_player)


	_ensure_local_player_node(_local_player)


	if _rain_system and _rain_system.has_method("update_local_player_reference"):
		_rain_system.update_local_player_reference()


	if _pending_spawn_position != null:
		await get_tree().process_frame
		_local_player.global_position = _pending_spawn_position
		print("Applied pending checkpoint spawn position to new player: ", _pending_spawn_position)
		_pending_spawn_position = null


	_start_transform_updates()

func _spawn_remote_player(player_id, username, position_data, rotation_data, texture_name = null, accessories = null, character_type = "humanoid", flag_code = "", emotion = "neutral"):
	if player_id in _players:
		return


	var player_scene = humanoid_scene
	if character_type == "countryball":
		player_scene = countryball_scene
	elif character_type == "countryball_oneside":
		player_scene = countryball_oneside_scene


	var player = player_scene.instantiate()
	player.name = username
	# Store flag_code as metadata for countryball_oneside
	if character_type == "countryball_oneside" and flag_code != "":
		player.set_meta("flag_code", flag_code)
	# Store initial emotion as metadata
	player.set_meta("initial_emotion", emotion)
	print("Adding remote player:", username, "as", character_type, " flag:", flag_code, " emotion:", emotion)




	player.get_node("CamOrigin").queue_free()
	player.get_node("XROrigin3D").queue_free()
	_player_container.add_child(player)


	_remove_local_player_node(player)


	player.set_as_remote_player()


	var position = Vector3(position_data.x, position_data.y, position_data.z)
	var rotation = Vector3(rotation_data.x, rotation_data.y, rotation_data.z)
	player.position = position
	player.rotation = rotation


	if player.has_node("CharacterModel"):
		player.get_node("CharacterModel").rotation.y = rotation.y


	_players[player_id] = player
	print("Spawned remote player: ", username)


	if texture_name:
		var texture_manager = get_node_or_null("/root/TextureManager")
		if not texture_manager:

			texture_manager = load("res://src/networking/texture_manager.gd").new()
			texture_manager.name = "TextureManager"
			get_tree().root.add_child(texture_manager)


		if texture_manager.texture_cache.has(texture_name):
			var texture = texture_manager.texture_cache[texture_name]
			texture_manager.apply_texture_to_player(player, texture)
		else:

			var texture_loaded_handler = func(loaded_texture_name, texture):
				if loaded_texture_name == texture_name:
					texture_manager.apply_texture_to_player(player, texture)

			texture_manager.texture_loaded.connect(texture_loaded_handler)
			texture_manager.load_texture(texture_name)


	if accessories:
		apply_accessories_to_player(player, accessories)
	
	# Apply initial emotion for countryball characters (delay to ensure animation is setup)
	if character_type in ["countryball", "countryball_oneside"] and emotion != "neutral":
		# Use call_deferred to ensure the character is fully initialized
		call_deferred("_apply_emotion_to_player", player, emotion)

func _transform_local_player(character_type, flag_code = ""):
	if not is_instance_valid(_local_player):
		return

	print("Transforming local player to:", character_type, " flag:", flag_code)


	var current_position = _local_player.global_position
	var current_rotation = _local_player.rotation
	var current_name = _local_player.name


	var current_accessories = []
	if _local_player.has_node("CharacterModel/Accessories"):
		var accessories_node = _local_player.get_node("CharacterModel/Accessories")
		for child in accessories_node.get_children():
			current_accessories.append(child.name)


	var current_planet = null
	var current_planet_name = "Planet"
	if _local_player.has_method("get_current_planet"):
		current_planet = _local_player.get_current_planet()
	if "planet_name" in _local_player:
		current_planet_name = _local_player.planet_name


	_local_player.queue_free()


	await get_tree().process_frame


	var new_scene = humanoid_scene
	if character_type == "countryball":
		new_scene = countryball_scene
	elif character_type == "countryball_oneside":
		new_scene = countryball_oneside_scene


	_local_player = new_scene.instantiate()
	_local_player.name = current_name
	# Store flag_code as metadata for countryball_oneside
	if character_type == "countryball_oneside" and flag_code != "":
		_local_player.set_meta("flag_code", flag_code)


	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		workspace.add_child(_local_player)
		print("Added new local player directly to workspace")
	else:
		_player_container.add_child(_local_player)
		print("Fallback: Added new local player to player container")


	_ensure_local_player_node(_local_player)


	if _rain_system and _rain_system.has_method("update_local_player_reference"):
		_rain_system.update_local_player_reference()


	_local_player.global_position = current_position
	_local_player.rotation = current_rotation


	await get_tree().process_frame


	if _pending_spawn_position != null:
		_local_player.global_position = _pending_spawn_position
		print("Applied pending checkpoint spawn position: ", _pending_spawn_position)
		_pending_spawn_position = null



	print("New character should automatically find planetary system")


	var accessories_to_apply = _user_accessories if _user_accessories.size() > 0 else current_accessories
	if accessories_to_apply.size() > 0:
		print("Restoring accessories after transformation:", accessories_to_apply)
		apply_accessories_to_player(_local_player, accessories_to_apply)


	_start_transform_updates()

func _transform_remote_player(player_id, character_type, flag_code = ""):
	if not player_id in _players:
		return

	var old_player = _players[player_id]
	print("Transforming remote player:", old_player.name, "to:", character_type, " flag:", flag_code)


	var current_position = old_player.global_position
	var current_rotation = old_player.rotation
	var current_name = old_player.name


	var current_accessories = []
	if old_player.has_node("CharacterModel/Accessories"):
		var accessories_node = old_player.get_node("CharacterModel/Accessories")
		for child in accessories_node.get_children():
			current_accessories.append(child.name)


	var current_planet = null
	var current_planet_name = "Planet"
	if old_player.has_method("get_current_planet"):
		current_planet = old_player.get_current_planet()
	if "planet_name" in old_player:
		current_planet_name = old_player.planet_name


	old_player.queue_free()


	await get_tree().process_frame


	var new_scene = humanoid_scene
	if character_type == "countryball":
		new_scene = countryball_scene
	elif character_type == "countryball_oneside":
		new_scene = countryball_oneside_scene


	var new_player = new_scene.instantiate()
	new_player.name = current_name
	# Store flag_code as metadata for countryball_oneside
	if character_type == "countryball_oneside" and flag_code != "":
		new_player.set_meta("flag_code", flag_code)

	if new_player.has_node("XROrigin3D"):
		new_player.get_node("XROrigin3D").queue_free()

	if new_player.has_node("CamOrigin"):
		new_player.get_node("CamOrigin").queue_free()

	_player_container.add_child(new_player)


	_remove_local_player_node(new_player)


	new_player.set_as_remote_player()


	new_player.global_position = current_position
	new_player.rotation = current_rotation


	await get_tree().process_frame


	if current_planet and new_player.has_method("set_planet"):
		print("Restoring planetary system to new remote character")

		new_player.planet_node = current_planet
		new_player.planet_name = current_planet_name
		if new_player.has_method("_calc_gravity_direction"):
			new_player._calc_gravity_direction()
		print("Restored planetary system without repositioning")


	if current_accessories.size() > 0:
		print("Restoring accessories after transformation:", current_accessories)
		apply_accessories_to_player(new_player, current_accessories)


	_players[player_id] = new_player

func _remove_player(player_id):
	if player_id in _players:
		var player = _players[player_id]
		player.queue_free()
	_players.erase(player_id)

func _apply_emotion_to_player(player: Node, emotion: String) -> void:
	"""Apply an emotion to a player's countryball character"""
	if not is_instance_valid(player):
		return
	
	# First, try the set_emotion method on unified_character
	if player.has_method("set_emotion"):
		if player.set_emotion(emotion):
			print("Applied emotion '", emotion, "' to player via set_emotion: ", player.name)
			return
	
	# Second, try to get the countryball_animation from the unified character
	if player.has_method("get") and player.get("current_animation") != null:
		var animation = player.current_animation
		if animation and animation.has_method("set_emotion"):
			animation.set_emotion(emotion)
			print("Applied emotion '", emotion, "' to player via animation: ", player.name)
			return
	
	# Fallback: Try to apply emotion material directly to the Emotions mesh
	var character_model = player.find_child("CharacterModel", true, false)
	if character_model:
		var emotions_mesh = character_model.find_child("Emotions", true, false)
		if emotions_mesh and emotions_mesh is MeshInstance3D:
			var emotion_path = "res://src/countryball/Emotions/" + emotion.to_lower() + ".tres"
			var emotion_material = load(emotion_path)
			if emotion_material:
				emotions_mesh.set_surface_override_material(0, emotion_material)
				print("Applied emotion material '", emotion, "' directly to player: ", player.name)

func _start_transform_updates():

	while _connected and is_instance_valid(_local_player):
		var position = _local_player.position
		var rotation = _local_player.rotation


		var model_rotation_y = null
		if _local_player.has_node("CharacterModel"):
			model_rotation_y = _local_player.get_node("CharacterModel").rotation.y


		var on_floor = false
		if _local_player.has_method("_is_character_on_floor"):
			on_floor = _local_player._is_character_on_floor()
		elif _local_player.has_method("is_on_floor"):
			on_floor = _local_player.is_on_floor()

		var message = {
			"type": "transform_update", 
			"position": {"x": position.x, "y": position.y, "z": position.z}, 
			"rotation": {"x": rotation.x, "y": rotation.y, "z": rotation.z}, 
			"on_floor": on_floor
		}


		if model_rotation_y != null:
			message["model_rotation_y"] = model_rotation_y

		_send_message(message)
		await get_tree().create_timer(0.05).timeout

func display_chat_bubble(player_id, message):
	var player = null


	if player_id == _client_id and is_instance_valid(_local_player):
		player = _local_player

	elif player_id in _players:
		player = _players[player_id]

	if player and player.has_node("CharacterModel/ChatBubble"):
		var chat_bubble = player.get_node("CharacterModel/ChatBubble")
		var sprite = chat_bubble.get_node("Sprite3D")
		var label = player.get_node("ChatBubbleViewport/Control/TextureRect/RichTextLabel")


		label.text = message


		sprite.visible = true


		await get_tree().create_timer(3.0).timeout
		if is_instance_valid(sprite) and is_instance_valid(label):
			sprite.visible = false

func _send_message(data):
	if _connected:
		var json_string = JSON.stringify(data)
		_client.send_text(json_string)

func send_json(data):
	_send_message(data)

func send_chat_message(message):

	if message.begins_with("/save"):
		save_studio_workspace()
		return

	if message.begins_with("/load"):
		load_studio_workspace()
		return

	if message.begins_with("/upload"):
		upload_place()
		return

	if not _connected:
		return

	_send_message({
		"type": "chat_message", 
		"message": message
	})

func send_login(username: String, password: String):
	if not _connected:
		print("Not connected to server")
		return


	_pending_login_username = username
	_pending_login_password = password

	_send_message({
		"type": "login", 
		"username": username, 
		"password": password
	})
	print("Login request sent for user: ", username)

func send_register(username: String, password: String):
	if not _connected:
		print("Not connected to server")
		return

	_send_message({
		"type": "register", 
		"username": username, 
		"password": password
	})
	print("Register request sent for user: ", username)









var _sso_retry_count: = 0
const SSO_MAX_RETRIES: = 3

func _try_web_sso_login():








	if not OS.has_feature("web"):
		print("[SSO] Not running in web mode, skipping SSO")
		return

	print("[SSO] Attempting web SSO login (attempt ", _sso_retry_count + 1, "/", SSO_MAX_RETRIES, ")...")
	_setup_sso_callback()

func _setup_sso_callback():
	var callback = JavaScriptBridge.create_callback(_on_sso_token_received)


	set_meta("sso_callback", callback)



	var js_code = "\n\t\t(async function() {\n\t\t\t// Method 1: Check for pre-injected token (set by the embedding page)\n\t\t\tif (window.PBRP_SSO_TOKEN && window.PBRP_SSO_USERNAME) {\n\t\t\t\tconsole.log('[Godot SSO] Using pre-injected token for:', window.PBRP_SSO_USERNAME);\n\t\t\t\twindow.godotSSOResult = {\n\t\t\t\t\tsuccess: true, \n\t\t\t\t\ttoken: window.PBRP_SSO_TOKEN, \n\t\t\t\t\tusername: window.PBRP_SSO_USERNAME\n\t\t\t\t};\n\t\t\t\treturn;\n\t\t\t}\n\t\t\t\n\t\t\t// Method 2: Check URL parameters (for redirect scenarios)\n\t\t\tconst urlParams = new URLSearchParams(window.location.search);\n\t\t\tconst urlToken = urlParams.get('sso_token');\n\t\t\tconst urlUsername = urlParams.get('sso_username');\n\t\t\tif (urlToken && urlUsername) {\n\t\t\t\tconsole.log('[Godot SSO] Using URL token for:', urlUsername);\n\t\t\t\twindow.godotSSOResult = {\n\t\t\t\t\tsuccess: true,\n\t\t\t\t\ttoken: urlToken,\n\t\t\t\t\tusername: urlUsername\n\t\t\t\t};\n\t\t\t\treturn;\n\t\t\t}\n\t\t\t\n\t\t\t// Method 3: Fetch token from API (requires same-origin)\n\t\t\ttry {\n\t\t\t\tconsole.log('[Godot SSO] Fetching auth token from /api/game-token...');\n\t\t\t\tconst response = await fetch('/api/game-token', {\n\t\t\t\t\tmethod: 'GET',\n\t\t\t\t\tcredentials: 'same-origin',\n\t\t\t\t\theaders: {\n\t\t\t\t\t\t'Accept': 'application/json'\n\t\t\t\t\t}\n\t\t\t\t});\n\t\t\t\t\n\t\t\t\tconsole.log('[Godot SSO] Response status:', response.status);\n\t\t\t\t\n\t\t\t\tif (!response.ok) {\n\t\t\t\t\twindow.godotSSOResult = {success: false, message: 'HTTP ' + response.status + ': ' + response.statusText};\n\t\t\t\t\treturn;\n\t\t\t\t}\n\t\t\t\t\n\t\t\t\tconst data = await response.json();\n\t\t\t\tconsole.log('[Godot SSO] Response data:', data);\n\t\t\t\t\n\t\t\t\tif (data.success && data.token) {\n\t\t\t\t\twindow.godotSSOResult = {success: true, token: data.token, username: data.username};\n\t\t\t\t\tconsole.log('[Godot SSO] Token received for:', data.username);\n\t\t\t\t} else {\n\t\t\t\t\twindow.godotSSOResult = {success: false, message: data.message || 'Not authenticated on website'};\n\t\t\t\t\tconsole.log('[Godot SSO] Not authenticated:', data.message);\n\t\t\t\t}\n\t\t\t} catch (error) {\n\t\t\t\tconsole.error('[Godot SSO] Fetch error:', error);\n\t\t\t\twindow.godotSSOResult = {success: false, message: 'Fetch error: ' + (error.message || error.toString())};\n\t\t\t}\n\t\t})();\n\t"





























































	JavaScriptBridge.eval(js_code)


	await get_tree().create_timer(0.5).timeout
	_check_sso_result()

func _check_sso_result():
	var result_json = JavaScriptBridge.eval("JSON.stringify(window.godotSSOResult || {success: false, message: 'Result not set - fetch may still be pending'})")

	print("[SSO] Raw result from JS: ", result_json)

	if result_json:
		var json = JSON.new()
		var parse_result = json.parse(result_json)

		if parse_result == OK:
			var result = json.data

			if result.get("success", false):
				var token = result.get("token", "")
				var username = result.get("username", "")

				print("[SSO] Token received for user: ", username)
				_sso_retry_count = 0
				send_token_login(token)
			else:
				var message = result.get("message", "No message provided")
				print("[SSO] Token retrieval failed: ", message)


				_sso_retry_count += 1
				if _sso_retry_count < SSO_MAX_RETRIES:
					print("[SSO] Retrying in 1 second... (", _sso_retry_count, "/", SSO_MAX_RETRIES, ")")

					JavaScriptBridge.eval("window.godotSSOResult = null;")
					await get_tree().create_timer(1.0).timeout
					_try_web_sso_login()
				else:
					print("[SSO] Max retries reached. This usually means:")
					print("[SSO]   1. User is not logged in on the website, OR")
					print("[SSO]   2. Game is not served from the same origin as the website")
					_sso_retry_count = 0
		else:
			print("[SSO] Failed to parse SSO result JSON")
	else:
		print("[SSO] No SSO result available from JavaScript")

func _on_sso_token_received(args):
	if args.size() > 0:
		var result = args[0]
		print("[SSO] Callback received: ", result)

func send_token_login(token: String):
	if not _connected:
		print("[SSO] Not connected to server")
		return

	print("[SSO] Sending token login request...")
	_send_message({
		"type": "token_login", 
		"token": token
	})

func clear_saved_credentials():
	_saved_username = ""
	_saved_password = ""

	if FileAccess.file_exists(_credentials_path):
		DirAccess.remove_absolute(_credentials_path)
		print("Cleared saved credentials")
	else:
		print("No saved credentials to clear")



func _spawn_or_update_object(net_id: String, xf: Transform3D):
	var obj = _objects.get(net_id, null)
	if obj and is_instance_valid(obj):
		obj.global_transform = xf
		return

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

func _spawn_plot_object(net_id: String, object_type: String, xf: Transform3D, plot_id: String):
	var obj = _objects.get(net_id, null)
	if obj and is_instance_valid(obj):
		obj.global_transform = xf

		obj.set_meta("plot_id", plot_id)
		obj.set_meta("object_type", object_type)
		obj.set_meta("is_plot_object", true)
		print("Updated existing plot object with plot_id: ", plot_id)
		return


	var mesh_tscn_path = "res://src/assets/Objects/" + object_type + "/mesh.tscn"
	var mesh_glb_path = "res://src/assets/Objects/" + object_type + "/mesh.glb"
	var mesh_path = ""

	if FileAccess.file_exists(mesh_tscn_path):
		mesh_path = mesh_tscn_path
	elif FileAccess.file_exists(mesh_glb_path):
		mesh_path = mesh_glb_path
		print("Using fallback .glb for: ", object_type)
	else:
		print("ERROR: Plot object mesh not found: ", mesh_tscn_path, " or ", mesh_glb_path)
		return

	var loaded_scene = load(mesh_path)
	if not loaded_scene:
		print("ERROR: Failed to load plot object scene: ", mesh_path)
		return


	var new_object = loaded_scene.instantiate()
	new_object.name = net_id


	new_object.set_meta("object_type", object_type)
	new_object.set_meta("plot_id", plot_id)
	new_object.set_meta("is_plot_object", true)


	var parent_scene: Node = get_tree().current_scene
	if parent_scene == null:
		parent_scene = get_tree().get_root()
	var workspace = parent_scene.find_child("workspace", true, false)
	if not workspace:
		workspace = parent_scene

	workspace.add_child(new_object)


	new_object.global_transform = xf


	_objects[net_id] = new_object

	print("Spawned plot object: ", object_type, " (", net_id, ") from ", mesh_path)

func _check_user_plot():
	if _all_plots.is_empty():
		print("NetworkController: No plots stored to check")
		return

	if _username == "" or _username.begins_with("Guest"):
		print("NetworkController: Not authenticated, skipping plot check")
		return

	print("NetworkController: Checking ", _all_plots.size(), " plots for user: ", _username)

	for plot_info in _all_plots:
		print("NetworkController: Comparing plot owner '", plot_info.owner, "' with username '", _username, "'")

		if plot_info.owner.to_lower() == _username.to_lower():
			print("NetworkController: ✓ FOUND USER'S PLOT: ", plot_info.name)
			var boundaries = plot_info.get("boundaries", {})
			print("NetworkController: Boundaries = ", boundaries)


			var workspace = get_tree().current_scene
			if workspace:
				var plot_ui_vis = workspace.get_node_or_null("PlotUIVisibility")
				if plot_ui_vis and plot_ui_vis.has_method("set_plot_boundaries"):
					plot_ui_vis.set_plot_boundaries(boundaries)
					print("NetworkController: ✓ Successfully notified PlotUIVisibility")
					return
				else:
					print("NetworkController: ✗ PlotUIVisibility node not found or missing method")
			else:
				print("NetworkController: ✗ Workspace not found")
			return

	print("NetworkController: ✗ No plot found for user: ", _username)

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


	if not player.has_node("CharacterModel"):
		print("ERROR: Player doesn't have a CharacterModel node")
		return

	if not player.has_node("CharacterModel/Accessories"):
		print("ERROR: Player doesn't have a CharacterModel/Accessories node")
		return


	var accessories_node = player.get_node("CharacterModel/Accessories")
	print("Found Accessories node: ", accessories_node)


	for child in accessories_node.get_children():
		child.queue_free()
	print("Cleared existing accessories")


	print("Adding new accessories: ", accessories)
	for accessory_name in accessories:
		print("Attempting to add accessory: ", accessory_name)
		var success = load_and_add_accessory(accessories_node, accessory_name)
		print("Accessory add result: ", success)


func load_and_add_accessory(accessories_node, accessory_name):

	var accessory_path = "res://src/character/accessories/" + accessory_name + "/" + accessory_name + ".tscn"
	print("Looking for accessory at path: ", accessory_path)


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
	if not player:
		return "humanoid"

	# Check for countryball_oneside first (more specific match)
	if player.scene_file_path.contains("countryballoneside"):
		return "countryball_oneside"
	elif player.scene_file_path.contains("countryball") or player.has_node("CountryballModel"):
		return "countryball"
	else:
		return "humanoid"

func _mark_owned(net_id: String, obj: Node3D):
	_owned_objects[net_id] = obj
	_owned_last_sent.erase(net_id)

func _unmark_owned(net_id: String):
	_owned_objects.erase(net_id)
	_owned_last_sent.erase(net_id)


func join_place(place_name: String):
	if not _connected:
		print("Not connected to server")
		return

	print("Requesting to join place: ", place_name)
	_send_message({
		"type": "join_place", 
		"place_name": place_name
	})

func request_places_list():
	if not _connected:
		print("Not connected to server")
		return

	_send_message({
		"type": "list_places"
	})

func _set_owner_recursive(node: Node, owner_node: Node):
	node.owner = owner_node
	for child in node.get_children():
		_set_owner_recursive(child, owner_node)

func save_studio_workspace():
	var workspace = get_tree().get_root().find_child("workspace", true, false)
	if not workspace:
		workspace = get_tree().get_root().find_child("localworkspace", true, false)

	if not workspace:
		print("No workspace found to save")
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "No workspace found to save", true)
		return false

	print("Saving studio workspace to user://...")
	print("Workspace children count: ", workspace.get_child_count())



	var clean_workspace = Node3D.new()
	clean_workspace.name = "workspace"
	clean_workspace.transform = Transform3D.IDENTITY

	print("  Created clean workspace node")

	var saved_count = 0
	var skipped_count = 0


	for child in workspace.get_children():
		var child_name = child.name
		print("  Checking child: ", child_name, " (type: ", child.get_class(), ")")


		if child_name in ["UI", "NetworkController", "Players", "humanoid", "countryball", "countryball_oneside", "LocalPlayer", 
						   "AuthManager", "TextureManager", "RainSystem", 
						   "SelectionManager", "ToolManager", "CameraManager", "OBJExporter", "FreeCamera", 
						   "AudioStreamPlayer"]:
			print("    -> Skipping system node: ", child_name)
			skipped_count += 1
			continue


		if child == _local_player:
			print("    -> Skipping local player: ", child_name)
			skipped_count += 1
			continue


		if child_name.contains("Camera") or child_name.contains("XR") or child_name.contains("Cam"):
			print("    -> Skipping camera/XR node: ", child_name)
			skipped_count += 1
			continue


		print("    -> Duplicating child: ", child_name)
		var child_duplicate = child.duplicate(DUPLICATE_USE_INSTANTIATION)
		if child_duplicate:
			clean_workspace.add_child(child_duplicate)

			_set_owner_recursive(child_duplicate, clean_workspace)
			saved_count += 1
			print("       ✓ Added (children: ", child_duplicate.get_child_count(), ", owner: ", child_duplicate.owner, ")")
		else:
			print("       ✗ Failed to duplicate")

	print("Summary: Saved ", saved_count, " nodes, skipped ", skipped_count, " nodes")
	print("Clean workspace now has ", clean_workspace.get_child_count(), " children")


	var studio_scene_path = "user://studio_workspace.tscn"


	var packed_scene = PackedScene.new()
	var result = packed_scene.pack(clean_workspace)


	clean_workspace.queue_free()

	if result != OK:
		print("Failed to pack scene: ", result)
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "Failed to save studio workspace", true)
		return false


	result = ResourceSaver.save(packed_scene, studio_scene_path)

	if result != OK:
		print("Failed to save packed scene: ", result)
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "Failed to save studio workspace to file", true)
		return false


	var file_check = FileAccess.open(studio_scene_path, FileAccess.READ)
	var file_size = 0
	if file_check:
		file_size = file_check.get_length()
		file_check.close()

	print("Studio workspace saved to: ", studio_scene_path)
	print("File size: ", file_size, " bytes (", file_size / 1024.0, " KB)")

	var chat_ui = get_tree().root.find_child("ChatUI", true, false)
	if chat_ui and chat_ui.has_method("add_message"):
		chat_ui.add_message("System", "Studio workspace saved! (" + str(saved_count) + " objects, " + str(file_size / 1024.0).pad_decimals(1) + " KB)", true)
	return true

func load_studio_workspace():
	var studio_scene_path = "user://studio_workspace.tscn"


	if not FileAccess.file_exists(studio_scene_path):
		print("No saved studio workspace found")
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "No saved studio workspace found", true)
		return false

	print("Loading studio workspace from: ", studio_scene_path)


	var scene_root = get_tree().get_root()
	var workspace = scene_root.find_child("workspace", true, false)
	if not workspace:
		workspace = scene_root.find_child("localworkspace", true, false)

	if not workspace:
		print("No workspace node found")
		return false


	for child in workspace.get_children():

		if child.name in ["NetworkController", "Players", "humanoid", "countryball", "countryball_oneside", "RainSystem", "UI", "SelectionManager", "ToolManager", "CameraManager", "OBJExporter", "FreeCamera", "Lightning", "AudioStreamPlayer"]:
			continue


		if child == _local_player:
			print("  Keeping local player: ", child.name)
			continue


		child.queue_free()


	await get_tree().process_frame


	var place_scene = load(studio_scene_path)
	if not place_scene:
		print("Failed to load studio workspace scene")
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "Failed to load studio workspace", true)
		return false

	var place_root = place_scene.instantiate()

	print("Loaded workspace has ", place_root.get_child_count(), " children")


	print("Loading studio workspace content...")
	var loaded_count = 0
	for child in place_root.get_children():
		var child_name = child.name
		print("  Found child: ", child_name, " (type: ", child.get_class(), ")")


		if child_name in ["UI", "BuildUI", "ChatUI", "NetworkController", "Players", "SelectionManager", "ToolManager", "CameraManager", "OBJExporter", "FreeCamera", "Lightning", "AudioStreamPlayer"]:
			print("    -> Skipping system node: ", child_name)
			continue

		place_root.remove_child(child)
		workspace.add_child(child)
		loaded_count += 1
		print("    -> ✓ Loaded: ", child_name)

	print("Loaded ", loaded_count, " objects into workspace")


	place_root.queue_free()


	await get_tree().process_frame


	if is_instance_valid(_local_player):
		print("Local player preserved: ", _local_player.name, " at ", _local_player.global_position)

		if _local_player.global_position.y < -10:
			_local_player.global_position = Vector3(_local_player.global_position.x, 10, _local_player.global_position.z)
			print("  Repositioned player to safe height")
	else:
		print("Local player not found after load, finding or spawning...")
		var existing_player = workspace.find_child("humanoid", true, false)
		if not existing_player:
			existing_player = workspace.find_child("countryball", true, false)

		if existing_player:
			_local_player = existing_player
			print("Found existing player after load: ", existing_player.name)
			_ensure_local_player_node(_local_player)
		else:
			print("No player found, spawning new local player")
			_spawn_local_player()


	if _rain_system and _rain_system.has_method("update_local_player_reference"):
		_rain_system.update_local_player_reference()

	print("Studio workspace loaded successfully")
	var chat_ui = get_tree().root.find_child("ChatUI", true, false)
	if chat_ui and chat_ui.has_method("add_message"):
		if loaded_count > 0:
			chat_ui.add_message("System", "Studio workspace loaded! (" + str(loaded_count) + " objects)", true)
		else:
			chat_ui.add_message("System", "Studio workspace loaded (empty workspace)", true)
	return true

func upload_place(scene_path: String = ""):
	if not _connected:
		print("Not connected to server")
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "Not connected to server. Please connect first.", true)
		return

	var studio_scene_path = "user://studio_workspace.tscn"


	if not FileAccess.file_exists(studio_scene_path):
		print("No saved studio workspace found. Save your work first.")
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "No saved workspace found. Use /save first to save your work.", true)
		return

	print("Reading saved studio workspace for upload...")


	var file = FileAccess.open(studio_scene_path, FileAccess.READ)
	if not file:
		print("Failed to open saved studio workspace")
		var chat_ui = get_tree().root.find_child("ChatUI", true, false)
		if chat_ui and chat_ui.has_method("add_message"):
			chat_ui.add_message("System", "Failed to read saved workspace", true)
		return

	var scene_data = file.get_as_text()
	file.close()

	print("Scene data size: ", scene_data.length(), " bytes")


	_send_message({
		"type": "upload_place", 
		"scene_data": scene_data
	})

	print("Place upload request sent (from saved studio workspace)")
	var chat_ui = get_tree().root.find_child("ChatUI", true, false)
	if chat_ui and chat_ui.has_method("add_message"):
		chat_ui.add_message("System", "Uploading saved workspace to server...", true)

func _clean_workspace_for_upload(workspace: Node):
	var nodes_to_remove = []

	for child in workspace.get_children():
		var should_remove = false
		var node_name = child.name


		if node_name == "UI":
			should_remove = true
			print("  Marking UI node for removal (BuildUI, ChatUI, etc.)")

		elif node_name in ["humanoid", "countryball", "countryball_oneside", "LocalPlayer"]:
			should_remove = true

		elif node_name == "Players":
			print("  Clearing Players node children (keeping container)")

			var players_to_remove = []
			for player_child in child.get_children():
				players_to_remove.append(player_child)
			for player_child in players_to_remove:
				child.remove_child(player_child)
				player_child.free()


		elif node_name in ["NetworkController", "AuthManager", "TextureManager"]:
			should_remove = true

		elif node_name.contains("Camera") or node_name.contains("XR"):
			should_remove = true

		elif child is AudioStreamPlayer:
			should_remove = true

		elif node_name in ["SelectionManager", "ToolManager", "CameraManager", "OBJExporter", "FreeCamera"]:
			should_remove = true

		if should_remove:
			nodes_to_remove.append(child)


	for node in nodes_to_remove:
		print("  Removing node: ", node.name)
		workspace.remove_child(node)
		node.free()

func _switch_to_place_server(new_server_url: String, scene_path: String):
	print("Switching to place server: ", new_server_url)
	print("Loading scene: ", scene_path)


	var username = _username


	_client.close()
	_connected = false


	for player_id in _players.keys():
		_remove_player(player_id)
	_players.clear()


	var scene_root = get_tree().get_root()
	var workspace = scene_root.find_child("workspace", true, false)

	if workspace:

		for child in workspace.get_children():
			if child.name not in ["NetworkController", "Players", "humanoid", "countryball", "countryball_oneside", "RainSystem", "UI"]:
				child.queue_free()


		await get_tree().process_frame


		var ui_node = workspace.get_node_or_null("UI")
		if ui_node:
			var build_ui = ui_node.get_node_or_null("BuildUI")
			if build_ui:
				print("  Removing BuildUI from lobby UI before entering place")
				build_ui.queue_free()
			var backpack_ui = ui_node.get_node_or_null("BackpackUI")
			if backpack_ui:
				print("  Removing BackpackUI from lobby UI")
				backpack_ui.queue_free()
			var mode_toggle_ui = ui_node.get_node_or_null("ModeToggleUI")
			if mode_toggle_ui:
				print("  Removing ModeToggleUI from lobby UI")
				mode_toggle_ui.queue_free()
			var network_ui = ui_node.get_node_or_null("NetworkUI")
			if network_ui:
				print("  Removing ModeToggleUI from lobby UI")
				network_ui.queue_free()


		await get_tree().process_frame


		var place_scene = load(scene_path)
		if place_scene:
			var place_root = place_scene.instantiate()


			print("Transferring place content to workspace...")
			for child in place_root.get_children():
				var child_name = child.name


				if child_name == "UI":
					print("  Skipping UI node from place (using lobby UI instead)")
					continue
				elif child_name == "BuildUI":
					print("  Skipping BuildUI from place")
					continue
				elif child_name == "ChatUI":
					print("  Skipping ChatUI from place")
					continue

				place_root.remove_child(child)
				workspace.add_child(child)
				print("  Added: ", child_name)


			place_root.queue_free()


			_apply_checkpoint_spawn(workspace)

			print("Loaded place scene successfully")
		else:
			print("Failed to load place scene")


	server_url = new_server_url


	await get_tree().create_timer(0.5).timeout


	connect_to_server()


	await get_tree().create_timer(0.5).timeout


	if _connected:

		_send_message({
			"type": "set_identity", 
			"username": username, 
			"texture": _user_texture, 
			"character_type": _user_character_type, 
			"accessories": _user_accessories
		})
		print("Sent identity to place server: ", username, " (", _user_character_type, ") with texture: ", _user_texture, " and accessories: ", _user_accessories)


		await get_tree().create_timer(0.1).timeout
		_update_voice_chat_username()

func _apply_checkpoint_spawn(workspace: Node):
	var checkpoint = workspace.get_node_or_null("Checkpoint")

	var spawn_position = Vector3(0, 10, 0)

	if checkpoint:
		spawn_position = checkpoint.global_position
		print("Found Checkpoint at: ", spawn_position)
	else:
		print("No Checkpoint found, using default spawn position: ", spawn_position)


	await get_tree().create_timer(0.2).timeout


	if _local_player:
		_local_player.global_position = spawn_position
		print("Teleported local player to checkpoint")
	else:

		_pending_spawn_position = spawn_position
		print("Player not ready yet, will apply spawn position when created")
