extends Node

signal login_successful(username)
signal login_failed(message)
signal register_successful(username)
signal register_failed(message)

# Local storage for credentials
var config = ConfigFile.new()
var config_path = "user://credentials.cfg"
var current_username = ""
var is_authenticated = false

func _ready():
    # Load saved credentials if they exist
    var err = config.load(config_path)
    if err == OK:
        # Try to auto-login with saved credentials
        var saved_username = config.get_value("auth", "username", "")
        var saved_password = config.get_value("auth", "password", "")
        
        if saved_username != "" and saved_password != "":
            current_username = saved_username
            # We'll implement auto-login later
    
func register(username, password):
    # Send registration request to server
    var network_controller = get_node("/root/NetworkController")
    if network_controller.has_method("send_register"):
        network_controller.send_register(username, password)
    else:
        network_controller._send_message({
            "type": "register",
            "username": username,
            "password": password
        })

func login(username, password, remember_me = false):
    # Send login request to server (credentials will be saved automatically on success)
    var network_controller = get_node("/root/NetworkController")
    if network_controller.has_method("send_login"):
        network_controller.send_login(username, password)
    else:
        # Fallback to old method
        network_controller._send_message({
            "type": "login",
            "username": username,
            "password": password
        })

func logout():
    # Clear authentication state
    is_authenticated = false
    current_username = ""
    
    # Clear saved credentials (old method)
    config.set_value("auth", "username", "")
    config.set_value("auth", "password", "")
    config.save(config_path)
    
    # Clear saved credentials in network controller (new method)
    var network_controller = get_node("/root/NetworkController")
    if network_controller and network_controller.has_method("clear_saved_credentials"):
        network_controller.clear_saved_credentials()

func handle_login_response(success, message):
    if success:
        is_authenticated = true
        emit_signal("login_successful", current_username)
    else:
        emit_signal("login_failed", message)

func handle_register_response(success, message):
    if success:
        emit_signal("register_successful", current_username)
    else:
        emit_signal("register_failed", message)

func is_logged_in():
    return is_authenticated 