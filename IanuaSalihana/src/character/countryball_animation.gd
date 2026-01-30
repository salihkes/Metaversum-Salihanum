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

# Emotion and blinking system
var current_emotion := "neutral"
var emotion_materials := {}
var blink_material: Material
var is_blinking := false
var blink_timer := 0.0
var next_blink_time := 3.0  # Time until next blink (randomized)
var blink_duration := 0.15  # How long the blink lasts

func setup(char: CharacterBody3D, model: Node3D, audio_player: AudioStreamPlayer3D) -> void:
	super.setup(char, model, audio_player)
	
	# Get references to countryball-specific nodes
	base_mesh = character_model.find_child("Base")
	emotions_mesh = character_model.find_child("Emotions")
	
	# Store original scale for squashing
	original_scale = character_model.scale
	
	# Load emotion materials
	_load_emotion_materials()
	
	# Copy parameters from character if they exist
	if character.get("bounce_amount") != null:
		bounce_amount = character.bounce_amount
	if character.get("bounce_speed") != null:
		bounce_speed = character.bounce_speed
	if character.get("squash_amount") != null:
		squash_amount = character.squash_amount
	if character.get("footstep_rate") != null:
		footstep_rate = character.footstep_rate
	
	# Start blinking with random initial delay
	next_blink_time = randf_range(2.0, 5.0)

func _load_emotion_materials():
	# Load all emotion materials
	emotion_materials["neutral"] = load("res://src/countryball/Emotions/neutral.tres")
	emotion_materials["happy"] = load("res://src/countryball/Emotions/happy.tres")
	emotion_materials["sad"] = load("res://src/countryball/Emotions/sad.tres")
	emotion_materials["serious"] = load("res://src/countryball/Emotions/serious.tres")
	blink_material = load("res://src/countryball/blink.tres")

func set_emotion(emotion: String) -> bool:
	"""Set the countryball's emotion. Returns true if successful."""
	var emotion_lower = emotion.to_lower()
	if emotion_materials.has(emotion_lower):
		current_emotion = emotion_lower
		if not is_blinking and emotions_mesh:
			emotions_mesh.set_surface_override_material(0, emotion_materials[current_emotion])
		print("Countryball emotion set to: ", current_emotion)
		return true
	return false

func get_emotion() -> String:
	return current_emotion

func animate(delta: float, speed: float, movement_dir: Vector3, is_running: bool, is_on_floor: bool) -> void:
	# Handle blinking animation
	_update_blink(delta)
	
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

func _update_blink(delta: float) -> void:
	"""Handle blinking animation"""
	if not emotions_mesh or not blink_material:
		return
	
	if is_blinking:
		# Currently blinking, check if blink duration is over
		blink_timer += delta
		if blink_timer >= blink_duration:
			# End blink, restore emotion material
			is_blinking = false
			blink_timer = 0.0
			if emotion_materials.has(current_emotion):
				emotions_mesh.set_surface_override_material(0, emotion_materials[current_emotion])
			# Set next blink time (random interval)
			next_blink_time = randf_range(2.0, 6.0)
	else:
		# Not blinking, count down to next blink
		next_blink_time -= delta
		if next_blink_time <= 0:
			# Start blinking
			is_blinking = true
			blink_timer = 0.0
			emotions_mesh.set_surface_override_material(0, blink_material)

func animate_remote(speed: float, direction: Vector3, is_on_floor: bool = true) -> void:
	# Handle blinking for remote players too (using a fixed delta approximation)
	_update_blink(0.05)  # ~20 fps approximation for remote updates
	
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