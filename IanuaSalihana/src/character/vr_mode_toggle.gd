extends Node

# References to nodes
var character: CharacterBody3D
var xr_origin: XROrigin3D
var camera_controller: Node3D
var xr_camera: XRCamera3D
var character_model: Node3D
var head: MeshInstance3D

# Movement parameters
@export var vr_movement_speed := 2
@export var vr_rotation_speed := 2.0
@export var vr_jump_velocity := 8

# VR state tracking
var is_vr_active := false
var movement_direction := Vector2.ZERO
var is_jumping := false
var left_hand_grip_pressed := false
var right_hand_grip_pressed := false
var movement_dir := Vector3.ZERO
var target_rotation := 0.0

# Signal for VR mode change
signal vr_mode_changed(is_active: bool)

# NPC interaction
var current_npc: Node = null
var npc_in_range = false

func _ready():
	# Get references to required nodes
	character = get_parent() as CharacterBody3D
	xr_origin = character.find_child("XROrigin3D")
	camera_controller = character.find_child("CamOrigin")
	xr_camera = xr_origin.find_child("XRCamera3D")
	character_model = character.find_child("CharacterModel")
	#head = character_model.find_child("head")
	head = character_model
	
	# Try to initialize VR directly
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		# Initialize XR
		if xr_interface.initialize():
			print("XR Interface initialized successfully")
			
			# Connect to VR controllers
			var left_hand = xr_origin.find_child("LeftHand")
			var right_hand = xr_origin.find_child("RightHand")
			
			if left_hand:
				left_hand.button_pressed.connect(_on_left_hand_button_pressed)
				left_hand.button_released.connect(_on_left_hand_button_released)
				left_hand.input_vector2_changed.connect(_on_left_hand_input_vector_2_changed)
			
			if right_hand:
				right_hand.button_pressed.connect(_on_right_hand_button_pressed)
				right_hand.button_released.connect(_on_right_hand_button_released)
				right_hand.input_vector2_changed.connect(_on_right_hand_input_vector_2_changed)
			
			# Start VR session
			get_viewport().use_xr = true
			set_vr_mode(true)
		else:
			print("XR Interface failed to initialize - falling back to non-VR mode")
			set_vr_mode(false)
	else:
		print("No XR Interface found - falling back to non-VR mode")
		set_vr_mode(false)

func toggle_vr_mode() -> void:
	set_vr_mode(!is_vr_active)

func set_vr_mode(active: bool) -> void:
	is_vr_active = active
	
	# Enable/disable relevant nodes
	if xr_origin:
		xr_origin.visible = active
		xr_origin.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	
	if camera_controller:
		camera_controller.visible = !active
		camera_controller.process_mode = Node.PROCESS_MODE_INHERIT if !active else Node.PROCESS_MODE_DISABLED
	
	# Hide ONLY the head mesh in VR mode (to prevent seeing inside the head)
	# This should only affect the LOCAL player's head, not remote players
	if head and character:
		# Only hide the head if this is the local player (has LocalPlayer node)
		var local_player_node = character.get_node_or_null("LocalPlayer")
		if local_player_node:
			head.visible = !active
	
	# Handle XR session
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		get_viewport().use_xr = active
	
	# Configure audio for VR mode - use non-spatial audio in VR
	if active:
		# First get references to both audio players
		var npc_spatial_audio = get_node_or_null("/root/workspace/NPC2/Skeleton3D/AudioStreamPlayer3D")
		var global_audio = get_node_or_null("/root/workspace/AudioStreamPlayer")
		
		if npc_spatial_audio and global_audio:
			# In VR mode, disable spatial audio and use the global audio player
			npc_spatial_audio.volume_db = -80.0  # Essentially mute the spatial audio
			
			# Tell the NPC to use non-spatial audio in VR mode
			var npc = get_node_or_null("/root/workspace/NPC2/Skeleton3D")
			if npc and npc.has_method("set_vr_audio_mode"):
				npc.set_vr_audio_mode(true)
			else:
				# Apply a patch directly to the NPC script if no method exists
				if npc and "use_vr_audio" in npc:
					npc.use_vr_audio = true
					print("Patched NPC to use VR audio mode")
					
					# If we need to directly patch the global audio reference
					if "vr_audio_player" in npc:
						npc.vr_audio_player = global_audio
						print("Assigned global audio player for VR mode")
			
			print("Switched to non-spatial audio for VR mode")
	else:
		# Restore spatial audio settings for non-VR mode
		var npc_spatial_audio = get_node_or_null("/root/workspace/NPC2/Skeleton3D/AudioStreamPlayer3D")
		if npc_spatial_audio:
			npc_spatial_audio.volume_db = 0.0  # Default volume
			
		# Tell the NPC to use spatial audio in non-VR mode
		var npc = get_node_or_null("/root/workspace/NPC2/Skeleton3D")
		if npc and npc.has_method("set_vr_audio_mode"):
			npc.set_vr_audio_mode(false)
		else:
			# Apply a patch directly to the NPC script if no method exists
			if npc and "use_vr_audio" in npc:
				npc.use_vr_audio = false
				print("Patched NPC to use normal audio mode")
	
	# Emit signal for other systems to respond
	vr_mode_changed.emit(active)
	
	print("VR mode " + ("enabled" if active else "disabled"))

func _physics_process(delta: float) -> void:
	if is_vr_active and character:
		# Check for NPCs in range
		find_nearest_npc()
		
		# VR Movement logic
		# Calculate movement direction based on controller input
		var direction = Vector3.ZERO
		if movement_direction != Vector2.ZERO:
			# Get the XR camera's forward direction (ignoring Y component)
			var camera_transform = xr_camera.get_global_transform()
			var forward = -camera_transform.basis.z
			forward.y = 0
			forward = forward.normalized()
			
			var right = camera_transform.basis.x
			right.y = 0
			right = right.normalized()
			
			# Combine input with camera direction
			direction = (forward * movement_direction.y + right * movement_direction.x).normalized()
		
		# Apply gravity
		if not character.is_on_floor():
			var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * 2.5  # Same gravity multiplier as humanoid
			
			# Apply stronger gravity when falling
			if character.velocity.y < 0:
				gravity *= 1.5
				
			character.velocity.y -= gravity * delta
		
		# Handle jump
		if is_jumping and character.is_on_floor():
			character.velocity.y = vr_jump_velocity
			is_jumping = false
		
		# Apply movement
		if direction:
			# Store normalized direction for animations
			movement_dir = direction
			
			# Apply acceleration
			var current_acceleration = 10.0  # Same as humanoid
			if not character.is_on_floor():
				current_acceleration *= 0.3  # Same air control as humanoid
			
			# Apply acceleration
			var target_velocity = direction * vr_movement_speed
			character.velocity.x = lerp(character.velocity.x, target_velocity.x, delta * current_acceleration)
			character.velocity.z = lerp(character.velocity.z, target_velocity.z, delta * current_acceleration)
		else:
			# Decelerate when no input
			var friction = 10.0 * (0.5 if not character.is_on_floor() else 1.0)
			character.velocity.x = lerp(character.velocity.x, 0.0, delta * friction)
			character.velocity.z = lerp(character.velocity.z, 0.0, delta * friction)
		
		# Always update character model rotation to match camera direction
		# This makes the character face the same direction as the VR headset
		var camera_basis = xr_camera.get_global_transform().basis
		var camera_forward = -camera_basis.z
		camera_forward.y = 0
		if camera_forward.length() > 0.1:
			var camera_rotation = atan2(camera_forward.x, camera_forward.z) + PI
			character_model.rotation.y = camera_rotation
		
		# Let the character controller handle the actual movement
		character.move_and_slide()

# No searching - just use a fixed NPC reference with increased range
func find_nearest_npc():
	# Only set the NPC once
	if current_npc == null:
		# Hard-coded path to the NPC
		current_npc = get_node_or_null("/root/workspace/NPC2/Skeleton3D")
		
		if current_npc != null:
			print("Using hard-coded NPC: " + current_npc.name)
			npc_in_range = true
		else:
			print("ERROR: Hard-coded NPC path not found")
			npc_in_range = false
	
	# Simple distance check with increased range (3x the original distance)
	if current_npc != null and current_npc.get_parent():
		var distance = current_npc.get_parent().global_position.distance_to(character.global_position)
		var extended_range = current_npc.interaction_distance * 30.0  # Triple the interaction range
		npc_in_range = distance < extended_range

# VR Controller input handlers
func _on_left_hand_input_vector_2_changed(name: String, value: Vector2) -> void:
	# Use primary joystick/thumbstick for movement
	if name == "primary":
		movement_direction = value

# VR Controller input handlers
func _on_right_hand_input_vector_2_changed(name: String, value: Vector2) -> void:
	# Use primary joystick/thumbstick for movement
	if name == "primary":
		movement_direction = value

func _on_left_hand_button_pressed(name: String) -> void:
	# Track grip state for interaction system
	if name == "grip_click":
		left_hand_grip_pressed = true
	# Jump with A/X button
	elif name == "ax_button":
		is_jumping = true
	# Debug ALL trigger presses regardless of NPC state
	elif name == "trigger_click":
		print("LEFT TRIGGER PRESSED - Debugging info:")
		print("  NPC in range: " + str(npc_in_range))
		print("  Current NPC: " + str(current_npc))
		
		# Only try to record if we have an NPC in range
		if npc_in_range and current_npc:
			print("  Attempting to record with NPC: " + current_npc.name)
			
			# Check if we can directly call methods on the NPC
			if current_npc.has_method("vr_start_recording"):
				print("  NPC has vr_start_recording method")
				if !current_npc.is_speaking and !current_npc.is_recording:
					print("  Starting recording - NPC is not speaking or recording")
					current_npc.vr_start_recording()
				else:
					print("  Cannot start recording - NPC is speaking: " + str(current_npc.is_speaking) + " or recording: " + str(current_npc.is_recording))
			else:
				print("  ERROR: NPC doesn't have vr_start_recording method")
				print("  Available methods:")
				for method in current_npc.get_method_list():
					print("    - " + method.name)

func _on_left_hand_button_released(name: String) -> void:
	# Track grip state for interaction system
	if name == "grip_click":
		left_hand_grip_pressed = false
	# Voice chat with NPC using the trigger
	elif name == "trigger_click" and npc_in_range and current_npc:
		print("LEFT TRIGGER RELEASED - trying to stop recording with NPC: " + current_npc.name)
		
		# Check if we can directly call methods on the NPC
		if current_npc.has_method("vr_stop_recording"):
			if current_npc.is_recording:
				print("VR: Stopped voice recording for NPC interaction")
				current_npc.vr_stop_recording()
		# Otherwise try to find the npc_voice_chat node
		else:
			var voice_chat = current_npc.get_node_or_null("NPCInteraction")
			if voice_chat and voice_chat.has_method("stop_recording"):
				print("Using NPCInteraction voice chat")
				voice_chat.stop_recording()
			else:
				print("ERROR: Can't find voice recording method on NPC")

func _on_right_hand_button_pressed(name: String) -> void:
	# Track grip state for interaction system
	if name == "grip_click":
		right_hand_grip_pressed = true
	# Menu button for important functions
	elif name == "menu_button":
		print("Right menu button pressed - toggle VR mode")
		toggle_vr_mode()
	# Right trigger now plays the last audio file (like T key)
	elif name == "trigger_click" and npc_in_range and current_npc:
		print("RIGHT TRIGGER: Playing last NPC response")
		
		# Check if NPC has the debug audio playback method
		if current_npc.has_method("play_last_audio"):
			current_npc.play_last_audio()
		# Or if NPC has the FileAccess.file_exists method and the path to the last audio file
		elif FileAccess.file_exists(current_npc.last_audio_file) and not current_npc.is_speaking:
			print("Playing last audio file: " + current_npc.last_audio_file)
			current_npc.play_audio_file(current_npc.last_audio_file)
		else:
			print("No last audio file available to play")

func _on_right_hand_button_released(name: String) -> void:
	# Track grip state for interaction system
	if name == "grip_click":
		right_hand_grip_pressed = false
