extends Node3D

@onready var network_controller = $NetworkController
@onready var chat_ui = $UI/ChatUI

func _ready():
	# Connect chat signals
	network_controller = get_tree().root.get_node("/root/NetworkController")
	chat_ui.message_sent.connect(_on_chat_message_sent)
	network_controller.chat_message_received.connect(_on_chat_message_received)
	network_controller.system_message_received.connect(_on_system_message_received)
	
	# Add welcome message
	chat_ui.add_message("System", "Welcome to the multiplayer chat! Press T to start typing.", true)

	# Connect to auth manager signals if it exists
	var auth_manager = get_node_or_null("/root/AuthManager")
	if auth_manager:
		auth_manager.login_successful.connect(_on_login_successful)
	else:
		# Wait for auth manager to be created
		await get_tree().process_frame
		auth_manager = get_node("/root/AuthManager")
		if auth_manager:
			auth_manager.login_successful.connect(_on_login_successful)

	# Connect to network controller texture signals
	network_controller.texture_info_received.connect(_on_texture_info_received)

func _on_chat_message_sent(message):
	print("Sending chat message to server: ", message)
	# Send message to server
	network_controller.send_chat_message(message)
	
	# Display chat bubble for local player
	var local_player = network_controller._local_player
	if is_instance_valid(local_player):
		local_player.show_chat_bubble(message)

func _on_chat_message_received(username, message):
	chat_ui.add_message(username, message)

func _on_system_message_received(message):
	chat_ui.add_message("System", message, true)
	
	# Check for username change messages
	if message.contains(" is now known as "):
		var parts = message.split(" is now known as ")
		if parts.size() == 2:
			var old_username = parts[0]
			var new_username = parts[1]
			
			# Try to apply texture after username change
			var texture_manager = get_node_or_null("/root/TextureManager")
			if texture_manager:
				# Wait a short time to ensure username is updated
				await get_tree().create_timer(0.2).timeout
				texture_manager.apply_texture_by_username(new_username)
				
				# Try again after a longer delay as a fallback
				await get_tree().create_timer(1.0).timeout
				texture_manager.apply_texture_by_username(new_username)

func _on_login_successful(username):
	# You could update the player's appearance or name here
	# For now, just add a system message
	network_controller.send_chat_message("Hello everyone, I just logged in!") 

func _on_texture_info_received(texture_name):
	# This is called when the server sends texture info for the local player
	chat_ui.add_message("System", "Applying your custom texture...", true)
	
	# The actual texture application is handled in the network controller 
