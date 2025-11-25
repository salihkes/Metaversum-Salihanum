extends Node3D
class_name AreaLoader

# Scene paths for each area
const AREA_SCENES = {
	"UniBack2": "res://src/models/salih1city/UniBack.glb",
	"WesternSuburbs": "res://src/models/salih1city/western_suburbs.tscn",
	"Asia": "res://src/models/salih1city/asia.tscn",
	"Historical": "res://src/models/salih1city/historical.tscn",
	"Eyup": "res://src/models/salih1city/eyup.tscn",
	"Pera": "res://src/models/salih1city/pera.tscn"
}

# Reference to the player (will be set automatically)
var player: Node3D = null

# Dictionary to track loaded areas
var loaded_areas: Dictionary = {}

# Check interval in seconds
@export var check_interval: float = 0.5
var time_since_check: float = 0.0

# Player recheck interval (check if player reference is still valid)
@export var player_recheck_interval: float = 1.0
var time_since_player_check: float = 0.0

func _ready():
	# Get references to existing child nodes and remove them
	# We'll manage them dynamically
	for area_name in AREA_SCENES.keys():
		var existing_node = get_node_or_null(area_name)
		if existing_node:
			existing_node.queue_free()
	
	# Wait for the scene to be fully ready
	await get_tree().process_frame
	
	# Find the player if not manually set
	if not player:
		_find_player()
		
		# If player not found yet, keep trying
		if not player:
			for i in range(10):
				await get_tree().create_timer(0.1).timeout
				_find_player()
				if player:
					break
	
	if player:
		_check_and_update_areas()
	else:
		# Load all areas if no player found
		for area_name in AREA_SCENES.keys():
			_load_area(area_name)

func _find_player():
	# Try to find the local player by looking for a node with a "LocalPlayer" child
	# This is more reliable than searching by name since the player gets renamed after login
	var root = get_tree().root
	player = _find_local_player_node(root)

func _find_local_player_node(node: Node) -> Node3D:
	# Check if this node has a "LocalPlayer" child marker
	if node.has_node("LocalPlayer"):
		return node as Node3D
	
	# Otherwise, search children recursively
	for child in node.get_children():
		var result = _find_local_player_node(child)
		if result:
			return result
	return null

func _process(delta):
	# Periodically check if player reference is still valid
	time_since_player_check += delta
	if time_since_player_check >= player_recheck_interval:
		time_since_player_check = 0.0
		
		# If player reference is invalid (freed/null), search for it again
		if not is_instance_valid(player):
			_find_player()
	
	# Only update areas if we have a valid player
	if not player or not is_instance_valid(player):
		return
	
	time_since_check += delta
	if time_since_check >= check_interval:
		time_since_check = 0.0
		_check_and_update_areas()

func _check_and_update_areas():
	if not player or not is_instance_valid(player):
		return
	
	# Use player's position in the workspace coordinate system (local to workspace)
	# Since both player and salih1city are children of workspace, we use player.position.x
	var player_x = player.position.x
	
	# Determine which areas should be loaded based on position
	var should_load = _calculate_areas_to_load(player_x)
	# Load new areas
	for area_name in should_load:
		if not loaded_areas.has(area_name):
			_load_area(area_name)
	
	# Unload areas that shouldn't be loaded
	var to_unload = []
	for area_name in loaded_areas.keys():
		if not should_load.has(area_name):
			to_unload.append(area_name)
	
	for area_name in to_unload:
		_unload_area(area_name)

func _calculate_areas_to_load(x: float) -> Array:
	var areas = []
	
	# Rule: Unload everything but WesternSuburbs when x < -1100
	if x < -1100:
		areas.append("WesternSuburbs")
		return areas
	
	# Rule: Unload everything but Asia when x > 900
	if x > 900:
		areas.append("Asia")
		return areas
	
	# Otherwise, apply individual rules
	
	# UniBack2 - no specific unload rule, so load by default
	areas.append("UniBack2")
	
	# WesternSuburbs - unload when x > -900
	if x <= -900:
		areas.append("WesternSuburbs")
	else:
		pass
	
	# Asia - load when x > -500
	if x > -500:
		areas.append("Asia")
	else:
		pass
	
	# Historical - no specific unload rule, so load by default
	areas.append("Historical")
	
	# Eyup - unload when x > -500
	if x <= -500:
		areas.append("Eyup")
	else:
		pass
	
	# Pera - no specific unload rule, so load by default
	areas.append("Pera")
	
	return areas

func _load_area(area_name: String):
	if loaded_areas.has(area_name):
		return
	
	var scene_path = AREA_SCENES[area_name]
	var scene = load(scene_path)
	if scene:
		var instance = scene.instantiate()
		instance.name = area_name
		add_child(instance)
		loaded_areas[area_name] = instance
	else:
		push_error("AreaLoader: Failed to load scene: " + scene_path)

func _unload_area(area_name: String):
	if not loaded_areas.has(area_name):
		return
	
	var node = loaded_areas[area_name]
	loaded_areas.erase(area_name)
	node.queue_free()
