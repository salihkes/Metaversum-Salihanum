extends CharacterBody3D

# Unified Character Controller with Modular Movement System
# This script combines the best features from humanoid.gd and vr_mode_toggle.gd
# Uses movement modules for different input types (keyboard, VR, etc.)

# Movement parameters
@export var walk_speed := 4.0
@export var run_speed := 8.0
@export var jump_velocity := 8.0
@export var acceleration := 10.0
@export var air_control := 0.3
@export var gravity_multiplier := 2.5

# Animation parameters
@export var arm_swing_amount := 1.2
@export var leg_swing_amount := 0.8
@export var animation_speed := 10.0
@export var remote_min_speed_for_animation := 1

# Planetary gravity variables (from polished humanoid.gd)
var gravity_direction := Vector3.ZERO
var planet_node: Node3D = null
var planet_name := "Ground"
var orientation_speed := 8.0
var custom_is_on_floor := false
var floor_detection_distance := 2.0
var orientation_smoothing := 0.1
var mesh_forward_is_backward := true
var settling_timer := 0.0
var settling_duration := 2.0
var last_alignment := 1.0

# Nodes
var character_model: Node3D
var camera_controller: Node3D
var xr_origin: XROrigin3D

# Animation state
var movement_dir := Vector3.ZERO
var last_y_velocity := 0.0
var was_on_floor := false

# Get the gravity from project settings
var gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * gravity_multiplier

# Sound system
var sound_player: AudioStreamPlayer3D
var victory_sound: AudioStream

# Movement modules
var current_movement: MovementBase
var keyboard_movement: KeyboardMovement
var vr_movement: VRMovement
var is_vr_mode := false

# Remote control state
var is_remote_player := false

# Animation modules
var current_animation: AnimationBase
var humanoid_animation: HumanoidAnimation
var countryball_animation: CountryballAnimation
var character_type := "humanoid"  # Can be "humanoid" or "countryball"

# Grab module
var grab_module: GrabModule

# Signals
signal vr_mode_changed(is_active: bool)

func _ready():
	# Get references to main nodes
	character_model = $CharacterModel
	camera_controller = find_child("CamOrigin")
	xr_origin = find_child("XROrigin3D")
	
	# Make chat bubble invisible initially
	$CharacterModel/ChatBubble/Sprite3D.visible = false
	
	# Setup sounds
	sound_player = $SoundPlayer
	victory_sound = preload("res://src/sound/victory.wav")
	
	# Play victory sound on initialization
	if sound_player and victory_sound:
		sound_player.stream = victory_sound
		sound_player.play()
	
	# Initialize planetary gravity system
	_find_planet()
	
	# Initialize movement modules
	_setup_movement_modules()
	
	# Initialize animation modules
	_setup_animation_modules()
	
	# Initialize grab/interaction module
	_setup_grab_module()
	
	# Check for VR availability and set initial mode
	_initialize_vr_system()

func _setup_movement_modules():
	# Create movement modules
	keyboard_movement = KeyboardMovement.new()
	keyboard_movement.setup(self, character_model)
	
	vr_movement = VRMovement.new()
	vr_movement.setup(self, character_model)
	
	# Connect VR signals
	vr_movement.vr_mode_changed.connect(_on_vr_mode_changed)
	
	# Start with keyboard movement
	current_movement = keyboard_movement
	print("Movement modules initialized")

func _setup_animation_modules():
	# Detect character type based on scene structure
	_detect_character_type()
	
	# Create animation modules
	humanoid_animation = HumanoidAnimation.new()
	humanoid_animation.setup(self, character_model, sound_player)
	
	countryball_animation = CountryballAnimation.new()
	countryball_animation.setup(self, character_model, sound_player)
	
	# Choose appropriate animation module based on character type
	if character_type == "countryball":
		current_animation = countryball_animation
	else:
		current_animation = humanoid_animation
	
	print("Animation modules initialized for character type: ", character_type)

func _setup_grab_module():
	grab_module = GrabModule.new()
	grab_module.setup(self, character_model)

func _detect_character_type():
	# Detect character type based on scene structure
	# Countryball has Base and Emotions nodes, humanoid has limb nodes
	if character_model.has_node("Base") and character_model.has_node("Emotions"):
		character_type = "countryball"
	elif character_model.has_node("LeftArm") and character_model.has_node("RightArm"):
		character_type = "humanoid"
	else:
		# Default to humanoid if uncertain
		character_type = "humanoid"
		print("Warning: Could not detect character type, defaulting to humanoid")

func _initialize_vr_system():
	# Check if VR is available
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface:
		print("OpenXR interface found, initializing VR system")
		call_deferred("_setup_vr")
	else:
		print("No OpenXR interface found, using keyboard mode only")
		set_vr_mode(false)

func _setup_vr():
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.initialize():
		print("XR Interface initialized successfully")
		
		# Wait for proper initialization
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().process_frame
		
		# Enable VR mode by default if available
		set_vr_mode(true)
	else:
		print("Failed to initialize XR Interface, staying in keyboard mode")
		set_vr_mode(false)
		
func _physics_process(delta):
	# Update planetary system
	if planet_node and planet_name != "space":
		_calc_gravity_direction()
		_orient_to_planet(delta)
		_update_custom_floor_detection()

	# For remote players, avoid running local physics and animation to prevent jitter
	if is_remote_player:
		# Ensure gravity direction and floor state are minimally updated for helpers
		if planet_node and planet_name != "space":
			_calc_gravity_direction()
			_update_custom_floor_detection()
		# Skip the rest of local physics and animation
		return
	
	# Configure CharacterBody3D grounding for spherical worlds
	# Ensure floor detection uses the local planet up and snaps to the surface
	if planet_node:
		up_direction = -gravity_direction
		motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		floor_snap_length = 0.6
	else:
		up_direction = Vector3.UP
		floor_snap_length = 0.0
	
	# Sync movement module with current planetary state
	if current_movement:
		current_movement.planet_node = planet_node
		current_movement.gravity_direction = gravity_direction

	# Update current movement module
	if current_movement:
		current_movement.update_input(delta)
		movement_dir = current_movement.get_movement_direction()
	
	# Determine if we're on floor
	var on_floor = _is_character_on_floor()
	
	# Apply gravity
	if not on_floor:
		if planet_node:
			# Apply planetary gravity
			var gravity_strength = gravity
			if velocity.dot(-gravity_direction) < 0:
				gravity_strength = gravity * 1.5
			velocity += gravity_direction * gravity_strength * delta
		else:
			# Apply regular gravity
			var gravity_strength = gravity
			if velocity.y < 0:
				gravity_strength = gravity * 1.5
			velocity.y -= gravity_strength * delta
	
	# Handle jump
	if current_movement and current_movement.is_jumping and on_floor:
		if planet_node:
			velocity += -gravity_direction * jump_velocity
		else:
			velocity.y = jump_velocity
		play_jump_sound()
	
	# Apply movement
	if movement_dir and movement_dir.length() > 0.1:
		var target_speed = run_speed if (current_movement and current_movement.is_running) else walk_speed
		var current_acceleration = acceleration
		if not on_floor:
			current_acceleration *= air_control
		
		var target_velocity = movement_dir * target_speed
		
		if planet_node:
			# Planetary movement
			var current_velocity = velocity
			var surface_velocity = current_velocity - current_velocity.project(gravity_direction)
			surface_velocity = surface_velocity.lerp(target_velocity, delta * current_acceleration)
			velocity = surface_velocity + current_velocity.project(gravity_direction)
		else:
			# Regular movement
			velocity.x = lerp(velocity.x, target_velocity.x, delta * current_acceleration)
			velocity.z = lerp(velocity.z, target_velocity.z, delta * current_acceleration)
	else:
		# Apply friction when no input
		var on_floor_check = _is_character_on_floor()
		var friction = acceleration * (0.3 if not on_floor_check else 2.5)
		
		if planet_node:
			var current_velocity = velocity
			var surface_velocity = current_velocity - current_velocity.project(gravity_direction)
			
			if on_floor_check:
				surface_velocity = surface_velocity.lerp(Vector3.ZERO, delta * friction)
				if surface_velocity.length() < 0.3:
					surface_velocity = surface_velocity.lerp(Vector3.ZERO, delta * friction * 5.0)
				if surface_velocity.length() < 0.15:
					surface_velocity = Vector3.ZERO
			else:
				surface_velocity = surface_velocity.lerp(Vector3.ZERO, delta * friction * 0.4)
			
			velocity = surface_velocity + current_velocity.project(gravity_direction)
		else:
			# Regular movement friction
			var friction_multiplier = friction
			if abs(velocity.x) < 0.3:
				velocity.x = lerp(velocity.x, 0.0, delta * friction_multiplier * 5.0)
			else:
				velocity.x = lerp(velocity.x, 0.0, delta * friction_multiplier)
			
			if abs(velocity.z) < 0.3:
				velocity.z = lerp(velocity.z, 0.0, delta * friction_multiplier * 5.0)
			else:
				velocity.z = lerp(velocity.z, 0.0, delta * friction_multiplier)
			
			if abs(velocity.x) < 0.15:
				velocity.x = 0.0
			if abs(velocity.z) < 0.15:
				velocity.z = 0.0
	
	# Safety velocity clamping
	if planet_node:
		var surface_velocity = velocity - velocity.project(gravity_direction)
		if surface_velocity.length() < 0.2:
			velocity = velocity.project(gravity_direction)
	else:
		if abs(velocity.x) < 0.2:
			velocity.x = 0.0
		if abs(velocity.z) < 0.2:
			velocity.z = 0.0
	
	# Move the character
	move_and_slide()
	
	# Adjust to planet surface if needed
	if planet_node and _is_character_on_floor():
		var is_jumping = false
		if planet_node:
			var velocity_away_from_planet = velocity.dot(-gravity_direction)
			is_jumping = velocity_away_from_planet > 1.0
		else:
			is_jumping = velocity.y > 1.0
		
		if not is_jumping:
			_adjust_to_planet_surface()
	
	# Safety check for planet distance
	if planet_node:
		var planet_radius = _get_planet_radius()
		var distance_to_center = global_position.distance_to(planet_node.global_position)
		var max_distance = planet_radius + 10.0
		
		if distance_to_center > max_distance:
			var direction_to_planet = (planet_node.global_position - global_position).normalized()
			global_position = planet_node.global_position - direction_to_planet * max_distance
			print("Character too far from planet, pulled back to surface")
	
	# Animate the character (local players only; remote players are animated via network updates)
	if not is_remote_player and current_animation:
		var speed: float
		if planet_node:
			var surface_velocity = velocity - velocity.project(gravity_direction)
			speed = surface_velocity.length()
		else:
			speed = Vector2(velocity.x, velocity.z).length()
		
		var is_running = current_movement and current_movement.is_running
		current_animation.animate(delta, speed, movement_dir, is_running, on_floor)

	# Update grab system (local only)
	if not is_remote_player and grab_module:
		grab_module.update(delta)
	
	# Handle jump sound detection (local only)
	if not is_remote_player:
		if was_on_floor and not on_floor and ((planet_node and velocity.dot(-gravity_direction) > 0) or (not planet_node and velocity.y > 0)):
			play_jump_sound()
	
	# Save previous state
	last_y_velocity = velocity.y if not planet_node else velocity.dot(-gravity_direction)
	was_on_floor = on_floor

# VR Mode Management
func toggle_vr_mode():
	var xr_interface = XRServer.find_interface("OpenXR")
	if xr_interface and xr_interface.is_initialized():
		set_vr_mode(not is_vr_mode)
	else:
		print("Cannot toggle VR mode - OpenXR interface not available")

func set_vr_mode(active: bool):
	is_vr_mode = active
	
	# Switch movement modules
	if current_movement:
		current_movement.cleanup()
	
	if active:
		current_movement = vr_movement
		vr_movement.set_vr_active(true)
	else:
		current_movement = keyboard_movement
		if vr_movement:
			vr_movement.set_vr_active(false)
	
	# Enable/disable relevant nodes
	if xr_origin:
		xr_origin.visible = active
		xr_origin.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	
	if camera_controller:
		camera_controller.visible = not active
		camera_controller.process_mode = Node.PROCESS_MODE_INHERIT if not active else Node.PROCESS_MODE_DISABLED
	
	# Hide head mesh in VR mode for local player
	var local_player_node = get_node_or_null("LocalPlayer")
	if get_node_or_null("CharacterModel") and local_player_node:
		if get_node_or_null("CharacterModel"):
			get_node("CharacterModel").visible = not active
	
	# Handle XR viewport
	_handle_xr_viewport(active)
	
	# Configure audio for VR
	_configure_vr_audio(active)
	
	# Inform grab module
	if grab_module:
		grab_module.set_vr_active(active)
	
	# Emit signal
	vr_mode_changed.emit(active)
	print("VR mode " + ("enabled" if active else "disabled"))

func _handle_xr_viewport(enable: bool):
	var xr_interface = XRServer.find_interface("OpenXR")
	if not xr_interface or not xr_interface.is_initialized():
		return
	
	var root_viewport = get_tree().root
	if root_viewport:
		root_viewport.use_xr = enable
		print("XR viewport " + ("enabled" if enable else "disabled"))

func _configure_vr_audio(vr_active: bool):
	var npc_spatial_audio = get_node_or_null("/root/workspace/NPC2/Skeleton3D/AudioStreamPlayer3D")
	var global_audio = get_node_or_null("/root/workspace/AudioStreamPlayer")
	var npc = get_node_or_null("/root/workspace/NPC2/Skeleton3D")
	
	if vr_active:
		# Use non-spatial audio in VR
		if npc_spatial_audio:
			npc_spatial_audio.volume_db = -80.0
		if npc and "use_vr_audio" in npc:
			npc.use_vr_audio = true
			if "vr_audio_player" in npc:
				npc.vr_audio_player = global_audio
	else:
		# Restore spatial audio
		if npc_spatial_audio:
			npc_spatial_audio.volume_db = 0.0
		if npc and "use_vr_audio" in npc:
			npc.use_vr_audio = false

func _on_vr_mode_changed(is_active: bool):
	# Handle additional VR mode changes if needed
	pass

# Planetary System (from polished humanoid.gd)
func _find_planet():
	var parent = get_parent()
	if parent and parent.has_node("Planet"):
		planet_node = parent.get_node("Planet")
		planet_name = "Planet"
	else:
		var root = get_tree().current_scene
		if root:
			var planets = _find_nodes_by_name(root, "Planet")
			if planets.size() > 0:
				planet_node = planets[0]
				planet_name = "Planet"
	
	if planet_node:
		print("Found planet: ", planet_node.name)
		_calc_gravity_direction()
		_ensure_on_planet_surface()
	else:
		print("No planet found, using default gravity")

func _find_nodes_by_name(node: Node, name: String) -> Array:
	var result = []
	if node.name == name:
		result.append(node)
	for child in node.get_children():
		result.append_array(_find_nodes_by_name(child, name))
	return result

func _calc_gravity_direction():
	if planet_node:
		gravity_direction = (planet_node.global_transform.origin - global_transform.origin).normalized()
	else:
		gravity_direction = Vector3.DOWN

func _ensure_on_planet_surface():
	if not planet_node:
		return
	
	var planet_radius = _get_planet_radius()
	var distance_to_center = global_position.distance_to(planet_node.global_position)
	
	if distance_to_center < planet_radius + 2.0:
		var direction_from_center = (global_position - planet_node.global_position).normalized()
		if direction_from_center.length() < 0.1:
			direction_from_center = Vector3.UP
		
		global_position = planet_node.global_position + direction_from_center * (planet_radius + 3.0)
		print("Repositioned character to planet surface")

func _get_planet_radius() -> float:
	if not planet_node:
		return 1.0
	
	if planet_node.has_node("CollisionShape3D"):
		var collision_shape = planet_node.get_node("CollisionShape3D")
		if collision_shape.shape is SphereShape3D:
			var sphere_shape = collision_shape.shape as SphereShape3D
			var shape_radius = sphere_shape.radius
			var scale_factor = collision_shape.transform.basis.get_scale().x
			var final_radius = shape_radius * scale_factor
			
			var workspace_scale = 1.0
			var parent = get_parent()
			if parent:
				workspace_scale = parent.transform.basis.get_scale().x
			
			return final_radius * workspace_scale
	
	return 25.0

func _orient_to_planet(delta):
	if not planet_node:
		return
	
	if not _is_character_on_floor():
		settling_timer = 0.0
		return
	
	var surface_velocity = velocity - velocity.project(gravity_direction)
	var is_moving = surface_velocity.length() > 0.2
	
	if is_moving:
		settling_timer = 0.0
	else:
		settling_timer += delta
	
	var target_up = -gravity_direction
	var current_up = transform.basis.y
	var alignment = current_up.dot(target_up)
	last_alignment = alignment
	
	var alignment_threshold = 0.98
	var is_settling = settling_timer > 0.2
	
	if is_settling:
		alignment_threshold = 0.9995
	elif not is_moving:
		alignment_threshold = 0.985
	
	if is_moving:
		alignment_threshold = 0.99
	
	if alignment < alignment_threshold:
		var rotation_axis = current_up.cross(target_up)
		var min_rotation_threshold = 0.01 if is_moving else 0.001
		
		if rotation_axis.length() > min_rotation_threshold:
			rotation_axis = rotation_axis.normalized()
			var angle = current_up.angle_to(target_up)
			
			var rotation_amount: float
			if is_settling:
				rotation_amount = min(angle, orientation_speed * delta * 0.02)
			elif not is_moving:
				rotation_amount = min(angle, orientation_speed * delta * 0.1)
			elif alignment < 0.5:
				rotation_amount = min(angle, orientation_speed * delta * 0.8)
			else:
				rotation_amount = min(angle, orientation_speed * delta * 0.4)
			
			var rotation_quat = Quaternion(rotation_axis, rotation_amount)
			transform.basis = Basis(rotation_quat) * transform.basis
			transform.basis = transform.basis.orthonormalized()
	
	# Enhanced stability using direct lerp for all cases
	if _is_character_on_floor():
		var base_factor = 0.05
		if is_moving:
			base_factor = 0.15
		else:
			base_factor = 0.08
		
		var lerp_factor = min(orientation_speed * delta * base_factor, 0.3)
		var new_up = current_up.lerp(target_up, lerp_factor).normalized()
		
		var current_forward = transform.basis.z
		var right = new_up.cross(current_forward)
		
		if right.length() < 0.1:
			right = Vector3.RIGHT if abs(new_up.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
			right = new_up.cross(right).normalized()
		else:
			right = right.normalized()
		
		var forward = right.cross(new_up).normalized()
		
		transform.basis.x = right
		transform.basis.y = new_up
		transform.basis.z = forward

func _update_custom_floor_detection():
	if not planet_node:
		custom_is_on_floor = is_on_floor()
		return
	
	var planet_radius = _get_planet_radius()
	var distance_to_center = global_position.distance_to(planet_node.global_position)
	var distance_to_surface = distance_to_center - planet_radius
	
	custom_is_on_floor = distance_to_surface <= floor_detection_distance
	
	if custom_is_on_floor:
		var space_state = get_world_3d().direct_space_state
		var query = PhysicsRayQueryParameters3D.create(
			global_position,
			global_position + gravity_direction * floor_detection_distance * 1.5
		)
		query.exclude = [self]
		
		var result = space_state.intersect_ray(query)
		if result.is_empty():
			custom_is_on_floor = distance_to_surface <= floor_detection_distance * 0.5
		else:
			custom_is_on_floor = true

func _is_character_on_floor() -> bool:
	if not planet_node:
		return is_on_floor()
	else:
		var floor_detected = custom_is_on_floor or is_on_floor()
		
		if not floor_detected:
			var planet_radius = _get_planet_radius()
			var distance_to_center = global_position.distance_to(planet_node.global_position)
			var distance_to_surface = distance_to_center - planet_radius
			var surface_velocity = velocity - velocity.project(gravity_direction)
			
			if distance_to_surface <= floor_detection_distance * 1.2 and surface_velocity.length() < 0.2:
				floor_detected = true
		
		return floor_detected

func _adjust_to_planet_surface():
	if not planet_node:
		return
	
	var planet_radius = _get_planet_radius()
	var distance_to_center = global_position.distance_to(planet_node.global_position)
	var distance_to_surface = distance_to_center - planet_radius
	var target_surface_distance = 0.1
	
	if distance_to_surface > target_surface_distance + 0.05:
		var direction_from_center = (global_position - planet_node.global_position).normalized()
		var target_position = planet_node.global_position + direction_from_center * (planet_radius + target_surface_distance)
		
		var adjustment_strength = 0.1
		var surface_velocity = velocity - velocity.project(gravity_direction)
		if surface_velocity.length() > 0.1:
			adjustment_strength = 0.3
		
		global_position = global_position.lerp(target_position, adjustment_strength)
		
		if distance_to_surface > target_surface_distance + 0.5:
			var pull_velocity = gravity_direction * min(distance_to_surface * 2.0, 5.0)
			velocity += pull_velocity * 0.1

# Animation System (now handled by animation modules)

# Sound System (now handled by animation modules)
func play_jump_sound():
	if current_animation:
		current_animation.play_jump_sound()

# Utility Methods
func set_input_enabled(enabled: bool):
	if keyboard_movement:
		keyboard_movement.set_input_enabled(enabled)

func set_as_remote_player():
	set_input_enabled(false)
	is_remote_player = true

func animate_remote_movement(speed, direction):
	# Use animation module for remote player animations
	if current_animation:
		var play_speed = speed
		if remote_min_speed_for_animation > 0.0 and speed < remote_min_speed_for_animation:
			# Treat as idle to avoid micro-jitter animations for remote players
			play_speed = 0.0
		current_animation.animate_remote(play_speed, direction)

# Chat System
func show_chat_bubble(message: String):
	var chat_viewport = $ChatBubbleViewport
	var rich_text = $ChatBubbleViewport/Control/TextureRect/RichTextLabel
	
	rich_text.text = message
	$CharacterModel/ChatBubble/Sprite3D.visible = true
	
	var timer = get_tree().create_timer(5.0)
	timer.timeout.connect(func(): $CharacterModel/ChatBubble/Sprite3D.visible = false)

# Planetary Helper Methods
func set_planet(planet: Node3D, name: String = "Planet"):
	planet_node = planet
	planet_name = name
	if planet_node:
		_calc_gravity_direction()
		print("Set planet: ", planet_name)

func get_current_planet() -> Node3D:
	return planet_node

func set_planet_name(name: String):
	planet_name = name
	print("Setting planet name: ", planet_name)

func is_in_space() -> bool:
	return planet_name == "space" or planet_node == null

func get_distance_to_planet() -> float:
	if planet_node:
		return global_transform.origin.distance_to(planet_node.global_transform.origin)
	return 0.0

func get_gravity_direction() -> Vector3:
	return gravity_direction

func get_surface_up_direction() -> Vector3:
	return -gravity_direction if planet_node else Vector3.UP

func set_mesh_forward_is_backward(is_backward: bool):
	mesh_forward_is_backward = is_backward
	if keyboard_movement:
		keyboard_movement.set_mesh_forward_is_backward(is_backward)
	print("Mesh forward is backward: ", mesh_forward_is_backward)

func toggle_mesh_orientation():
	mesh_forward_is_backward = !mesh_forward_is_backward
	if keyboard_movement:
		keyboard_movement.set_mesh_forward_is_backward(mesh_forward_is_backward)
	print("Toggled mesh orientation. Forward is backward: ", mesh_forward_is_backward)

# Texture Manager Compatibility Methods
func get_base_mesh() -> MeshInstance3D:
	"""Get the base mesh for texture application - mainly for countryball characters"""
	if character_type == "countryball" and current_animation and current_animation.has_method("get_base_mesh"):
		return current_animation.get_base_mesh()
	elif character_model and character_model.has_node("Base"):
		return character_model.get_node("Base")
	return null

func get_character_type() -> String:
	"""Get the character type for external systems"""
	return character_type
