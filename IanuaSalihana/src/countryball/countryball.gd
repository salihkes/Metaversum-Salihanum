extends CharacterBody3D

# This script makes the countryball compatible with the humanoid system
# It inherits most functionality but with blob-like animations

# Movement parameters (same as humanoid)
@export var walk_speed := 4
@export var run_speed := 8.0
@export var jump_velocity := 8
@export var acceleration := 10.0
@export var air_control := 0.3
@export var gravity_multiplier := 2.5

# Countryball specific parameters
@export var bounce_amount := 0.3  # How much the ball bounces up and down
@export var bounce_speed := 8.0   # How fast the bouncing animation
@export var squash_amount := 0.2  # How much the ball squashes when moving

# Nodes
var character_model: Node3D
var base_mesh: MeshInstance3D
var emotions_mesh: MeshInstance3D

# Animation state
var movement_dir := Vector3.ZERO
var target_rotation := 0.0
var rotation_speed := 10.0
var _input_enabled := true
var bounce_timer := 0.0
var original_scale: Vector3

# Get the gravity from the project settings
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_multiplier

# Sound system
var sound_player: AudioStreamPlayer3D
var footstep_sound: AudioStream
var jump_sound: AudioStream
var footstep_timer := 0.0
var footstep_rate := 0.4

func _ready():
	# Get references to nodes
	character_model = $CharacterModel
	base_mesh = $CharacterModel/Base
	emotions_mesh = $CharacterModel/Emotions
	
	# Store original scale for squashing
	original_scale = character_model.scale
	
	# Make chat bubble invisible initially
	$CharacterModel/ChatBubble/Sprite3D.visible = false
	
	# Setup sounds
	sound_player = $SoundPlayer
	footstep_sound = preload("res://src/sound/bfsl-minifigfoots1.mp3")
	jump_sound = preload("res://src/sound/swoosh.wav")
	
	# Mark this as the local player if it has the LocalPlayer node
	if has_node("LocalPlayer"):
		add_to_group("local_player")
		set_meta("is_local_player", true)

func _physics_process(delta):
	# Handle input only if enabled
	if not _input_enabled:
		return
	
	# Add gravity
	if not is_on_floor():
		velocity.y -= gravity * delta
	
	# Handle jump
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity
		play_jump_sound()
	
	# Get input direction (only if input is enabled)
	var input_dir = Vector2.ZERO
	if _input_enabled:
		input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Get camera-based movement direction (same as humanoid)
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
		
		# Combine input with camera direction
		direction = (forward * -input_dir.y + right * input_dir.x).normalized()
		
		# Set target rotation for the character model to face movement direction
		if direction.length() > 0.1:
			target_rotation = atan2(direction.x, direction.z) + PI
	
	# Determine if running
	var is_running = _input_enabled and Input.is_action_pressed("ui_sprint")
	var current_speed = run_speed if is_running else walk_speed
	
	if direction:
		# Store normalized direction for animations
		movement_dir = direction
		
		# Apply acceleration
		var current_acceleration = acceleration
		if not is_on_floor():
			current_acceleration *= air_control
		
		var target_velocity = direction * current_speed
		velocity.x = lerp(velocity.x, target_velocity.x, delta * current_acceleration)
		velocity.z = lerp(velocity.z, target_velocity.z, delta * current_acceleration)
	else:
		# Decelerate when no input
		var friction = acceleration * (0.5 if not is_on_floor() else 1.0)
		velocity.x = lerp(velocity.x, 0.0, delta * friction)
		velocity.z = lerp(velocity.z, 0.0, delta * friction)
		movement_dir = Vector3.ZERO
	
	# Smoothly rotate the character model to face movement direction
	if abs(velocity.x) > 0.1 or abs(velocity.z) > 0.1:
		var current_rotation = character_model.rotation.y
		var rotation_diff = wrapf(target_rotation - current_rotation, -PI, PI)
		character_model.rotation.y = lerp_angle(current_rotation, current_rotation + rotation_diff, delta * rotation_speed)
	
	move_and_slide()
	
	# Handle countryball-specific animations
	_animate_countryball(delta)

func _animate_countryball(delta):
	var speed = Vector2(velocity.x, velocity.z).length()
	var is_moving = speed > 0.1
	var is_running = speed > walk_speed * 0.8
	
	if is_moving and is_on_floor():
		# Blob-like bouncing animation
		bounce_timer += delta * bounce_speed * (2.0 if is_running else 1.0)
		
		# Create bouncing effect with sine wave
		var bounce_offset = sin(bounce_timer) * bounce_amount
		
		# Squash the ball slightly when moving (make it wider and shorter)
		var squash_factor = 1.0 - (speed / run_speed) * squash_amount
		character_model.scale = Vector3(
			original_scale.x * (1.0 + squash_amount * 0.5),  # Wider
			original_scale.y * squash_factor,                 # Shorter
			original_scale.z * (1.0 + squash_amount * 0.5)   # Wider
		)
		
		# Apply bounce to position
		character_model.position.y = bounce_offset
		
		# Play bouncing sound
		footstep_timer -= delta
		if footstep_timer <= 0:
			play_footstep_sound(speed / walk_speed)
			footstep_timer = footstep_rate / (2.0 if is_running else 1.0)
	else:
		# Return to normal shape when not moving
		character_model.scale = character_model.scale.lerp(original_scale, delta * 5.0)
		character_model.position.y = lerp(character_model.position.y, 0.0, delta * 5.0)
		bounce_timer = 0.0
	
	# Special animation when in air (squash vertically like falling)
	if not is_on_floor():
		var fall_squash = 1.0 + abs(velocity.y) * 0.05  # More squash when falling faster
		character_model.scale = Vector3(
			original_scale.x * fall_squash,
			original_scale.y / fall_squash,
			original_scale.z * fall_squash
		)

# Remote player animation (called by network controller)
func animate_remote_movement(speed: float, direction: Vector3):
	var is_moving = speed > 0.1
	var is_running = speed > walk_speed * 0.8
	
	if is_moving:
		# Blob-like bouncing animation for remote players
		bounce_timer += 0.05 * bounce_speed * (2.0 if is_running else 1.0)  # 0.05 is network update interval
		
		# Create bouncing effect
		var bounce_offset = sin(bounce_timer) * bounce_amount
		
		# Squash the ball slightly when moving
		var squash_factor = 1.0 - (speed / run_speed) * squash_amount
		character_model.scale = Vector3(
			original_scale.x * (1.0 + squash_amount * 0.5),
			original_scale.y * squash_factor,
			original_scale.z * (1.0 + squash_amount * 0.5)
		)
		
		# Apply bounce to position
		character_model.position.y = bounce_offset
	else:
		# Return to normal shape
		character_model.scale = character_model.scale.lerp(original_scale, 0.1)
		character_model.position.y = lerp(character_model.position.y, 0.0, 0.1)

func set_as_remote_player():
	_input_enabled = false
	# Disable VR components for remote players
	if has_node("XROrigin3D"):
		$XROrigin3D.visible = false
	if has_node("CamOrigin"):
		$CamOrigin.visible = false
	if has_node("VR_Mode_Toggle"):
		$VR_Mode_Toggle.queue_free()

func play_footstep_sound(intensity: float = 1.0):
	if sound_player and footstep_sound:
		sound_player.stream = footstep_sound
		sound_player.pitch_scale = randf_range(0.8, 1.2) * intensity
		sound_player.volume_db = linear_to_db(0.3 * intensity)
		sound_player.play()

func play_jump_sound():
	if sound_player and jump_sound:
		sound_player.stream = jump_sound
		sound_player.pitch_scale = randf_range(0.9, 1.1)
		sound_player.volume_db = linear_to_db(0.5)
		sound_player.play()

func show_chat_bubble(message: String):
	# Find the chat bubble
	var chat_bubble = find_child("ChatBubble", true)
	if not chat_bubble:
		return
	
	var sprite = chat_bubble.find_child("Sprite3D", true)
	var viewport = find_child("ChatBubbleViewport", true)
	
	if not sprite or not viewport:
		return
	
	# Update the text
	var rich_text_label = viewport.find_child("RichTextLabel", true)
	if rich_text_label:
		rich_text_label.text = message
	
	# Show the bubble
	sprite.visible = true
	
	# Hide after 3 seconds
	var timer = Timer.new()
	timer.wait_time = 3.0
	timer.one_shot = true
	if timer:
		timer.timeout.connect(func(): sprite.visible = false; timer.queue_free())
		get_tree().root.add_child(timer)
		timer.start()

# Function to get the base mesh for texture application
func get_base_mesh() -> MeshInstance3D:
	return base_mesh
