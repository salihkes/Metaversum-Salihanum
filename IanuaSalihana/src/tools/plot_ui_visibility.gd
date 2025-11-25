extends Node

# Shows/hides BuildUI based on whether player is in their plot

var build_ui: Control = null
var network_controller: Node = null
var local_player: Node3D = null
var user_plot_boundaries: Dictionary = {}  # {min_x, max_x, min_y, max_y, min_z, max_z}
var check_interval: float = 0.2  # Check more frequently
var check_timer: float = 0.0

func _ready():
	await get_tree().process_frame
	
	# Get network controller
	network_controller = get_node_or_null("/root/NetworkController")
	if not network_controller:
		network_controller = get_tree().root.find_child("NetworkController", true, false)
	
	# Get BuildUI
	var workspace = get_tree().current_scene
	build_ui = workspace.get_node_or_null("UI/BuildUI")
	
	if build_ui:
		build_ui.visible = false  # Start hidden
	else:
		pass
	
	# Connect to network controller to get plot info
	if network_controller:
		# Try to get plots info if already received
		_check_for_plots_info()

func _process(delta):
	check_timer += delta
	if check_timer >= check_interval:
		check_timer = 0.0
		_update_ui_visibility()

func _check_for_plots_info():
	"""Check if we've received plots info from server"""
	# This would be called when plots_info is received
	# For now, we'll check in _update_ui_visibility
	pass

func _update_ui_visibility():
	"""Check if player is in their plot and show/hide UI accordingly"""
	if not build_ui:
		return
	
	# Always try to find local player (in case of character transformation)
	if not local_player or not is_instance_valid(local_player):
		local_player = _find_local_player()
	
	# Still no player found
	if not local_player or not is_instance_valid(local_player):
		if build_ui.visible:
			build_ui.visible = false
		return
	
	# Get username
	if not network_controller:
		if build_ui.visible:
			build_ui.visible = false
		return
	
	var username = network_controller.get("_username")
	
	if not username or username == "" or username.begins_with("Guest"):
		if build_ui.visible:
			build_ui.visible = false
		return
	
	# Get player position
	var player_pos = local_player.global_position
	
	# Check if we have plot boundaries for this user
	if user_plot_boundaries.is_empty():
		if build_ui.visible:
			build_ui.visible = false
		return
	
	var in_plot = is_position_in_plot(player_pos, user_plot_boundaries)
	
	# Only update visibility if it changed
	if build_ui.visible != in_plot:
		build_ui.visible = in_plot

func _find_local_player() -> Node3D:
	"""Find the local player node"""
	var workspace = get_tree().current_scene
	if not workspace:
		return null
	
	# First, try to get username from network controller
	if network_controller:
		var username = network_controller.get("_username")
		if username and username != "" and not username.begins_with("Guest"):
			# Look for player node by username (after character transformation)
			var player = workspace.get_node_or_null(username)
			if player and player.has_node("LocalPlayer"):
				return player
	
	# Fallback: Look for humanoid with LocalPlayer node (before transformation)
	var humanoid = workspace.find_child("humanoid", true, false)
	if humanoid and humanoid.has_node("LocalPlayer"):
		return humanoid
	
	# Fallback: look for countryball with LocalPlayer
	var countryball = workspace.find_child("countryball", true, false)
	if countryball and countryball.has_node("LocalPlayer"):
		return countryball
	
	return null

func _load_user_plot_boundaries(username: String):
	"""Load plot boundaries for the current user from network controller"""
	# This will be populated when plots_info message is received
	# For now, we'll parse it from a custom property if it exists
	if network_controller and network_controller.has_method("get_user_plot_boundaries"):
		user_plot_boundaries = network_controller.get_user_plot_boundaries(username)

func is_position_in_plot(position: Vector3, boundaries: Dictionary) -> bool:
	"""Check if a position is within plot boundaries"""
	if boundaries.is_empty():
		return false
	
	# Scale player position to world space (assuming world scale of 0.2)
	var world_scale = 5.0  # Inverse of 0.2
	var x = position.x * world_scale
	var y = position.y * world_scale
	var z = position.z * world_scale
	
	var min_x = boundaries.get("min_x")
	var max_x = boundaries.get("max_x")
	var min_y = boundaries.get("min_y")
	var max_y = boundaries.get("max_y")
	var min_z = boundaries.get("min_z")
	var max_z = boundaries.get("max_z")
	
	var x_ok = min_x <= x and x <= max_x
	var y_ok = min_y <= y and y <= max_y
	var z_ok = min_z <= z and z <= max_z
	
	var in_plot = x_ok and y_ok and z_ok
	
	if not in_plot:
		pass
	return in_plot

func set_plot_boundaries(boundaries: Dictionary):
	"""Set the plot boundaries (called from network controller when plots_info is received)"""
	user_plot_boundaries = boundaries
	_update_ui_visibility()
