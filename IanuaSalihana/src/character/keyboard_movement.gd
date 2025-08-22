extends MovementBase
class_name KeyboardMovement

# Keyboard-specific movement implementation

var _input_enabled := true
var target_rotation := 0.0
var rotation_speed := 5.0
var mesh_forward_is_backward := true

func setup(char: CharacterBody3D, model: Node3D) -> void:
	super.setup(char, model)
	
	# Copy parameters from character if they exist
	if character.get("walk_speed") != null:
		walk_speed = character.walk_speed
		run_speed = character.run_speed
		jump_velocity = character.jump_velocity
		acceleration = character.acceleration
		air_control = character.air_control
		var mesh_backward = character.get("mesh_forward_is_backward")
		mesh_forward_is_backward = mesh_backward if mesh_backward != null else true

func update_input(delta: float) -> void:
	if not _input_enabled:
		movement_direction = Vector3.ZERO
		is_running = false
		is_jumping = false
		return
	
	# Get input direction
	var input_dir = Input.get_vector("ui_left", "ui_right", "ui_up", "ui_down")
	
	# Get movement direction based on camera and planetary orientation
	if input_dir != Vector2.ZERO:
		var camera = character.get_viewport().get_camera_3d()
		movement_direction = get_camera_relative_direction(input_dir, camera)
		
		# Set target rotation for the character model to face movement direction
		if movement_direction.length() > 0.1:
			_calculate_target_rotation()
	else:
		movement_direction = Vector3.ZERO
	
	# Handle running
	is_running = Input.is_action_pressed("ui_sprint")
	
	# Handle jumping
	is_jumping = Input.is_action_just_pressed("jump")
	
	# Update character model rotation
	_update_character_rotation(delta)

func _calculate_target_rotation():
	if planet_node:
		# Calculate rotation relative to planet surface (more stable)
		var local_forward = -character.transform.basis.z  # Character's forward direction
		var local_right = character.transform.basis.x
		
		# Project movement direction onto the character's local plane
		var local_movement = Vector3(
			movement_direction.dot(local_right),
			0,  # Ignore vertical component
			movement_direction.dot(-local_forward)
		).normalized()
		
		if local_movement.length() > 0.1:
			var move_angle = atan2(local_movement.x, local_movement.z)
			# Adjust for mesh orientation if forward is backward
			target_rotation = move_angle + (PI if mesh_forward_is_backward else 0.0)
	else:
		# Regular rotation for non-planetary movement
		var base_rotation = atan2(movement_direction.x, movement_direction.z)
		target_rotation = base_rotation + (0.0 if mesh_forward_is_backward else PI)

func _update_character_rotation(delta: float):
	# Only rotate if we have significant movement
	var has_movement = false
	if planet_node:
		# For planetary movement, check surface velocity
		var surface_velocity = character.velocity - character.velocity.project(gravity_direction)
		has_movement = surface_velocity.length() > 0.2
	else:
		has_movement = abs(character.velocity.x) > 0.2 or abs(character.velocity.z) > 0.2
	
	if has_movement:
		var current_rotation = character_model.rotation.y
		var rotation_diff = wrapf(target_rotation - current_rotation, -PI, PI)
		
		# Only rotate if the difference is significant (prevents spinning from small adjustments)
		if abs(rotation_diff) > 0.1:  # About 6 degrees minimum
			var rotation_speed_adjusted = rotation_speed
			
			# Slower rotation for small changes to make it smoother
			if abs(rotation_diff) < 0.5:  # Less than ~30 degrees
				rotation_speed_adjusted *= 0.5
			
			character_model.rotation.y = lerp_angle(current_rotation, current_rotation + rotation_diff, delta * rotation_speed_adjusted)

func set_input_enabled(enabled: bool):
	_input_enabled = enabled
	
	# If disabling input, also stop movement
	if not enabled:
		movement_direction = Vector3.ZERO
		is_running = false
		is_jumping = false

func is_movement_active() -> bool:
	return movement_direction.length() > 0.1 and _input_enabled

func set_mesh_forward_is_backward(is_backward: bool):
	mesh_forward_is_backward = is_backward 