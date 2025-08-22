extends Node

signal texture_loaded(texture_name, texture, character_type)

# Cache for loaded textures - now keyed by "username_charactertype"
var texture_cache = {}

# Default texture for fallback
var default_texture: Texture2D

func _ready():
	# Load default texture
	default_texture = load("res://src/character/humanoid_Salih1_diff.png")
	if not default_texture:
		default_texture = load("res://icon.png")  # Fallback to icon if default texture not found

# Generate cache key from username and character type
func _get_cache_key(texture_name: String, character_type: String = "humanoid") -> String:
	return texture_name + "_" + character_type

# Load a texture by name (request from server)
func load_texture(texture_name: String, character_type: String = "humanoid"):
	var cache_key = _get_cache_key(texture_name, character_type)
	
	# Check if texture is already cached
	if texture_cache.has(cache_key):
		emit_signal("texture_loaded", texture_name, texture_cache[cache_key], character_type)
		return texture_cache[cache_key]
	
	# Request texture from server
	var network_controller = get_node("/root/NetworkController")
	network_controller._send_message({
		"type": "get_texture",
		"texture_name": texture_name
	})
	
	# Return default texture for now, will be updated when data arrives
	return default_texture

# Process texture data received from server
func process_texture_data(texture_name: String, base64_data: String, character_type: String = "humanoid"):
	print("Processing texture data for:", texture_name, "character type:", character_type)
	
	var cache_key = _get_cache_key(texture_name, character_type)
	
	# Check if texture is already cached
	if texture_cache.has(cache_key):
		print("Using cached texture for:", texture_name, "character type:", character_type)
		emit_signal("texture_loaded", texture_name, texture_cache[cache_key], character_type)
		return texture_cache[cache_key]
	
	# Decode base64 data
	var bytes = Marshalls.base64_to_raw(base64_data)
	print("Decoded base64 data, size:", bytes.size())
	
	# Create image from data
	var image = Image.new()
	var error = image.load_png_from_buffer(bytes)
	if error != OK:
		push_error("Failed to create image from texture data: " + texture_name)
		emit_signal("texture_loaded", texture_name, default_texture, character_type)
		return default_texture
	
	print("Successfully created image from data")
	
	# Create texture from image
	var texture = ImageTexture.create_from_image(image)
	print("Created texture from image")
	
	# Cache the texture with character type
	texture_cache[cache_key] = texture
	
	# Emit signal
	emit_signal("texture_loaded", texture_name, texture, character_type)
	print("Emitted texture_loaded signal for:", texture_name, "character type:", character_type)
	
	return texture

# Apply texture to a player - handles both humanoid and countryball
func apply_texture_to_player(player: Node, texture: Texture2D):
	print("TEXTURE APPLICATION to player:", player.name)
	
	# Get character type from the player
	var character_type = _get_player_character_type(player)
	
	if character_type == "countryball":
		# This is a countryball - apply texture only to the Base mesh
		var base_mesh = _get_countryball_base_mesh(player)
		if base_mesh and base_mesh is MeshInstance3D:
			print("Applying texture to countryball Base mesh only")
			apply_texture_to_mesh(base_mesh, texture)
		else:
			print("Could not find Base mesh in countryball")
	else:
		# This is a humanoid - apply to all mesh instances
		print("Applying texture to humanoid - finding all mesh instances")
		var mesh_instances = []
		find_all_mesh_instances(player, mesh_instances)
		
		print("Found", mesh_instances.size(), "mesh instances in humanoid")
		
		# Apply texture to each mesh instance
		for mesh_instance in mesh_instances:
			apply_texture_to_mesh(mesh_instance, texture)

# Get the character type from a player node
func _get_player_character_type(player: Node) -> String:
	# First, check if the player has a get_character_type method (preferred)
	if player.has_method("get_character_type"):
		return player.get_character_type()
	
	# Second, check if the player has a character_type property
	if player.has_method("get") and player.get("character_type") != null:
		return player.character_type
	
	# If no character_type property, detect based on scene structure
	var character_model = player.find_child("CharacterModel")
	if character_model:
		# Countryball has Base and Emotions nodes
		if character_model.has_node("Base") and character_model.has_node("Emotions"):
			return "countryball"
		# Humanoid has limb nodes
		elif character_model.has_node("LeftArm") and character_model.has_node("RightArm"):
			return "humanoid"
	
	# Fallback to checking for get_base_mesh method (legacy)
	if player.has_method("get_base_mesh"):
		return "countryball"
	
	# Default to humanoid if uncertain
	return "humanoid"

# Get the base mesh for a countryball character
func _get_countryball_base_mesh(player: Node) -> MeshInstance3D:
	# First, try the unified character's get_base_mesh method (preferred)
	if player.has_method("get_base_mesh"):
		var base_mesh = player.get_base_mesh()
		if base_mesh and base_mesh is MeshInstance3D:
			return base_mesh
	
	# Second, try to get it from the current_animation if it's a CountryballAnimation
	if player.has_method("get") and player.get("current_animation") != null:
		var animation = player.current_animation
		if animation.has_method("get_base_mesh"):
			var base_mesh = animation.get_base_mesh()
			if base_mesh and base_mesh is MeshInstance3D:
				return base_mesh
	
	# Third, try to get it directly from the character model structure
	var character_model = player.find_child("CharacterModel")
	if character_model:
		var base_mesh = character_model.find_child("Base")
		if base_mesh and base_mesh is MeshInstance3D:
			return base_mesh
	
	return null

# Apply texture to a specific mesh instance
func apply_texture_to_mesh(mesh_instance: MeshInstance3D, texture: Texture2D):
	if not mesh_instance or not texture:
		return
	
	print("Applying texture to mesh:", mesh_instance.name)
	
	# Create a new material
	var material = StandardMaterial3D.new()
	material.albedo_texture = texture
	
	# Apply to all surfaces
	if mesh_instance.mesh:
		for i in range(mesh_instance.mesh.get_surface_count()):
			mesh_instance.set_surface_override_material(i, material)
			print("Applied texture to surface", i, "of", mesh_instance.name)

# Find all mesh instances in a node
func find_all_mesh_instances(node: Node, result: Array):
	if node is MeshInstance3D:
		result.append(node)
	
	for child in node.get_children():
		find_all_mesh_instances(child, result)

# Apply texture by username and character type
func apply_texture_by_username(username: String, character_type: String = "humanoid"):
	print("Attempting to apply texture for username:", username, "character type:", character_type)
	
	var cache_key = _get_cache_key(username, character_type)
	
	if not texture_cache.has(cache_key):
		print("No texture found for username:", username, "character type:", character_type)
		return
	
	var texture = texture_cache[cache_key]
	var network_controller = get_node_or_null("/root/NetworkController")
	if not network_controller:
		print("NetworkController not found")
		return
	
	print("NetworkController found, username:", network_controller._username, "texture_name:", username)
	
	# Apply to local player if username matches
	if network_controller._username == username:
		var local_player = network_controller._local_player
		if is_instance_valid(local_player):
			var local_character_type = _get_player_character_type(local_player)
			if local_character_type == character_type:
				print("Local player is valid, applying texture directly")
				apply_texture_to_player(local_player, texture)
	else:
		print("Username mismatch: local=", network_controller._username, "texture=", username)
		
		# Check if this is a texture for a remote player
		for player_id in network_controller._players:
			var player = network_controller._players[player_id]
			if player.name == username:
				var remote_character_type = _get_player_character_type(player)
				if remote_character_type == character_type:
					print("Applying texture to remote player:", username)
					apply_texture_to_player(player, texture)

# Debug function to print the character model hierarchy
func debug_print_character_model(character_model: Node3D, indent: String = ""):
	if not is_instance_valid(character_model):
		print("Invalid character model")
		return
		
	print(indent + character_model.name + " (" + character_model.get_class() + ")")
	
	if character_model is MeshInstance3D:
		var mesh = character_model.mesh
		if mesh:
			print(indent + "  - Has mesh: " + str(mesh.get_class()))
			for i in range(mesh.get_surface_count()):
				var material = mesh.surface_get_material(i)
				if material:
					print(indent + "    - Surface " + str(i) + " material: " + str(material.get_class()))
					if material is StandardMaterial3D and material.albedo_texture:
						print(indent + "      - Has albedo texture")
		
		for i in range(character_model.get_surface_override_material_count()):
			var material = character_model.get_surface_override_material(i)
			if material:
				print(indent + "  - Surface override " + str(i) + " material: " + str(material.get_class()))
	
	for child in character_model.get_children():
		debug_print_character_model(child, indent + "  ") 
