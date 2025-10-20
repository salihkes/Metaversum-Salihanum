extends Control

signal message_sent(text)

@onready var chat_display = $VBoxContainer/ChatDisplay
@onready var input_field = $VBoxContainer/InputContainer/InputField
@onready var send_button = $VBoxContainer/InputContainer/SendButton

var max_messages = 50
var message_timeout = 10.0  # Messages fade after this many seconds
var messages = []

func _ready():
	# Connect signals
	input_field.text_submitted.connect(_on_input_field_submitted)
	send_button.pressed.connect(_on_send_button_pressed)
	
	# Initial setup
	chat_display.text = ""
	
	# Set up fade timer
	var timer = Timer.new()
	timer.wait_time = 1.0  # Check every second
	timer.autostart = true
	timer.timeout.connect(_on_fade_timer_timeout)
	add_child(timer)
	
	# Connect to auth manager signals
	var auth_manager = get_node_or_null("/root/AuthManager")
	if not auth_manager:
		await get_tree().process_frame
		auth_manager = get_node("/root/AuthManager")
	
	auth_manager.login_successful.connect(_on_login_successful)
	auth_manager.login_failed.connect(_on_login_failed)
	auth_manager.register_successful.connect(_on_register_successful)
	auth_manager.register_failed.connect(_on_register_failed)
	
	# Add welcome message with login instructions
	add_message("System", "Welcome! Type /help for available commands.", true)

func _input(event):
	# Toggle chat with T key
	if event is InputEventKey and event.pressed and event.keycode == KEY_T and not input_field.has_focus():
		input_field.grab_focus()
		get_viewport().set_input_as_handled()
	
	# Hide chat with Escape
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and input_field.has_focus():
		input_field.release_focus()
		get_viewport().set_input_as_handled()

func add_message(username, text, is_system = false):
	var timestamp = Time.get_unix_time_from_system()
	var message = {
		"username": username,
		"text": text,
		"timestamp": timestamp,
		"is_system": is_system
	}
	
	messages.append(message)
	
	# Limit number of messages
	if messages.size() > max_messages:
		messages.pop_front()
	
	_update_chat_display()

func _update_chat_display():
	chat_display.text = ""
	
	for message in messages:
		var prefix = "[System]: " if message.is_system else "[" + message.username + "]: "
		var color = "#AAAAFF" if message.is_system else "#FFFFFF"
		
		# Calculate opacity based on age
		var age = Time.get_unix_time_from_system() - message.timestamp
		var opacity = 1.0
		if age > message_timeout - 2.0:  # Start fading 2 seconds before timeout
			opacity = max(0.0, (message_timeout - age) / 2.0)
		
		if opacity > 0.1:  # Only show messages that aren't fully faded
			var opacity_hex = "%02X" % int(opacity * 255)
			chat_display.text += "[color=#" + color.substr(1) + opacity_hex + "]" + prefix + message.text + "[/color]\n"

func _on_input_field_submitted(text):
	if text.strip_edges() == "":
		input_field.release_focus()
		return
	
	# Check if it's a command
	if text.begins_with("/"):
		_handle_command(text)
	else:
		# Regular chat message
		emit_signal("message_sent", text)
	
	input_field.text = ""
	input_field.release_focus()

func _on_send_button_pressed():
	var text = input_field.text.strip_edges()
	if text != "":
		# Check if it's a command
		if text.begins_with("/"):
			_handle_command(text)
		else:
			# Regular chat message
			emit_signal("message_sent", text)
		input_field.text = ""
	input_field.release_focus()

func _on_fade_timer_timeout():
	# Remove messages that are too old
	var current_time = Time.get_unix_time_from_system()
	var i = 0
	while i < messages.size():
		if current_time - messages[i].timestamp > message_timeout + 2.0:  # Keep them a bit longer than the fade
			messages.remove_at(i)
		else:
			i += 1
	
	_update_chat_display()

func _handle_command(command_text):
	var parts = command_text.split(" ")
	var command = parts[0].to_lower()
	
	match command:
		"/help":
			add_message("System", "Available commands:", true)
			add_message("System", "/register <username> <password> - Create account (lobby only)", true)
			add_message("System", "/login <username> <password> - Log in (lobby only)", true)
			add_message("System", "/logout - Log out from your account", true)
			add_message("System", "/transform <type> - Transform character (humanoid/countryball)", true)
			add_message("System", "/places - List available places to join", true)
			add_message("System", "/join <place_name> - Join a place (login first!)", true)
			add_message("System", "/lobby - Return to lobby", true)
			add_message("System", "/upload_place [path] - Upload your place (requires login)", true)
			add_message("System", "/help - Show this help message", true)
		
		"/register":
			if parts.size() < 3:
				add_message("System", "Usage: /register <username> <password>", true)
				return
			
			var username = parts[1]
			var password = parts[2]
			
			# Validate username and password
			if username.length() < 3:
				add_message("System", "Username must be at least 3 characters long", true)
				return
			
			if password.length() < 6:
				add_message("System", "Password must be at least 6 characters long", true)
				return
			
			# Get auth manager and register
			var auth_manager = get_node("/root/AuthManager")
			auth_manager.current_username = username
			auth_manager.register(username, password)
			
			add_message("System", "Registering...", true)
		
		"/login":
			if parts.size() < 3:
				add_message("System", "Usage: /login <username> <password>", true)
				return
			
			var username = parts[1]
			var password = parts[2]
			
			# Get auth manager and login
			var auth_manager = get_node("/root/AuthManager")
			auth_manager.current_username = username
			auth_manager.login(username, password, true)  # true for remember_me
			
			add_message("System", "Logging in...", true)
		
		"/logout":
			var auth_manager = get_node("/root/AuthManager")
			if auth_manager.is_logged_in():
				auth_manager.logout()
				add_message("System", "You have been logged out", true)
			else:
				add_message("System", "You are not logged in", true)
		
		"/transform":
			if parts.size() < 2:
				add_message("System", "Usage: /transform <type> (humanoid/countryball)", true)
				return
			
			var character_type = parts[1].to_lower()
			if character_type in ["humanoid", "countryball"]:
				# Send the transform command as a chat message to the server
				emit_signal("message_sent", command_text)
				add_message("System", "Transforming to " + character_type + "...", true)
			else:
				add_message("System", "Invalid character type. Use 'humanoid' or 'countryball'", true)
		
		"/places":
			# Request list of available places from the server
			var network_controller = get_node_or_null("/root/NetworkController")
			if not network_controller:
				network_controller = get_tree().root.find_child("NetworkController", true, false)
			
			if network_controller and network_controller.has_method("request_places_list"):
				network_controller.request_places_list()
				add_message("System", "Requesting places list...", true)
			else:
				add_message("System", "Network controller not found", true)
		
		"/join":
			if parts.size() < 2:
				add_message("System", "Usage: /join <place_name>", true)
				return
			
			var place_name = parts[1]
			
			# Get network controller and request to join place
			var network_controller = get_node_or_null("/root/NetworkController")
			if not network_controller:
				network_controller = get_tree().root.find_child("NetworkController", true, false)
			
			if network_controller and network_controller.has_method("join_place"):
				network_controller.join_place(place_name)
				add_message("System", "Joining place '" + place_name + "'...", true)
			else:
				add_message("System", "Network controller not found", true)
		
		"/upload_place":
			# Get network controller first
			var network_controller = get_node_or_null("/root/NetworkController")
			if not network_controller:
				network_controller = get_tree().root.find_child("NetworkController", true, false)
			
			if not network_controller:
				add_message("System", "Network controller not found", true)
				return
			
			# Check if user is logged in via NetworkController
			var username = network_controller._username if "_username" in network_controller else ""
			if username == "" or username.begins_with("Guest"):
				add_message("System", "You must be logged in to upload places", true)
				add_message("System", "Use /login <username> <password> to log in", true)
				return
			
			# Optional: custom scene path
			var scene_path = ""
			if parts.size() >= 2:
				scene_path = parts[1]
			
			if network_controller.has_method("upload_place"):
				add_message("System", "Uploading your place to the server...", true)
				network_controller.upload_place(scene_path)
			else:
				add_message("System", "Network controller not found", true)
		
		"/lobby":
			# Return to lobby
			add_message("System", "Returning to lobby...", true)
			add_message("System", "Note: This will reload the scene. Your unsaved work will be lost!", true)
			get_tree().reload_current_scene()
		
		_:
			add_message("System", "Unknown command. Type /help for available commands.", true)

func _on_login_successful(username):
	add_message("System", "Login successful. Welcome, " + username + "!", true)

func _on_login_failed(message):
	add_message("System", "Login failed: " + message, true)

func _on_register_successful(username):
	add_message("System", "Registration successful! You can now log in with /login " + username + " <your-password>", true)

func _on_register_failed(message):
	add_message("System", "Registration failed: " + message, true) 
