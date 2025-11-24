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
		print("AreaLoader: Player found at ", player.global_position, " - starting area management")
		_check_and_update_areas()
	else:
		push_warning("AreaLoader: Could not find player, loading all areas by default")
		# Load all areas if no player found
		for area_name in AREA_SCENES.keys():
			_load_area(area_name)

func _find_player():
	# Try to find the local player by looking for a node with a "LocalPlayer" child
	# This is more reliable than searching by name since the player gets renamed after login
	var root = get_tree().root
	player = _find_local_player_node(root)
	if player:
		print("AreaLoader: Found local player '", player.name, "' at ", player.global_position)
	else:
		print("AreaLoader: Warning - Could not find local player (looking for node with LocalPlayer child)")

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
			print("AreaLoader: Player reference invalid, searching again...")
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
		print("AreaLoader: No valid player found, cannot check areas")
		return
	
	# Use player's position in the workspace coordinate system (local to workspace)
	# Since both player and salih1city are children of workspace, we use player.position.x
	var player_x = player.position.x
	
	# Determine which areas should be loaded based on position
	var should_load = _calculate_areas_to_load(player_x)
	
	print("AreaLoader: Player X=", player_x, " (global: ", player.global_position.x, ") Should load: ", should_load)
	
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
	
	print("  → Checking position x=", x)
	
	# Rule: Unload everything but WesternSuburbs when x < -1100
	if x < -1100:
		print("  → Zone: Far West (x < -1100) - Only WesternSuburbs")
		areas.append("WesternSuburbs")
		return areas
	
	# Rule: Unload everything but Asia when x > 900
	if x > 900:
		print("  → Zone: Far East (x > 900) - Only Asia")
		areas.append("Asia")
		return areas
	
	# Otherwise, apply individual rules
	print("  → Zone: Middle area (-1100 to 900)")
	
	# UniBack2 - no specific unload rule, so load by default
	areas.append("UniBack2")
	print("    • UniBack2: LOAD (always in middle zone)")
	
	# WesternSuburbs - unload when x > -900
	if x <= -900:
		areas.append("WesternSuburbs")
		print("    • WesternSuburbs: LOAD (x <= -900)")
	else:
		print("    • WesternSuburbs: SKIP (x > -900, currently ", x, ")")
	
	# Asia - load when x > -500
	if x > -500:
		areas.append("Asia")
		print("    • Asia: LOAD (x > -500)")
	else:
		print("    • Asia: SKIP (x <= -500, currently ", x, ")")
	
	# Historical - no specific unload rule, so load by default
	areas.append("Historical")
	print("    • Historical: LOAD (always in middle zone)")
	
	# Eyup - unload when x > -500
	if x <= -500:
		areas.append("Eyup")
		print("    • Eyup: LOAD (x <= -500)")
	else:
		print("    • Eyup: SKIP (x > -500, currently ", x, ")")
	
	# Pera - no specific unload rule, so load by default
	areas.append("Pera")
	print("    • Pera: LOAD (always in middle zone)")
	
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
		if is_instance_valid(player):
			print("AreaLoader: Loaded ", area_name, " at player x: ", player.global_position.x)
		else:
			print("AreaLoader: Loaded ", area_name)
	else:
		push_error("AreaLoader: Failed to load scene: " + scene_path)

func _unload_area(area_name: String):
	if not loaded_areas.has(area_name):
		return
	
	var node = loaded_areas[area_name]
	loaded_areas.erase(area_name)
	node.queue_free()
	if is_instance_valid(player):
		print("AreaLoader: Unloaded ", area_name, " at player x: ", player.global_position.x)
	else:
		print("AreaLoader: Unloaded ", area_name)

# Debug function to print current status
func print_status():
	if player and is_instance_valid(player):
		print("Player: ", player.name, " at X: ", player.global_position.x)
	else:
		print("Player: Not found or invalid")
	print("Loaded areas: ", loaded_areas.keys())
