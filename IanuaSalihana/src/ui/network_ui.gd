extends Control

@onready var connect_disconnect_button = $ColorRect/HBoxContainer/ConnectDisconnect
@onready var save_place_button = $ColorRect/HBoxContainer/SavePlace
@onready var load_place_button = $ColorRect/HBoxContainer/LoadPlace
@onready var upload_place_button = $ColorRect/HBoxContainer/UploadPlace

var _network_controller = null
var _is_connected = false

func _ready():
	# Find the network controller
	_network_controller = get_node_or_null("/root/NetworkController")
	if not _network_controller:
		_network_controller = get_tree().root.find_child("NetworkController", true, false)
	
	# Connect button signals
	connect_disconnect_button.pressed.connect(_on_connect_disconnect_pressed)
	save_place_button.pressed.connect(_on_save_place_pressed)
	load_place_button.pressed.connect(_on_load_place_pressed)
	upload_place_button.pressed.connect(_on_upload_place_pressed)
	
	# Initial state - start disconnected
	_update_ui_state(false)

func _process(_delta):
	# Check connection state from network controller
	if _network_controller:
		var connected = _network_controller._connected
		if connected != _is_connected:
			_is_connected = connected
			_update_ui_state(_is_connected)

func _update_ui_state(connected: bool):
	"""Update UI based on connection state"""
	if connected:
		# Connected state
		connect_disconnect_button.text = "Disconnect"
		upload_place_button.visible = true
		
		# Hide save/load when connected (they're for offline use)
		save_place_button.visible = false
		load_place_button.visible = false
	else:
		# Disconnected state
		connect_disconnect_button.text = "Connect"
		upload_place_button.visible = false
		
		# Show save/load when disconnected (offline mode)
		save_place_button.visible = true
		load_place_button.visible = true

func _on_connect_disconnect_pressed():
	"""Toggle connection to server"""
	connect_disconnect_button.release_focus()  # Remove focus to prevent stuck highlight
	
	if not _network_controller:
		print("Network controller not found")
		return
	
	if _is_connected:
		# Disconnect
		_network_controller.disconnect_from_server()
		_show_chat_message("Disconnected from server")
	else:
		# Connect
		_network_controller.connect_to_server()
		_show_chat_message("Connecting to server...")

func _on_save_place_pressed():
	"""Save the studio workspace locally"""
	save_place_button.release_focus()  # Remove focus to prevent stuck highlight
	
	if not _network_controller:
		print("Network controller not found")
		return
	
	_network_controller.save_studio_workspace()

func _on_load_place_pressed():
	"""Load the studio workspace from local storage"""
	load_place_button.release_focus()  # Remove focus to prevent stuck highlight
	
	if not _network_controller:
		print("Network controller not found")
		return
	
	_network_controller.load_studio_workspace()

func _on_upload_place_pressed():
	"""Upload the saved workspace to server (requires connection)"""
	upload_place_button.release_focus()  # Remove focus to prevent stuck highlight
	
	if not _network_controller:
		print("Network controller not found")
		return
	
	if not _is_connected:
		_show_chat_message("Cannot upload: Not connected to server")
		return
	
	_network_controller.upload_place()

func _show_chat_message(message: String):
	"""Display a message in the chat UI"""
	var chat_ui = get_tree().root.find_child("ChatUI", true, false)
	if chat_ui and chat_ui.has_method("add_message"):
		chat_ui.add_message("System", message, true)

