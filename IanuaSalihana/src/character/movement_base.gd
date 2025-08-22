extends RefCounted
class_name MovementBase

# Base class for movement modules
# This defines the interface that all movement types must implement

# References that will be set by the character controller
var character: CharacterBody3D
var character_model: Node3D
var planet_node: Node3D
var gravity_direction: Vector3

# Movement parameters that can be overridden
var walk_speed := 4.0
var run_speed := 8.0
var jump_velocity := 8.0
var acceleration := 10.0
var air_control := 0.3

# Current movement state
var movement_direction := Vector3.ZERO
var is_running := false
var is_jumping := false

func _init():
	pass

# Virtual methods that must be implemented by subclasses
func setup(char: CharacterBody3D, model: Node3D) -> void:
	character = char
	character_model = model

func update_input(delta: float) -> void:
	# Override in subclasses to handle input
	pass

func get_movement_direction() -> Vector3:
	# Override in subclasses to return current movement direction
	return movement_direction

func is_movement_active() -> bool:
	# Override in subclasses to indicate if movement is active
	return movement_direction.length() > 0.1

func cleanup() -> void:
	# Override in subclasses for cleanup when switching movement types
	pass

# Helper method to get camera-relative movement direction
func get_camera_relative_direction(input_dir: Vector2, camera: Camera3D) -> Vector3:
	if not camera:
		return Vector3.ZERO
	
	var camera_transform = camera.get_global_transform()
	
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
		
		# Combine input with surface-relative directions
		return (forward * -input_dir.y + right * input_dir.x).normalized()
	else:
		# Regular movement - ignore Y component
		var forward = -camera_transform.basis.z
		forward.y = 0
		forward = forward.normalized()
		
		var right = camera_transform.basis.x
		right.y = 0
		right = right.normalized()
		
		return (forward * -input_dir.y + right * input_dir.x).normalized() 