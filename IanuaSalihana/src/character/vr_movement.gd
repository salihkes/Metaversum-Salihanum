extends MovementBase
class_name VRMovement

# VR-specific movement implementation

var xr_origin: XROrigin3D
var xr_camera: XRCamera3D
var movement_input := Vector2.ZERO
var rotation_input := 0.0  # For smooth camera rotation

# VR state tracking
var left_hand_grip_pressed := false
var right_hand_grip_pressed := false
var is_vr_active := false
var jump_just_pressed := false
var first_button_pressed := false  # Track if any button has been pressed to trigger auto-connect

# VR rotation settings
@export var vr_rotation_speed := 90.0  # Degrees per second at full joystick tilt

# NPC interaction
var current_npc: Node = null
var npc_in_range = false

# Signal for VR mode change
signal vr_mode_changed(is_active: bool)

func setup(char: CharacterBody3D, model: Node3D) -> void:
	super.setup(char, model)
	
	# Get XR components
	xr_origin = character.find_child("XROrigin3D")
	xr_camera = xr_origin.find_child("XRCamera3D") if xr_origin else null
	
	# Copy VR-specific parameters
	walk_speed = 2.0  # Slower for VR
	run_speed = 4.0
	jump_velocity = 8.0
	
	# Connect VR controller signals
	_connect_vr_controllers()
	
	# Find NPC for interaction
	_find_npc()

func _connect_vr_controllers():
	if not xr_origin:
		return
	
	var left_hand = xr_origin.find_child("LeftHand")
	var right_hand = xr_origin.find_child("RightHand")
	
	if left_hand:
		if not left_hand.button_pressed.is_connected(_on_left_hand_button_pressed):
			left_hand.button_pressed.connect(_on_left_hand_button_pressed)
		if not left_hand.button_released.is_connected(_on_left_hand_button_released):
			left_hand.button_released.connect(_on_left_hand_button_released)
		if not left_hand.input_vector2_changed.is_connected(_on_left_hand_input_vector_2_changed):
			left_hand.input_vector2_changed.connect(_on_left_hand_input_vector_2_changed)
		print("Connected left hand controller")
	
	if right_hand:
		if not right_hand.button_pressed.is_connected(_on_right_hand_button_pressed):
			right_hand.button_pressed.connect(_on_right_hand_button_pressed)
		if not right_hand.button_released.is_connected(_on_right_hand_button_released):
			right_hand.button_released.connect(_on_right_hand_button_released)
		if not right_hand.input_vector2_changed.is_connected(_on_right_hand_input_vector_2_changed):
			right_hand.input_vector2_changed.connect(_on_right_hand_input_vector_2_changed)
		print("Connected right hand controller")

func _handle_first_button_press():
	"""Handle auto-connection on first VR button press"""
	if not first_button_pressed and is_vr_active:
		first_button_pressed = true
		
		# Get the NetworkController and trigger connection
		if not character:
			return
		
		var network_controller = character.get_tree().root.get_node_or_null("/root/NetworkController")
		if network_controller and network_controller.has_method("connect_to_server"):
			network_controller.connect_to_server()
		
		# Also connect MicrophoneSender to voice server
		var workspace = character.get_tree().root.find_child("workspace", true, false)
		if workspace:
			var mic_sender = workspace.find_child("MicrophoneSender", true, false)
			if mic_sender and mic_sender.has_method("connect_to_voice_server"):
				mic_sender.connect_to_voice_server()

func update_input(delta: float) -> void:
	if not is_vr_active:
		movement_direction = Vector3.ZERO
		is_running = false
		is_jumping = false
		jump_just_pressed = false
		rotation_input = 0.0
		return
	
	# Handle jump (only true for one frame)
	is_jumping = jump_just_pressed
	jump_just_pressed = false  # Reset after one frame
	
	# Handle VR camera rotation
	if abs(rotation_input) > 0.1 and xr_origin:
		var rotation_amount = rotation_input * vr_rotation_speed * delta
		xr_origin.rotate_y(deg_to_rad(-rotation_amount))  # Negative for intuitive right = turn right
	
	# Get movement direction from VR controller input
	if movement_input != Vector2.ZERO:
		movement_direction = _get_vr_movement_direction(movement_input)
	else:
		movement_direction = Vector3.ZERO
	
	# Update VR camera-based character model rotation
	_update_vr_character_rotation()
	
	# Check for NPCs in range
	_update_npc_interaction()

func _get_vr_movement_direction(input_dir: Vector2) -> Vector3:
	if not xr_camera:
		return Vector3.ZERO
	
	# Override the camera relative direction for VR to fix forward/backward
	var camera_transform = xr_camera.get_global_transform()
	
	if planet_node:
		# Planetary movement - relative to surface
		var up = -gravity_direction
		var camera_forward = -camera_transform.basis.z
		
		# Project camera forward onto the planet surface plane
		var forward = camera_forward - camera_forward.project(up)
		if forward.length() < 0.1:
			# Fallback if camera is looking straight up or down
			forward = character.transform.basis.z
		forward = forward.normalized()
		
		# Calculate right vector perpendicular to both up and forward
		var right = forward.cross(up).normalized()
		
		# VR fix: Use +input_dir.y instead of -input_dir.y for forward/backward
		return (forward * input_dir.y + right * input_dir.x).normalized()
	else:
		# Regular movement - ignore Y component
		var forward = -camera_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		
		var right = camera_transform.basis.x
		right.y = 0
		right = right.normalized()
		
		# VR fix: Use +input_dir.y instead of -input_dir.y for forward/backward
		return (forward * input_dir.y + right * input_dir.x).normalized()

func _update_vr_character_rotation():
	if not xr_camera:
		return
	
	var camera_basis = xr_camera.get_global_transform().basis
	var camera_forward = -camera_basis.z
	
	if planet_node:
		# For planetary movement, project camera forward onto surface
		var up = -gravity_direction
		camera_forward = camera_forward - camera_forward.project(up)
	else:
		# Regular movement - ignore Y component
		camera_forward.y = 0
	
	if camera_forward.length() > 0.1:
		var camera_rotation = atan2(camera_forward.x, camera_forward.z) + PI
		character_model.rotation.y = camera_rotation

func _find_npc():
	# Hard-coded path to the NPC for interaction
	current_npc = character.get_node_or_null("/root/workspace/NPC2/Skeleton3D")
	if current_npc:
		print("VR: Found NPC for interaction: " + current_npc.name)

func _update_npc_interaction():
	if not current_npc or not current_npc.get_parent():
		return
	
	# Check distance to NPC with extended range for VR
	var distance = current_npc.get_parent().global_position.distance_to(character.global_position)
	var interaction_distance = current_npc.get("interaction_distance")
	var base_range = interaction_distance if interaction_distance != null else 5.0
	var extended_range = base_range * 30.0  # Extended range for VR
	npc_in_range = distance < extended_range

func set_vr_active(active: bool):
	is_vr_active = active
	
	# Enable/disable XR origin
	if xr_origin:
		xr_origin.visible = active
		xr_origin.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	
	# Emit signal for other systems
	vr_mode_changed.emit(active)
	
	print("VR movement " + ("enabled" if active else "disabled"))

func is_movement_active() -> bool:
	return movement_direction.length() > 0.1 and is_vr_active

# VR Controller input handlers
func _on_left_hand_input_vector_2_changed(name: String, value: Vector2) -> void:
	if name == "primary":
		# Left joystick: Full 2D movement (strafe + forward/backward)
		movement_input = value

func _on_right_hand_input_vector_2_changed(name: String, value: Vector2) -> void:
	if name == "primary":
		# Right joystick X-axis: Camera rotation ONLY
		rotation_input = value.x
		# Right joystick Y-axis is ignored - no movement from right stick

func _on_left_hand_button_pressed(name: String) -> void:
	# Auto-connect on first button press
	_handle_first_button_press()
	
	if name == "grip_click":
		left_hand_grip_pressed = true
	elif name == "ax_button":
		# A button on left controller - Debug planetary status
		if character.has_method("debug_planetary_status"):
			character.debug_planetary_status()
	elif name == "by_button":
		# B button on left controller - Reserved for future use
		pass
	elif name == "trigger_click":
		_handle_npc_interaction_start()

func _on_left_hand_button_released(name: String) -> void:
	if name == "grip_click":
		left_hand_grip_pressed = false
	elif name == "trigger_click":
		_handle_npc_interaction_stop()

func _on_right_hand_button_pressed(name: String) -> void:
	# Auto-connect on first button press
	_handle_first_button_press()
	
	if name == "grip_click":
		right_hand_grip_pressed = true
	elif name == "ax_button":
		# A button on right controller - JUMP
		jump_just_pressed = true
	elif name == "by_button":
		# B button on right controller - Force perfect planet alignment
		if character.has_method("force_perfect_planet_alignment"):
			character.force_perfect_planet_alignment()
	elif name == "trigger_click":
		_handle_npc_audio_playback()

func _on_right_hand_button_released(name: String) -> void:
	if name == "grip_click":
		right_hand_grip_pressed = false

func _handle_npc_interaction_start():
	if not npc_in_range or not current_npc:
		return
	
	print("VR: Starting NPC interaction")
	if current_npc.has_method("vr_start_recording"):
		var is_speaking = current_npc.get("is_speaking")
		var is_recording = current_npc.get("is_recording")
		if not (is_speaking if is_speaking != null else false) and not (is_recording if is_recording != null else false):
			current_npc.vr_start_recording()

func _handle_npc_interaction_stop():
	if not npc_in_range or not current_npc:
		return
	
	print("VR: Stopping NPC interaction")
	if current_npc.has_method("vr_stop_recording"):
		var is_recording = current_npc.get("is_recording")
		if is_recording if is_recording != null else false:
			current_npc.vr_stop_recording()

func _handle_npc_audio_playback():
	if not npc_in_range or not current_npc:
		return
	
	print("VR: Playing last NPC response")
	if current_npc.has_method("play_last_audio"):
		current_npc.play_last_audio()

func cleanup() -> void:
	# Reset VR state
	movement_input = Vector2.ZERO
	rotation_input = 0.0
	is_jumping = false
	left_hand_grip_pressed = false
	right_hand_grip_pressed = false 
