extends Node3D
class_name PlanetaryController

# This script manages planetary gravity systems for characters
# Attach this to your scene to automatically manage planet-character interactions

@export var auto_assign_planets := true
@export var update_frequency := 0.1  # How often to check for planet changes (in seconds)

var characters: Array[CharacterBody3D] = []
var planets: Array[Node3D] = []
var update_timer := 0.0

func _ready():
	if auto_assign_planets:
		_find_all_characters_and_planets()
		_assign_planets_to_characters()

func _process(delta):
	if auto_assign_planets:
		update_timer += delta
		if update_timer >= update_frequency:
			update_timer = 0.0
			_update_character_planets()

func _find_all_characters_and_planets():
	"""Find all characters and planets in the scene"""
	characters.clear()
	planets.clear()
	
	_find_nodes_recursive(get_tree().current_scene)
	
	print("Found ", characters.size(), " characters and ", planets.size(), " planets")

func _find_nodes_recursive(node: Node):
	"""Recursively find characters and planets in the scene"""
	# Check if this node is a character with planetary support
	if node is CharacterBody3D and node.has_method("set_planet"):
		characters.append(node)
	
	# Check if this node is a planet (has StaticBody3D or similar)
	if node.name.to_lower().contains("planet") or node is StaticBody3D:
		if node.has_node("MeshInstance3D") or node.has_node("CollisionShape3D"):
			planets.append(node)
	
	# Recurse through children
	for child in node.get_children():
		_find_nodes_recursive(child)

func _assign_planets_to_characters():
	"""Assign the closest planet to each character"""
	for character in characters:
		var closest_planet = _find_closest_planet(character)
		if closest_planet and character.has_method("set_planet"):
			character.set_planet(closest_planet, closest_planet.name)

func _update_character_planets():
	"""Update planet assignments based on current positions"""
	for character in characters:
		if not character or not is_instance_valid(character):
			continue
			
		var closest_planet = _find_closest_planet(character)
		var current_planet = null
		
		if character.has_method("get_current_planet"):
			current_planet = character.get_current_planet()
		
		# Only update if the closest planet changed
		if closest_planet != current_planet:
			if character.has_method("set_planet"):
				character.set_planet(closest_planet, closest_planet.name if closest_planet else "space")

func _find_closest_planet(character: CharacterBody3D) -> Node3D:
	"""Find the closest planet to a character"""
	if planets.is_empty():
		return null
	
	var closest_planet: Node3D = null
	var closest_distance := INF
	
	for planet in planets:
		if not planet or not is_instance_valid(planet):
			continue
			
		var distance = character.global_position.distance_to(planet.global_position)
		if distance < closest_distance:
			closest_distance = distance
			closest_planet = planet
	
	return closest_planet

# Manual control functions
func add_character(character: CharacterBody3D):
	"""Manually add a character to be managed"""
	if character and character.has_method("set_planet"):
		characters.append(character)
		var closest_planet = _find_closest_planet(character)
		if closest_planet:
			character.set_planet(closest_planet, closest_planet.name)

func remove_character(character: CharacterBody3D):
	"""Remove a character from management"""
	var index = characters.find(character)
	if index >= 0:
		characters.remove_at(index)

func add_planet(planet: Node3D):
	"""Manually add a planet"""
	if planet:
		planets.append(planet)

func remove_planet(planet: Node3D):
	"""Remove a planet"""
	var index = planets.find(planet)
	if index >= 0:
		planets.remove_at(index)

func set_character_to_space(character: CharacterBody3D):
	"""Put a character in space (no planetary gravity)"""
	if character and character.has_method("set_planet_name"):
		character.set_planet_name("space")

func teleport_character_to_planet(character: CharacterBody3D, planet: Node3D, height_offset: float = 10.0):
	"""Teleport a character to the surface of a planet"""
	if not character or not planet:
		return
	
	# Calculate position on planet surface
	var direction = (character.global_position - planet.global_position).normalized()
	if direction.length() < 0.1:
		direction = Vector3.UP  # Fallback direction
	
	# Get planet radius (approximate)
	var planet_radius = 1.0
	if planet.has_node("CollisionShape3D"):
		var collision_shape = planet.get_node("CollisionShape3D")
		if collision_shape.shape is SphereShape3D:
			planet_radius = collision_shape.shape.radius
		elif collision_shape.shape is BoxShape3D:
			var box_shape = collision_shape.shape as BoxShape3D
			planet_radius = max(box_shape.size.x, max(box_shape.size.y, box_shape.size.z)) * 0.5
	
	# Set character position
	character.global_position = planet.global_position + direction * (planet_radius + height_offset)
	
	# Assign planet
	if character.has_method("set_planet"):
		character.set_planet(planet, planet.name)

# Debug functions
func debug_print_status():
	"""Print debug information about the current state"""
	print("=== Planetary Controller Status ===")
	print("Characters: ", characters.size())
	print("Planets: ", planets.size())
	
	for i in range(characters.size()):
		var character = characters[i]
		if not character or not is_instance_valid(character):
			continue
			
		var planet_name = "Unknown"
		var distance = 0.0
		
		if character.has_method("get_current_planet"):
			var planet = character.get_current_planet()
			if planet:
				planet_name = planet.name
				distance = character.global_position.distance_to(planet.global_position)
			else:
				planet_name = "None/Space"
		
		print("Character ", i, ": Planet = ", planet_name, ", Distance = ", distance) 