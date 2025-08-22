extends CharacterBody3D

# Movement parameters
@export var walk_speed := 4
@export var run_speed := 8.0
@export var jump_velocity := 8  # Increased from 4.5 for higher jumps
@export var acceleration := 10.0
@export var air_control := 0.3
@export var gravity_multiplier := 2.5  # Increased from 1.0 for faster falling

# Animation parameters
@export var arm_swing_amount := 1.2  # How far arms swing (in radians)
@export var leg_swing_amount := 0.8  # How far legs swing (in radians)
@export var animation_speed := 10.0  # Speed of limb rotation

# Nodes
var character_model: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var head: MeshInstance3D

# Animation state
var walk_cycle := 0.0
var is_running := false
var movement_dir := Vector3.ZERO
var last_y_velocity := 0.0
var was_on_floor := false
var target_rotation := 0.0
var rotation_speed := 10.0  # Speed of character rotation
var _input_enabled := true  # New variable to control input processing

# Get the gravity from the project settings
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_multiplier

# Add these variables near the top of your script
var sound_player: AudioStreamPlayer3D
var footstep_sound: AudioStream
var jump_sound: AudioStream
var victory_sound: AudioStream
var footstep_timer := 0.0
var footstep_rate := 0.3  # Time between footstep sounds in seconds

func _ready():
	# Get references to all limbs and model
	character_model = $CharacterModel
	left_arm = $CharacterModel/LeftArm
	right_arm = $CharacterModel/RightArm
	left_leg = $CharacterModel/LeftLeg
	right_leg = $CharacterModel/RightLeg2
	head = $CharacterModel/head

	# Make chat bubble invisible initially
	$CharacterModel/ChatBubble/Sprite3D.visible = false
	
	# Setup sounds
	sound_player = $SoundPlayer
	footstep_sound = preload("res://src/sound/bfsl-minifigfoots1.mp3")
	jump_sound = preload("res://src/sound/swoosh.wav")
	victory_sound = preload("res://src/sound/victory.wav")
	
	# Play victory sound on initialization
	if sound_player and victory_sound:
		sound_player.stream = victory_sound
		sound_player.play()

func _physics_process(delta):
	# Add gravity
	if not is_on_floor():
		# Apply stronger gravity when falling (after reaching peak of jump)
		var gravity_strength = gravity
		if velocity.y < 0:
			gravity_strength = gravity * 1.5  # Even stronger gravity when falling
		velocity.y -= gravity_strength * delta
	
	# Handle jump
	if _input_enabled and Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		play_jump_sound()
	
	# Get input direction (only if input is enabled)
	var input_dir = Vector2.ZERO
	if _input_enabled:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Get camera-based movement direction
	var direction = Vector3.ZERO
	if input_dir != Vector2.ZERO:
		# Get the camera's global transform - Add safety check
		var camera = get_viewport().get_camera_3d()
		if camera == null:
			print("Warning: No camera found!")
			return
			
		var camera_transform = camera.get_global_transform()
		
		# Get forward and right vectors from the camera, but ignore Y component
		var forward = -camera_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		
		var right = camera_transform.basis.x
		right.y = 0
		right = right.normalized()
		
		# Combine input with camera direction - FIXED: Inverted the y input to correct forward/backward
		direction = (forward * -input_dir.y + right * input_dir.x).normalized()
		
		# Set target rotation for the character model to face movement direction
		if direction.length() > 0.1:
			# Add PI to make the model face forward instead of backward
			target_rotation = atan2(direction.x, direction.z) + PI
	
	# Running toggled with shift (only if input is enabled)
	is_running = _input_enabled and Input.is_action_pressed("ui_sprint") 
	
	# Target speed depends on whether we're running
	var target_speed = run_speed if is_running else walk_speed
	
	# Set horizontal velocity based on input
	if direction:
		# Store normalized direction for animations
		movement_dir = direction
		
		# Apply acceleration when on floor, reduced control when in air
		var current_acceleration = acceleration
		if not is_on_floor():
			current_acceleration *= air_control
		
		# Apply acceleration
		var target_velocity = direction * target_speed
		velocity.x = lerp(velocity.x, target_velocity.x, delta * current_acceleration)
		velocity.z = lerp(velocity.z, target_velocity.z, delta * current_acceleration)
	else:
		# Decelerate when no input
		var friction = acceleration * (0.5 if not is_on_floor() else 1.0)
		velocity.x = lerp(velocity.x, 0.0, delta * friction)
		velocity.z = lerp(velocity.z, 0.0, delta * friction)
	
	# Smoothly rotate the character model to face movement direction
	if abs(velocity.x) > 0.1 or abs(velocity.z) > 0.1:
		var current_rotation = character_model.rotation.y
		var rotation_diff = wrapf(target_rotation - current_rotation, -PI, PI)
		character_model.rotation.y = lerp_angle(current_rotation, current_rotation + rotation_diff, delta * rotation_speed)
	
	# Move the character
	move_and_slide()
	
	# Animate the character
	animate_character(delta)
	
	# Check for jumping (was on floor but now isn't)
	if was_on_floor and not is_on_floor() and velocity.y > 0:
		play_jump_sound()
	
	# Save previous state
	last_y_velocity = velocity.y
	was_on_floor = is_on_floor()

func animate_character(delta):
	# Calculate movement intensity (0 when standing still, 1 when at full speed)
	var speed = Vector2(velocity.x, velocity.z).length()
	var max_speed = run_speed if is_running else walk_speed
	var movement_intensity = clamp(speed / max_speed, 0.0, 1.0)
	
	# Only animate when moving and on the ground
	if movement_intensity > 0.01 and is_on_floor():
		# Progress the walk cycle based on speed
		var cycle_speed = animation_speed * movement_intensity * delta
		if is_running:
			cycle_speed *= 1.5
		
		walk_cycle += cycle_speed
		
		# Update footstep timer and play sound if needed
		footstep_timer -= delta
		if footstep_timer <= 0 and movement_intensity > 0.1:
			play_footstep_sound(movement_intensity)
			footstep_timer = footstep_rate / movement_intensity  # Faster steps when running
		
		# Keep walk_cycle between 0 and 2*PI
		walk_cycle = fmod(walk_cycle, 2.0 * PI)
		
		# Calculate limb rotations using sine waves offset by half a cycle
		var arm_swing = sin(walk_cycle) * arm_swing_amount * movement_intensity
		var leg_swing = sin(walk_cycle) * leg_swing_amount * movement_intensity
		var opposite_swing = sin(walk_cycle + PI) * leg_swing_amount * movement_intensity
		
		# Apply rotations to limbs - note we're rotating the parent Node3D as requested
		# Arms swing opposite to legs
		left_arm.rotation.x = opposite_swing
		right_arm.rotation.x = arm_swing
		
		# Legs swing in walking motion
		left_leg.rotation.x = leg_swing 
		right_leg.rotation.x = opposite_swing
	else:
		# Reset limbs to default pose when not moving
		if is_on_floor():
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
			right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
			
			# Reset footstep timer when not moving
			footstep_timer = 0.0
	
	# Animate jumping/falling - Roblox style
	if not is_on_floor():
		# Roblox-style: Arms forward and up (180 degrees rotation)
		# Using positive values for forward rotation (PI/2 is 90 degrees forward)
		left_arm.rotation.x = lerp(left_arm.rotation.x, PI, delta * 5.0)  # 180 degrees forward
		right_arm.rotation.x = lerp(right_arm.rotation.x, PI, delta * 5.0)  # 180 degrees forward
		
		# Keep legs straight in air (Roblox style)
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)

	# Head slightly looks in movement direction
	if movement_intensity > 0.05:
		head.rotation.y = lerp(head.rotation.y, -movement_dir.x * 0.2, delta * 2.0)
	else:
		head.rotation.y = lerp(head.rotation.y, 0.0, delta * 2.0)

# New method to enable/disable input processing
func set_input_enabled(enabled: bool):
	_input_enabled = enabled
	
	# If disabling input, also stop movement
	if not enabled:
		# Gradually slow down instead of immediate stop
		velocity.x = lerp(velocity.x, 0.0, 0.3)
		velocity.z = lerp(velocity.z, 0.0, 0.3)

# Add this method to the humanoid.gd script
func set_as_remote_player():
	# Disable input processing
	set_input_enabled(false)

# Add this method to animate remote players based on their movement
func animate_remote_movement(speed, direction):
	# Calculate movement intensity (0 when standing still, 1 when at full speed)
	var max_speed = run_speed  # Assume running if moving fast
	if speed < walk_speed:
		max_speed = walk_speed
	
	var movement_intensity = clamp(speed / max_speed, 0.0, 1.0)
	var is_moving = movement_intensity > 0.01
	
	# Store direction for head animation
	if is_moving:
		movement_dir = direction
	
	# Check if player is in the air (based on y position changing)
	var is_in_air = not is_on_floor()
	var was_in_air = last_y_velocity != 0
	
	# Handle jump sound for remote players
	if not is_in_air and was_in_air:
		play_jump_sound()
	
	# Handle jumping/falling animation
	if is_in_air:
		# Roblox-style: Arms forward and up (180 degrees rotation)
		left_arm.rotation.x = lerp(left_arm.rotation.x, PI, 0.1)  # 180 degrees forward
		right_arm.rotation.x = lerp(right_arm.rotation.x, PI, 0.1)  # 180 degrees forward
		
		# Keep legs straight in air (Roblox style)
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, 0.1)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 0.1)
		
		# Head slightly looks in movement direction
		head.rotation.y = lerp(head.rotation.y, -movement_dir.x * 0.2, 0.1)
		
		# Reset footstep timer when in air
		footstep_timer = 0.0
		return
	
	# Only animate when moving and on the ground
	if is_moving:
		# Progress the walk cycle based on speed
		var cycle_speed = animation_speed * movement_intensity * 0.05  # 0.05 is the network update interval
		if speed > walk_speed:  # Running
			cycle_speed *= 1.5
		
		walk_cycle += cycle_speed
		
		# Update footstep timer and play sound if needed
		footstep_timer -= 0.05  # Use network update interval
		if footstep_timer <= 0 and movement_intensity > 0.1:
			play_footstep_sound(movement_intensity)
			footstep_timer = footstep_rate / movement_intensity
		
		# Keep walk_cycle between 0 and 2*PI
		walk_cycle = fmod(walk_cycle, 2.0 * PI)
		
		# Calculate limb rotations using sine waves offset by half a cycle
		var arm_swing = sin(walk_cycle) * arm_swing_amount * movement_intensity
		var leg_swing = sin(walk_cycle) * leg_swing_amount * movement_intensity
		var opposite_swing = sin(walk_cycle + PI) * leg_swing_amount * movement_intensity
		
		# Apply rotations to limbs
		# Arms swing opposite to legs
		left_arm.rotation.x = opposite_swing
		right_arm.rotation.x = arm_swing
		
		# Legs swing in walking motion
		left_leg.rotation.x = leg_swing 
		right_leg.rotation.x = opposite_swing
		
		# Head slightly looks in movement direction
		head.rotation.y = -movement_dir.x * 0.2
	else:
		# Reset limbs to default pose when not moving
		left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, 0.1)
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, 0.1)
		left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, 0.1)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 0.1)
		head.rotation.y = lerp(head.rotation.y, 0.0, 0.1)

# Add accessories to the character model
func add_accessory(accessory_name):
	if not has_node("CharacterModel/Accessories"):
		print("Accessories node not found on character model")
		return false
	
	var accessories_node = get_node("CharacterModel/Accessories")
	
	# Check if accessory is already added
	if accessories_node.has_node(accessory_name):
		print("Accessory already exists: ", accessory_name)
		return false
	
	# Load the accessory scene
	var accessory_path = "res://src/accessories/" + accessory_name + "/" + accessory_name + ".tscn"
	if ResourceLoader.exists(accessory_path):
		var accessory_scene = load(accessory_path)
		var accessory_instance = accessory_scene.instantiate()
		accessory_instance.name = accessory_name
		accessories_node.add_child(accessory_instance)
		print("Added accessory: ", accessory_name)
		return true
	else:
		print("Failed to load accessory: ", accessory_path)
		return false

# Show chat bubble with message
func show_chat_bubble(message: String):
	# Get the chat bubble viewport components
	var chat_viewport = $ChatBubbleViewport
	var rich_text = $ChatBubbleViewport/Control/TextureRect/RichTextLabel
	
	# Update the text
	rich_text.text = message
	
	# Make the bubble visible (in case it was hidden)
	$CharacterModel/ChatBubble/Sprite3D.visible = true
	
	# Create a timer to hide the bubble after a few seconds
	var timer = get_tree().create_timer(5.0)  # 5 seconds display time
	timer.timeout.connect(func(): $CharacterModel/ChatBubble/Sprite3D.visible = false)

# Remove an accessory from the character model
func remove_accessory(accessory_name):
	if not has_node("CharacterModel/Accessories"):
		return false
	
	var accessories_node = get_node("CharacterModel/Accessories")
	if accessories_node.has_node(accessory_name):
		accessories_node.get_node(accessory_name).queue_free()
		print("Removed accessory: ", accessory_name)
		return true
	return false

# Clear all accessories
func clear_accessories():
	if not has_node("CharacterModel/Accessories"):
		return
	
	var accessories_node = get_node("CharacterModel/Accessories")
	for child in accessories_node.get_children():
		child.queue_free()
	
	print("Cleared all accessories")

# Add these new methods for sound handling
func play_footstep_sound(intensity: float):
	if sound_player and footstep_sound:
		sound_player.stream = footstep_sound
		# Adjust volume based on movement intensity
		sound_player.volume_db = linear_to_db(clamp(intensity, 0.3, 1.0))
		sound_player.play()

func play_jump_sound():
	if sound_player and jump_sound:
		sound_player.stream = jump_sound
		sound_player.volume_db = 0.0  # Full volume for jumps
		sound_player.play()
