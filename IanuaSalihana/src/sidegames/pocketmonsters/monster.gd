extends CharacterBody3D
class_name PocketMonster

# Monster properties (loaded from YAML)
var monster_name: String = "Unknown"
var monster_type: String = "normal"
var base_speed: float = 3.0
var interaction_range: float = 2.0
var description: String = ""
var color: Color = Color.WHITE

# Owner and following
var owner_node: Node3D = null
var follow_distance: float = 1.8  # Increased - stays a bit farther behind
var follow_speed_multiplier: float = 1.5

# Network replication
var net_id: String = ""
var is_local_monster: bool = false

# Internal state
var _gravity: float = 20.0
var _max_follow_distance: float = 6.0  # Increased teleport threshold
var _idle_time: float = 0.0
var _wander_target: Vector3 = Vector3.ZERO
var _last_owner_position: Vector3 = Vector3.ZERO
var _teleport_cooldown: float = 0.0  # Prevent rapid teleporting

# Countryball animation (for countryball monsters)
var bounce_amount: float = 0.3
var bounce_speed: float = 8.0
var squash_amount: float = 0.2
var bounce_timer: float = 0.0
var original_scale: Vector3 = Vector3.ONE
var character_model: Node3D = null  # Will point to the countryball model

# Nodes
@onready var model: Node3D = $Model
@onready var interaction_area: Area3D = $InteractionArea
@onready var name_label: Label3D = $NameLabel

func _ready():
	# Load monster data from YAML
	_load_monster_data()
	
	# Setup interaction area
	if interaction_area:
		interaction_area.body_entered.connect(_on_body_entered_interaction)
		interaction_area.body_exited.connect(_on_body_exited_interaction)
	
	# Update name label
	if name_label:
		name_label.text = monster_name
		name_label.modulate = color  # Color the name based on monster type
	
	# Apply color to model (for non-countryball monsters)
	if _is_countryball_monster():
		# Countryball monsters use textures instead of colors
		# Setup animation for countryball
		# Find the character model (the parent of Base, Emotions, Outline)
		for child in get_children():
			if child is Node3D and child.name != "InteractionArea" and child.name != "NameLabel" and child.name != "CollisionShape3D":
				character_model = child
				original_scale = character_model.scale
				break
	elif model and model is MeshInstance3D:
		var material = StandardMaterial3D.new()
		material.albedo_color = color
		material.metallic = 0.2
		material.roughness = 0.8
		model.material_override = material
	
	# Add to monsters group
	add_to_group("monsters")

func _is_countryball_monster() -> bool:
	"""Check if this is a countryball-type monster"""
	var name_lower = name.to_lower()
	return name_lower == "countryball" or name_lower == "countryball_remote" or name_lower.begins_with("countryball")

func _load_monster_data():
	"""Load monster properties from YAML file"""
	# Determine monster species from the scene name or a metadata
	var species = "countryball"  # Default
	
	# Try to get species from parent node name or scene filename
	if name != "":
		species = name.to_lower()
	
	var yaml_path = "res://src/sidegames/pocketmonsters/data/" + species + ".yaml"
	
	# Check if YAML file exists
	if not FileAccess.file_exists(yaml_path):
		print("Warning: YAML file not found for ", species, " at ", yaml_path)
		_set_default_properties(species)
		return
	
	# Read YAML file
	var file = FileAccess.open(yaml_path, FileAccess.READ)
	if not file:
		print("Error: Could not open YAML file: ", yaml_path)
		_set_default_properties(species)
		return
	
	var yaml_content = file.get_as_text()
	file.close()
	
	# Parse YAML (simple parser for key: value format)
	_parse_yaml(yaml_content)

func _parse_yaml(content: String):
	"""Simple YAML parser for monster data"""
	var lines = content.split("\n")
	
	for line in lines:
		line = line.strip_edges()
		
		# Skip comments and empty lines
		if line.begins_with("#") or line == "":
			continue
		
		# Parse key: value
		if ":" in line:
			var parts = line.split(":", true, 1)
			if parts.size() != 2:
				continue
			
			var key = parts[0].strip_edges()
			var value = parts[1].strip_edges()
			
			# Remove quotes from string values
			if value.begins_with('"') and value.ends_with('"'):
				value = value.substr(1, value.length() - 2)
			elif value.begins_with("'") and value.ends_with("'"):
				value = value.substr(1, value.length() - 2)
			
			# Assign properties
			match key:
				"name":
					monster_name = value
				"type":
					monster_type = value
				"speed":
					base_speed = float(value)
				"interaction_range":
					interaction_range = float(value)
				"description":
					description = value
				"color":
					color = _parse_color(value)

func _parse_color(color_str: String) -> Color:
	"""Parse color from string (hex or name)"""
	if color_str.begins_with("#"):
		return Color(color_str)
	else:
		# Named colors
		match color_str.to_lower():
			"red": return Color.RED
			"green": return Color.GREEN
			"blue": return Color.BLUE
			"yellow": return Color.YELLOW
			"white": return Color.WHITE
			"black": return Color.BLACK
			_: return Color.WHITE

func _set_default_properties(species: String):
	"""Set default properties if YAML not found"""
	monster_name = species.capitalize()
	monster_type = "normal"
	base_speed = 3.0
	interaction_range = 2.0
	description = "A mysterious creature."
	color = Color.WHITE

func _physics_process(delta):
	if not is_local_monster:
		# Remote monsters are position-replicated, don't simulate physics
		return
	
	# Update teleport cooldown
	# Update teleport cooldown
	if _teleport_cooldown > 0:
		_teleport_cooldown -= delta
	
	# Apply gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta
	else:
		velocity.y = 0
	
	# Follow behavior
	if owner_node and is_instance_valid(owner_node):
		_follow_owner(delta)
	else:
		# Idle/wander behavior
		_idle_behavior(delta)
	
	# Move
	move_and_slide()
	
	# Animate countryball monsters
	if _is_countryball_monster() and character_model:
		_animate_countryball(delta)

func _follow_owner(delta):
	"""Follow the owner player"""
	var owner_pos = owner_node.global_position
	var distance = global_position.distance_to(owner_pos)
	
	# Teleport if too far away (with cooldown to prevent spam)
	if distance > _max_follow_distance and _teleport_cooldown <= 0:
		var spawn_offset = Vector3(randf_range(-0.8, 0.8), 0, randf_range(-0.5, 0.5))
		global_position = owner_pos + spawn_offset
		velocity = Vector3.ZERO  # Reset velocity after teleport
		_teleport_cooldown = 2.0  # 2 second cooldown before next teleport
		_last_owner_position = owner_pos
		return
	
	# Follow if owner is beyond follow distance
	if distance > follow_distance:
		var direction = (owner_pos - global_position).normalized()
		direction.y = 0  # Stay on ground
		
		# Speed up if owner is moving fast or is far away
		var speed = base_speed
		if distance > follow_distance * 2.0:
			speed *= follow_speed_multiplier * 1.5
		elif distance > follow_distance * 1.5:
			speed *= follow_speed_multiplier
		
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		
		# Rotate to face movement direction
		if direction.length() > 0.1:
			var target_rotation = atan2(direction.x, direction.z)
			
			# For countryball monsters, rotate the character model instead of root
			# Local monsters need PI offset because Model node in scene has 180 rotation
			if _is_countryball_monster() and character_model:
				character_model.rotation.y = lerp_angle(character_model.rotation.y, target_rotation + PI, delta * 10.0)
			else:
				rotation.y = lerp_angle(rotation.y, target_rotation, delta * 10.0)
		
		_idle_time = 0.0
	else:
		# Stop and idle near owner
		velocity.x = lerp(velocity.x, 0.0, delta * 5.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 5.0)
		_idle_time += delta
	
	_last_owner_position = owner_pos

func _idle_behavior(delta):
	"""Idle behavior when no owner"""
	velocity.x = lerp(velocity.x, 0.0, delta * 5.0)
	velocity.z = lerp(velocity.z, 0.0, delta * 5.0)

func _animate_countryball(delta):
	"""Animate countryball monster with bouncing and squashing"""
	if not character_model:
		return
	
	var speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = speed > 0.1
	var is_running = speed > base_speed * 0.8
	
	if is_moving and is_on_floor():
		# Blob-like bouncing animation
		bounce_timer += delta * bounce_speed * (2.0 if is_running else 1.0)
		
		# Create bouncing effect with sine wave
		var bounce_offset = sin(bounce_timer) * bounce_amount
		
		# Squash the ball slightly when moving (make it wider and shorter)
		var squash_factor = 1.0 - (speed / (base_speed * 2.0)) * squash_amount
		character_model.scale = Vector3(
			original_scale.x * (1.0 + squash_amount * 0.5),  # Wider
			original_scale.y * squash_factor,                 # Shorter
			original_scale.z * (1.0 + squash_amount * 0.5)   # Wider
		)
		
		# Apply bounce to position
		character_model.position.y = bounce_offset
	else:
		# Return to normal shape when not moving
		character_model.scale = character_model.scale.lerp(original_scale, delta * 5.0)
		character_model.position.y = lerp(character_model.position.y, 0.0, delta * 5.0)
		bounce_timer = 0.0
	
	# Special animation when in air (squash vertically like falling)
	if not is_on_floor():
		var fall_squash = 1.0 + abs(velocity.y) * 0.05  # More squash when falling faster
		character_model.scale = Vector3(
			original_scale.x * fall_squash,
			original_scale.y / fall_squash,
			original_scale.z * fall_squash
		)

func set_owner_player(new_owner: Node3D):
	"""Set the owner player to follow"""
	owner_node = new_owner
	is_local_monster = true
	
	if new_owner:
		_last_owner_position = new_owner.global_position

func get_monster_data() -> Dictionary:
	"""Get monster data for network replication"""
	# For countryball monsters, send character_model rotation instead of root rotation
	var rot_to_send = rotation
	if _is_countryball_monster() and character_model:
		rot_to_send = character_model.rotation
	
	var data = {
		"net_id": net_id,
		"species": name,
		"position": {
			"x": global_position.x,
			"y": global_position.y,
			"z": global_position.z
		},
		"rotation": {
			"x": rot_to_send.x,
			"y": rot_to_send.y,
			"z": rot_to_send.z
		}
	}
	
	# Include texture if set (for countryball monsters)
	if has_meta("custom_texture"):
		data["texture"] = get_meta("custom_texture")
	
	return data

func apply_network_transform(pos: Vector3, rot: Vector3):
	"""Apply transform from network (for remote monsters)"""
	if is_local_monster:
		return  # Don't apply network updates to local monsters
	
	global_position = pos
	
	# For countryball monsters, apply rotation to character_model instead of root
	if _is_countryball_monster() and character_model:
		character_model.rotation = rot
	else:
		rotation = rot

# Interaction handlers (for future battle system)
func _on_body_entered_interaction(body: Node3D):
	"""Handle when something enters interaction range"""
	print(monster_name, " detected: ", body.name)
	# Future: Trigger battle, interaction UI, etc.

func _on_body_exited_interaction(body: Node3D):
	"""Handle when something exits interaction range"""
	pass

func apply_countryball_texture(texture: Texture2D):
	"""Apply texture to countryball monster meshes"""
	if not _is_countryball_monster():
		return
	
	# Use character_model (which points to the Model node for countryball monsters)
	var model_node = character_model if character_model else model
	
	# Find the Base mesh (the main textured part)
	var base_mesh = model_node.find_child("Base", true, false)
	if base_mesh and base_mesh is MeshInstance3D:
		var material = StandardMaterial3D.new()
		material.albedo_texture = texture
		material.metallic = 0.0
		material.roughness = 1.0
		base_mesh.set_surface_override_material(0, material)

# API for future features
func interact():
	"""Called when player interacts with this monster"""
	print("Interacting with ", monster_name)
	# Future: Open battle menu, monster info, etc.

func get_interaction_prompt() -> String:
	"""Get text to show when player can interact"""
	return "Press [E] to interact with " + monster_name

