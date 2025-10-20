extends AnimationBase
class_name CountryballAnimation

# Countryball-specific animation implementation

# Countryball specific parameters
var bounce_amount := 0.3  # How much the ball bounces up and down
var bounce_speed := 8.0   # How fast the bouncing animation
var squash_amount := 0.2  # How much the ball squashes when moving

# Node references
var base_mesh: MeshInstance3D
var emotions_mesh: MeshInstance3D

# Animation state
var bounce_timer := 0.0
var original_scale: Vector3

func setup(char: CharacterBody3D, model: Node3D, audio_player: AudioStreamPlayer3D) -> void:
	super.setup(char, model, audio_player)
	
	# Get references to countryball-specific nodes
	base_mesh = character_model.find_child("Base")
	emotions_mesh = character_model.find_child("Emotions")
	
	# Store original scale for squashing
	original_scale = character_model.scale
	
	# Copy parameters from character if they exist
	if character.get("bounce_amount") != null:
		bounce_amount = character.bounce_amount
	if character.get("bounce_speed") != null:
		bounce_speed = character.bounce_speed
	if character.get("squash_amount") != null:
		squash_amount = character.squash_amount
	if character.get("footstep_rate") != null:
		footstep_rate = character.footstep_rate

func animate(delta: float, speed: float, movement_dir: Vector3, is_running: bool, is_on_floor: bool) -> void:
	var is_moving = speed > 0.1
	
	if is_moving and is_on_floor:
		# Blob-like bouncing animation
		bounce_timer += delta * bounce_speed * (2.0 if is_running else 1.0)
		
		# Create bouncing effect with sine wave
		var bounce_offset = sin(bounce_timer) * bounce_amount
		
		# Squash the ball slightly when moving (make it wider and shorter)
		var squash_factor = 1.0 - (speed / character.run_speed) * squash_amount
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
			play_footstep_sound(speed / character.walk_speed)
			footstep_timer = footstep_rate / (2.0 if is_running else 1.0)
	else:
		# Return to normal shape when not moving
		character_model.scale = character_model.scale.lerp(original_scale, delta * 5.0)
		character_model.position.y = lerp(character_model.position.y, 0.0, delta * 5.0)
		bounce_timer = 0.0
	
	# Special animation when in air (squash vertically like falling)
	if not is_on_floor:
		var fall_squash = 1.0 + abs(character.velocity.y) * 0.05  # More squash when falling faster
		character_model.scale = Vector3(
			original_scale.x * fall_squash,
			original_scale.y / fall_squash,
			original_scale.z * fall_squash
		)

func animate_remote(speed: float, direction: Vector3, is_on_floor: bool = true) -> void:
	var is_moving = speed > 0.1
	var is_running = speed > character.walk_speed * 0.8
	
	if is_moving and is_on_floor:
		# Blob-like bouncing animation for remote players
		bounce_timer += 0.05 * bounce_speed * (2.0 if is_running else 1.0)  # 0.05 is network update interval
		
		# Create bouncing effect
		var bounce_offset = sin(bounce_timer) * bounce_amount
		
		# Squash the ball slightly when moving
		var squash_factor = 1.0 - (speed / character.run_speed) * squash_amount
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
	
	# Special animation when in air for remote players
	if not is_on_floor:
		var fall_squash = 1.0 + abs(character.velocity.y) * 0.05 if character else 1.2
		character_model.scale = Vector3(
			original_scale.x * fall_squash,
			original_scale.y / fall_squash,
			original_scale.z * fall_squash
		)

# Get the base mesh for texture application (countryball-specific)
func get_base_mesh() -> MeshInstance3D:
	return base_mesh 