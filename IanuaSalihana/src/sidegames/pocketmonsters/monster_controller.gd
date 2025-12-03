extends Node

# Monster management
var local_monsters: Array = []  # Monsters owned by local player
var remote_monsters: Dictionary = {}  # net_id -> Monster (monsters owned by other players)

# References
var network_controller = null
var local_player = null

# Monster scenes
var monster_scenes: Dictionary = {
	# Single countryball species - texture loaded from {username}_countryball.png
	"countryball": "res://src/sidegames/pocketmonsters/monsters/countryball_base.tscn",
}

# Network update
var _update_interval: float = 0.1  # Send updates 10 times per second
var _update_timer: float = 0.0

func _ready():
	# Find network controller
	network_controller = get_node_or_null("/root/NetworkController")
	if not network_controller:
		print("MonsterController: NetworkController not found")
	else:
		print("MonsterController: Connected to NetworkController")
		# Connect to login success signal to request monsters after login
		if network_controller.has_signal("login_response"):
			network_controller.login_response.connect(_on_login_success)
			print("MonsterController: Connected to login_response signal")
	
	# Connect to TextureManager's texture_loaded signal (fires AFTER texture is cached)
	var texture_manager = get_node_or_null("/root/TextureManager")
	if texture_manager:
		if texture_manager.has_signal("texture_loaded"):
			texture_manager.texture_loaded.connect(_on_texture_loaded)
			print("MonsterController: Connected to TextureManager.texture_loaded signal")
		else:
			print("MonsterController: TextureManager doesn't have texture_loaded signal!")
			# Print all signals to debug
			var signals_list = texture_manager.get_signal_list()
			print("MonsterController: TextureManager signals: ", signals_list)
	else:
		print("MonsterController: TextureManager not found!")
	
	# Wait for the scene to be ready, then start looking for local player
	await get_tree().create_timer(1.0).timeout
	_find_local_player_with_retries()
	
	# Set up a periodic check for local player if not found yet
	if not local_player or not is_instance_valid(local_player):
		_start_periodic_player_check()
	
	print("MonsterController ready (server-based spawning enabled)")

func _exit_tree():
	"""Cleanup when MonsterController is removed from scene"""
	# Despawn all local monsters and notify server
	for monster in local_monsters:
		if is_instance_valid(monster):
			_send_monster_despawn(monster)
			monster.queue_free()
	local_monsters.clear()
	
	# Cleanup remote monsters
	for net_id in remote_monsters.keys():
		var monster = remote_monsters[net_id]
		if is_instance_valid(monster):
			monster.queue_free()
	remote_monsters.clear()

func _send_monster_despawn(monster: PocketMonster):
	"""Notify server about monster despawn"""
	if not network_controller or not network_controller._connected:
		return
	
	network_controller.send_json({
		"type": "monster_despawn",
		"net_id": monster.net_id
	})

func _on_login_success(success: bool, message: String):
	"""Called when login succeeds - request monsters"""
	if success:
		print("MonsterController: Login successful, requesting monsters...")
		await get_tree().create_timer(0.5).timeout  # Small delay to ensure username is updated
		_request_player_monsters()

func _on_texture_loaded(texture_name: String, texture: Texture2D, character_type: String):
	"""Called when TextureManager finishes loading a texture"""
	# Check if this is a countryball texture (contains "_countryball")
	if not texture_name.contains("_countryball"):
		return
	
	apply_texture_to_monsters(texture_name, texture)

func _start_periodic_player_check():
	"""Periodically check for local player (in case they spawn later)"""
	while not local_player or not is_instance_valid(local_player):
		await get_tree().create_timer(2.0).timeout
		
		_find_local_player()
		
		if local_player and is_instance_valid(local_player):
			print("MonsterController: Local player found via periodic check!")
			
			# Check if authenticated
			var username = _get_current_username()
			if username != "" and not username.begins_with("Guest"):
				print("MonsterController: Player authenticated as ", username, ", requesting monsters")
				await get_tree().create_timer(0.5).timeout
				_request_player_monsters()
			else:
				print("MonsterController: Player is guest, will wait for login")
			break

func _find_local_player_with_retries():
	"""Find local player with multiple retry attempts"""
	var max_retries = 10
	var retry_interval = 0.5
	
	for attempt in range(max_retries):
		_find_local_player()
		
		if local_player and is_instance_valid(local_player):
			print("MonsterController: Local player found on attempt ", attempt + 1)
			
			# Check if player is already authenticated (not a guest)
			var username = _get_current_username()
			if username != "" and not username.begins_with("Guest"):
				print("MonsterController: Player already authenticated as ", username, ", requesting monsters")
				await get_tree().create_timer(0.5).timeout
				_request_player_monsters()
			else:
				print("MonsterController: Player is guest (", username, "), will wait for login")
			return
		
		# Wait before next attempt
		if attempt < max_retries - 1:
			await get_tree().create_timer(retry_interval).timeout
	
	print("MonsterController: Failed to find local player after ", max_retries, " attempts")

func _get_current_username() -> String:
	"""Get the current player's username from NetworkController"""
	if network_controller and "_username" in network_controller:
		return network_controller._username
	return ""

func _request_player_monsters():
	"""Request the player's monsters from the server"""
	if not network_controller or not network_controller._connected:
		print("MonsterController: Not connected to server, skipping monster request")
		return
	
	var username = _get_current_username()
	print("MonsterController: Requesting monsters for user: ", username)
	
	network_controller.send_json({
		"type": "get_player_monsters"
	})

func _find_local_player():
	"""Find the local player in the scene"""
	print("MonsterController: === Searching for local player ===")
	
	# Safety check
	if not is_inside_tree():
		print("MonsterController: ERROR - Not in scene tree yet!")
		return
	
	# Debug: Print scene tree structure
	var tree = get_tree()
	if not tree:
		print("MonsterController: ERROR - get_tree() returned null!")
		return
	
	var root = tree.get_root()
	if not root:
		print("MonsterController: ERROR - get_root() returned null!")
		return
	
	print("MonsterController: Root node children: ", root.get_child_count())
	for i in range(min(root.get_child_count(), 10)):
		var child = root.get_child(i)
		print("  - ", child.name, " (", child.get_class(), ")")
	
	# Method 1: Try to get from network controller first
	if network_controller and "_local_player" in network_controller:
		var nc_player = network_controller._local_player
		if nc_player and is_instance_valid(nc_player):
			local_player = nc_player
			print("MonsterController: ✓ Found local player from NetworkController: ", local_player.name)
			return
		else:
			print("MonsterController: NetworkController._local_player is null or invalid")
	else:
		print("MonsterController: NetworkController not available or missing _local_player")
	
	# Method 2: Try multiple workspace names
	var workspace = null
	var workspace_names = ["workspace", "Workspace", "localworkspace", "LocalWorkspace"]
	
	for ws_name in workspace_names:
		workspace = get_tree().get_root().find_child(ws_name, true, false)
		if workspace:
			print("MonsterController: Found workspace variant: ", ws_name)
			break
	
	# Also try getting current_scene as fallback
	if not workspace:
		workspace = get_tree().current_scene
		if workspace:
			print("MonsterController: Using current_scene as workspace: ", workspace.name)
	
	if workspace:
		print("MonsterController: Workspace found (", workspace.name, "), searching for player...")
		
		# First try direct children - more efficient
		var direct_children = workspace.get_children()
		print("MonsterController: Direct children of workspace: ", direct_children.size())
		for i in range(min(direct_children.size(), 15)):
			var child = direct_children[i]
			var has_local_marker = "✓" if child.has_node("LocalPlayer") else " "
			var node_type = child.get_class()
			print("  [", has_local_marker, "] ", child.name, " (", node_type, ")")
		
		# Method A: Look for LocalPlayer marker (online mode)
		for child in direct_children:
			if child.has_node("LocalPlayer"):
				local_player = child
				print("MonsterController: ✓ Found local player by LocalPlayer marker: ", local_player.name)
				return
		
		# Method B: In offline/localworkspace mode, look for humanoid or countryball directly
		if workspace.name.to_lower().contains("local"):
			print("MonsterController: Offline mode detected, looking for humanoid/countryball...")
			for child in direct_children:
				var child_name_lower = child.name.to_lower()
				if child_name_lower == "humanoid" or child_name_lower == "countryball":
					# Make sure it's a CharacterBody3D
					if child is CharacterBody3D:
						local_player = child
						print("MonsterController: ✓ Found local player in offline mode: ", local_player.name)
						return
		
		print("MonsterController: No direct child player found, searching recursively...")
		
		# Search all children recursively
		var all_children = _get_all_children_recursive(workspace)
		print("MonsterController: Found ", all_children.size(), " children in workspace tree (recursive)")
		
		for child in all_children:
			if child.has_node("LocalPlayer"):
				local_player = child
				print("MonsterController: ✓ Found local player by LocalPlayer marker (recursive): ", local_player.name)
				return
		
		# Last chance in recursive search - look for humanoid/countryball
		for child in all_children:
			var child_name_lower = child.name.to_lower()
			if (child_name_lower == "humanoid" or child_name_lower == "countryball") and child is CharacterBody3D:
				local_player = child
				print("MonsterController: ✓ Found local player in recursive search: ", local_player.name)
				return
		
		print("MonsterController: No child with LocalPlayer marker or humanoid/countryball found")
	else:
		print("MonsterController: ✗ No workspace or current_scene found!")
	
	# Method 3: Check the "local_player" group
	var local_player_group = get_tree().get_nodes_in_group("local_player")
	print("MonsterController: Checking 'local_player' group, found ", local_player_group.size(), " members")
	if local_player_group.size() > 0:
		local_player = local_player_group[0]
		print("MonsterController: ✓ Found local player from 'local_player' group: ", local_player.name)
		return
	
	# Method 4: Last resort - search ALL nodes in scene tree for LocalPlayer marker
	print("MonsterController: Last resort - searching entire scene tree...")
	var all_nodes = _get_all_children_recursive(get_tree().get_root())
	for node in all_nodes:
		if node.has_node("LocalPlayer"):
			local_player = node
			print("MonsterController: ✓ Found local player in scene tree: ", local_player.name)
			return
	
	print("MonsterController: ✗ Could not find local player by any method")

func _get_all_children_recursive(node: Node) -> Array:
	"""Recursively get all children of a node"""
	var children = []
	for child in node.get_children():
		children.append(child)
		children.append_array(_get_all_children_recursive(child))
	return children

func _give_default_monster():
	"""Give the local player a default starting monster"""
	if not local_player or not is_instance_valid(local_player):
		print("MonsterController: No local player found, cannot give default monster")
		return
	
	# Check if player already has a monster (don't give duplicates)
	if local_monsters.size() > 0:
		print("MonsterController: Local player already has ", local_monsters.size(), " monster(s)")
		return
	
	print("MonsterController: Giving default monster to local player")
	
	# Spawn a countryball as the default starter (closer for 0.2 scale world)
	spawn_monster("countryball", local_player.global_position + Vector3(0.5, 0, 0), local_player)

# Public API to manually give a monster (for commands or UI)
func give_monster_to_local_player(species: String = "countryball"):
	"""Manually give a monster to the local player"""
	if not local_player or not is_instance_valid(local_player):
		_find_local_player()
		if not local_player or not is_instance_valid(local_player):
			print("MonsterController: Cannot give monster - no local player found")
			return false
	
	var spawn_pos = local_player.global_position + Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1))
	spawn_monster(species, spawn_pos, local_player)
	return true

func spawn_monster(species: String, position: Vector3, owner_player: Node3D = null, texture: String = "") -> PocketMonster:
	"""Spawn a new monster of the given species"""
	if not monster_scenes.has(species):
		print("MonsterController: Unknown species: ", species)
		return null
	
	var scene_path = monster_scenes[species]
	if not FileAccess.file_exists(scene_path):
		print("MonsterController: Monster scene not found: ", scene_path)
		return null
	
	var monster_scene = load(scene_path)
	if not monster_scene:
		print("MonsterController: Failed to load monster scene: ", scene_path)
		return null
	
	# Instantiate the monster
	var monster: PocketMonster = monster_scene.instantiate()
	monster.name = species
	
	# Generate network ID
	var net_id = "monster_" + str(Time.get_ticks_msec()) + "_" + str(randi())
	monster.net_id = net_id
	
	# Set position
	monster.global_position = position
	
	# Set texture metadata BEFORE adding to scene (so it's included in network spawn)
	if texture != "":
		monster.set_meta("custom_texture", texture)
		monster.set_meta("pending_texture", texture)
	
	# Set owner if provided
	if owner_player:
		monster.set_owner_player(owner_player)
		
		# If this is for the local player, add to local_monsters
		if owner_player == local_player:
			local_monsters.append(monster)
	
	# Add to scene
	if not is_inside_tree():
		print("MonsterController: ERROR - Not in scene tree, cannot add monster!")
		monster.queue_free()
		return null
	
	var tree = get_tree()
	if not tree:
		print("MonsterController: ERROR - get_tree() returned null!")
		monster.queue_free()
		return null
	
	var workspace = tree.get_root().find_child("workspace", true, false)
	if not workspace:
		workspace = tree.get_root().find_child("localworkspace", true, false)
	
	if workspace:
		workspace.add_child(monster)
	else:
		tree.current_scene.add_child(monster)
	
	# Notify network if this is a local monster
	if owner_player == local_player and network_controller:
		_send_monster_spawn(monster)
	
	return monster

func spawn_remote_monster(species: String, net_id: String, position: Vector3, rotation: Vector3, texture_name: String = "") -> PocketMonster:
	"""Spawn a monster owned by a remote player"""
	if remote_monsters.has(net_id):
		# Already exists, just update position
		var monster = remote_monsters[net_id]
		monster.apply_network_transform(position, rotation)
		return monster
	
	if not monster_scenes.has(species):
		print("MonsterController: Unknown species: ", species)
		return null
	
	var scene_path = monster_scenes[species]
	if not FileAccess.file_exists(scene_path):
		print("MonsterController: Monster scene not found: ", scene_path)
		return null
	
	var monster_scene = load(scene_path)
	if not monster_scene:
		print("MonsterController: Failed to load monster scene: ", scene_path)
		return null
	
	# Instantiate the monster
	var monster: PocketMonster = monster_scene.instantiate()
	monster.name = species + "_remote"
	monster.net_id = net_id
	monster.is_local_monster = false
	
	# Add to scene (this will trigger _ready() which initializes character_model)
	if not is_inside_tree():
		print("MonsterController: ERROR - Not in scene tree, cannot add remote monster!")
		monster.queue_free()
		return null
	
	var tree = get_tree()
	if not tree:
		print("MonsterController: ERROR - get_tree() returned null for remote monster!")
		monster.queue_free()
		return null
	
	var workspace = tree.get_root().find_child("workspace", true, false)
	if not workspace:
		workspace = tree.get_root().find_child("localworkspace", true, false)
	
	if workspace:
		workspace.add_child(monster)
	else:
		tree.current_scene.add_child(monster)
	
	# Now that _ready() has run and character_model is initialized, apply rotation
	# This ensures countryball monsters rotate their character_model correctly
	monster.apply_network_transform(position, rotation)
	
	# Store in remote monsters
	remote_monsters[net_id] = monster
	
	# Apply texture if provided (for countryball monsters)
	if texture_name != "" and species == "countryball":
		monster.set_meta("custom_texture", texture_name)
		monster.set_meta("pending_texture", texture_name)  # Mark for texture_loaded signal
		_apply_monster_texture(monster, texture_name, species)
	return monster

func despawn_remote_monster(net_id: String):
	"""Remove a remote monster"""
	if remote_monsters.has(net_id):
		var monster = remote_monsters[net_id]
		monster.queue_free()
		remote_monsters.erase(net_id)

func _process(delta):
	# Send periodic updates for local monsters
	_update_timer += delta
	if _update_timer >= _update_interval:
		_update_timer = 0.0
		_send_monster_updates()

func _send_monster_updates():
	"""Send position updates for all local monsters"""
	if not network_controller or not network_controller._connected:
		return
	
	for monster in local_monsters:
		if not is_instance_valid(monster):
			continue
		
		var data = monster.get_monster_data()
		network_controller.send_json({
			"type": "monster_update",
			"monster_data": data
		})

func _send_monster_spawn(monster: PocketMonster):
	"""Notify server about a new monster spawn"""
	if not network_controller or not network_controller._connected:
		return
	
	var data = monster.get_monster_data()
	network_controller.send_json({
		"type": "monster_spawn",
		"monster_data": data
	})

func handle_monster_spawn(data: Dictionary):
	"""Handle monster spawn from network"""
	var monster_data = data.monster_data
	var species = monster_data.species
	var net_id = monster_data.net_id
	var position = Vector3(monster_data.position.x, monster_data.position.y, monster_data.position.z)
	var rotation = Vector3(monster_data.rotation.x, monster_data.rotation.y, monster_data.rotation.z)
	var texture_name = monster_data.get("texture", "")
	
	spawn_remote_monster(species, net_id, position, rotation, texture_name)

func handle_monster_update(data: Dictionary):
	"""Handle monster position update from network"""
	var monster_data = data.monster_data
	var net_id = monster_data.net_id
	
	if remote_monsters.has(net_id):
		var position = Vector3(monster_data.position.x, monster_data.position.y, monster_data.position.z)
		var rotation = Vector3(monster_data.rotation.x, monster_data.rotation.y, monster_data.rotation.z)
		remote_monsters[net_id].apply_network_transform(position, rotation)

func handle_monster_despawn(data: Dictionary):
	"""Handle monster despawn from network"""
	var net_id = data.net_id
	despawn_remote_monster(net_id)

func handle_player_monsters_list(data: Dictionary, player_ref = null):
	"""Handle receiving the player's monster list from server"""
	var monsters_data = data.get("monsters", [])
	
	print("MonsterController: ===== RECEIVED MONSTERS LIST =====")
	print("MonsterController: Received ", monsters_data.size(), " monster(s) from server")
	print("MonsterController: Data: ", monsters_data)
	print("MonsterController: Player passed: ", player_ref)
	
	# Use the player reference passed directly from NetworkController
	if player_ref and is_instance_valid(player_ref):
		local_player = player_ref
		print("MonsterController: ✓ Using player passed from NetworkController: ", local_player.name)
	elif not local_player or not is_instance_valid(local_player):
		print("MonsterController: ✗ ERROR - No valid player reference!")
		return
	
	print("MonsterController: ✓ Local player valid: ", local_player.name, " at ", local_player.global_position)
	
	# Spawn each monster the player owns
	for i in range(monsters_data.size()):
		var monster_data = monsters_data[i]
		print("MonsterController: Processing monster ", i + 1, "/", monsters_data.size())
		print("  Species: ", monster_data.get("species", "countryball"))
		print("  Texture: ", monster_data.get("texture", ""))
		
		var species = monster_data.get("species", "countryball")
		var texture_name = monster_data.get("texture", "")
		var position_offset = Vector3(randf_range(-1, 1), 0.2, randf_range(-1, 1))
		var spawn_pos = local_player.global_position + position_offset
		
		# For countryball, always use texture based on username
		if species == "countryball":
			var username = _get_current_username()
			if username != "" and not username.begins_with("Guest"):
				texture_name = username + "_countryball"
				print("  Countryball detected, using texture: ", texture_name)
		
		print("  Spawning at: ", spawn_pos)
		var monster = spawn_monster(species, spawn_pos, local_player, texture_name)
		
		if monster:
			print("  ✓ Monster spawned successfully: ", monster.net_id)
			
			# Apply texture (metadata already set in spawn_monster)
			if texture_name != "":
				print("  Applying texture: ", texture_name)
				_apply_monster_texture(monster, texture_name, species)
		else:
			print("  ✗ ERROR - Monster spawn failed!")
	
	print("MonsterController: ===== MONSTER SPAWNING COMPLETE =====")

func _apply_monster_texture(monster: PocketMonster, texture_name: String, species: String):
	"""Apply custom texture to a countryball monster"""
	if species != "countryball":
		return  # Only countryball monsters support custom textures
	
	# Check if texture manager has the texture cached
	var texture_manager = get_node_or_null("/root/TextureManager")
	if texture_manager:
		# Build cache key (texture_name + "_humanoid" for countryball textures)
		var cache_key = texture_name + "_humanoid"
		if texture_manager.texture_cache.has(cache_key):
			var texture = texture_manager.texture_cache[cache_key]
			monster.apply_countryball_texture(texture)
			return
	
	# Request texture from server if not cached
	if network_controller:
		network_controller.send_json({
			"type": "get_texture",
			"texture_name": texture_name
		})
	
	# Store reference for later application when texture arrives
	monster.set_meta("pending_texture", texture_name)

func apply_texture_to_monsters(texture_name: String, texture: Texture2D):
	"""Apply texture to all countryball monsters waiting for it"""
	# Apply to local monsters
	for monster in local_monsters:
		if is_instance_valid(monster) and monster.has_meta("pending_texture"):
			if monster.get_meta("pending_texture") == texture_name:
				monster.apply_countryball_texture(texture)
				monster.remove_meta("pending_texture")
	
	# Apply to remote monsters
	for net_id in remote_monsters.keys():
		var monster = remote_monsters[net_id]
		if is_instance_valid(monster) and monster.has_meta("pending_texture"):
			if monster.get_meta("pending_texture") == texture_name:
				monster.apply_countryball_texture(texture)
				monster.remove_meta("pending_texture")

# API for external systems
func get_local_monsters() -> Array:
	"""Get all monsters owned by local player"""
	return local_monsters

func get_monster_by_net_id(net_id: String) -> PocketMonster:
	"""Get a monster by its network ID"""
	# Check local monsters
	for monster in local_monsters:
		if monster.net_id == net_id:
			return monster
	
	# Check remote monsters
	if remote_monsters.has(net_id):
		return remote_monsters[net_id]
	
	return null
