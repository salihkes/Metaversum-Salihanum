extends Node

# Camera Manager for switching between Player Camera and Free Camera
# Similar to ROBLOX Studio camera toggle

enum CameraMode {
	PLAYER,
	FREE
}

var current_mode: CameraMode = CameraMode.PLAYER

# Camera references
var player_camera: Node3D = null
var free_camera: Node3D = null
var player_character: Node3D = null

# UI references
var toggle_label: Label = null

func _ready():
	# Wait for scene to be ready
	await get_tree().process_frame
	
	var workspace = get_tree().current_scene
	
	# Get camera references
	player_character = workspace.get_node_or_null("humanoid")
	if player_character:
		player_camera = player_character.get_node_or_null("CamOrigin")
	
	free_camera = workspace.get_node_or_null("FreeCamera")
	
	# Get UI references
	toggle_label = workspace.get_node_or_null("UI/CameraToggleUI/Panel/Label")
	
	# Start in player mode
	set_camera_mode(CameraMode.PLAYER)
	update_ui()

func _input(event):
	# Toggle camera with F key (like ROBLOX Studio uses Shift+P, but F is simpler)
	if event.is_action_pressed("ui_focus_next"):  # F key by default
		toggle_camera_mode()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F:
			toggle_camera_mode()

func toggle_camera_mode():
	if current_mode == CameraMode.PLAYER:
		set_camera_mode(CameraMode.FREE)
	else:
		set_camera_mode(CameraMode.PLAYER)

func set_camera_mode(mode: CameraMode):
	current_mode = mode
	
	match mode:
		CameraMode.PLAYER:
			# Switch to player camera
			if free_camera and free_camera.has_method("deactivate"):
				free_camera.deactivate()
			
			if player_character:
				var cam_origin = player_character.get_node_or_null("CamOrigin")
				if cam_origin:
					var cam = cam_origin.get_node_or_null("CamLook/Camera3D")
					if cam:
						cam.current = true
				
				# Re-enable character physics and input
				player_character.set_physics_process(true)
				if player_character.has_method("set_input_enabled"):
					player_character.set_input_enabled(true)
			
			print("Switched to Player Camera")
		
		CameraMode.FREE:
			# Switch to free camera
			if player_character:
				var cam_origin = player_character.get_node_or_null("CamOrigin")
				if cam_origin:
					var cam = cam_origin.get_node_or_null("CamLook/Camera3D")
					if cam:
						cam.current = false
				
				# Disable character physics and input completely
				player_character.set_physics_process(false)
				if player_character.has_method("set_input_enabled"):
					player_character.set_input_enabled(false)
			
			if free_camera and free_camera.has_method("activate"):
				# Position free camera at player camera position
				if player_character:
					var cam_origin = player_character.get_node_or_null("CamOrigin")
					if cam_origin:
						var cam_look = cam_origin.get_node_or_null("CamLook")
						var player_cam = cam_look.get_node_or_null("Camera3D") if cam_look else null
						if player_cam:
							free_camera.global_position = player_cam.global_position
							free_camera.global_rotation = Vector3(cam_look.global_rotation.x, player_character.rotation.y, 0)
				
				free_camera.activate()
			
			print("Switched to Free Camera")
	
	update_ui()

func update_ui():
	if toggle_label:
		match current_mode:
			CameraMode.PLAYER:
				toggle_label.text = "Camera: Player (F to toggle)"
			CameraMode.FREE:
				toggle_label.text = "Camera: Free (F to toggle)"

func get_active_camera() -> Camera3D:
	"""Returns the currently active camera"""
	match current_mode:
		CameraMode.PLAYER:
			if player_character:
				var cam_origin = player_character.get_node_or_null("CamOrigin")
				if cam_origin:
					return cam_origin.get_node_or_null("CamLook/Camera3D")
		CameraMode.FREE:
			if free_camera:
				return free_camera.get_node_or_null("Camera3D")
	return null

func is_free_camera_active() -> bool:
	return current_mode == CameraMode.FREE

