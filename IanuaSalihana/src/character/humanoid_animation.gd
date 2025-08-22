extends AnimationBase
class_name HumanoidAnimation

# Humanoid-specific animation implementation

# Animation parameters
var arm_swing_amount := 1.2
var leg_swing_amount := 0.8

# Node references
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var head: MeshInstance3D

func setup(char: CharacterBody3D, model: Node3D, audio_player: AudioStreamPlayer3D) -> void:
	super.setup(char, model, audio_player)
	
	# Get references to humanoid-specific nodes
	left_arm = character_model.find_child("LeftArm")
	right_arm = character_model.find_child("RightArm")
	left_leg = character_model.find_child("LeftLeg")
	right_leg = character_model.find_child("RightLeg2")
	head = character_model.find_child("head")
	
	# Copy parameters from character if they exist
	if character.get("arm_swing_amount") != null:
		arm_swing_amount = character.arm_swing_amount
	if character.get("leg_swing_amount") != null:
		leg_swing_amount = character.leg_swing_amount
	if character.get("animation_speed") != null:
		animation_speed = character.animation_speed
	if character.get("footstep_rate") != null:
		footstep_rate = character.footstep_rate

func animate(delta: float, speed: float, movement_dir: Vector3, is_running: bool, is_on_floor: bool) -> void:
	var max_speed = character.run_speed if is_running else character.walk_speed
	var movement_intensity = clamp(speed / max_speed, 0.0, 1.0)
	
	if movement_intensity > 0.05 and is_on_floor:
		var cycle_speed = animation_speed * movement_intensity * delta
		if is_running:
			cycle_speed *= 1.5
		
		walk_cycle += cycle_speed
		
		# Handle footstep sounds
		footstep_timer -= delta
		if footstep_timer <= 0 and movement_intensity > 0.1:
			play_footstep_sound(movement_intensity)
			footstep_timer = footstep_rate / movement_intensity
		
		walk_cycle = fmod(walk_cycle, 2.0 * PI)
		
		# Calculate limb rotations using sine waves
		var arm_swing = sin(walk_cycle) * arm_swing_amount * movement_intensity
		var leg_swing = sin(walk_cycle) * leg_swing_amount * movement_intensity
		var opposite_swing = sin(walk_cycle + PI) * leg_swing_amount * movement_intensity
		
		# Apply rotations to limbs
		if left_arm:
			left_arm.rotation.x = opposite_swing
		if right_arm:
			right_arm.rotation.x = arm_swing
		if left_leg:
			left_leg.rotation.x = leg_swing
		if right_leg:
			right_leg.rotation.x = opposite_swing
	else:
		if is_on_floor:
			# Return limbs to default position
			if left_arm:
				left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, delta * 5.0)
			if right_arm:
				right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
			if left_leg:
				left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
			if right_leg:
				right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
			footstep_timer = 0.0
	
	# Jumping/falling animation
	if not is_on_floor:
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, PI, delta * 5.0)
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, PI, delta * 5.0)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
	
	# Head looks in movement direction
	if head:
		if movement_intensity > 0.1:
			head.rotation.y = lerp(head.rotation.y, -movement_dir.x * 0.2, delta * 2.0)
		else:
			head.rotation.y = lerp(head.rotation.y, 0.0, delta * 2.0)

func animate_remote(speed: float, direction: Vector3) -> void:
	var max_speed = character.run_speed if speed > character.walk_speed else character.walk_speed
	var movement_intensity = clamp(speed / max_speed, 0.0, 1.0)
	var is_moving = movement_intensity > 0.05
	var is_on_floor = _is_character_on_floor()
	
	if is_moving:
		var movement_dir = direction
	
	# Handle jumping/falling animation for remote players
	if not is_on_floor:
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, PI, 0.1)
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, PI, 0.1)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, 0.1)
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 0.1)
		if head:
			head.rotation.y = lerp(head.rotation.y, -direction.x * 0.2, 0.1)
		footstep_timer = 0.0
		return
	
	# Animate when moving and on ground
	if is_moving and is_on_floor:
		var cycle_speed = animation_speed * movement_intensity * 0.05
		if speed > character.walk_speed:
			cycle_speed *= 1.5
		
		walk_cycle += cycle_speed
		
		footstep_timer -= 0.05
		if footstep_timer <= 0 and movement_intensity > 0.1:
			play_footstep_sound(movement_intensity)
			footstep_timer = footstep_rate / movement_intensity
		
		walk_cycle = fmod(walk_cycle, 2.0 * PI)
		
		var arm_swing = sin(walk_cycle) * arm_swing_amount * movement_intensity
		var leg_swing = sin(walk_cycle) * leg_swing_amount * movement_intensity
		var opposite_swing = sin(walk_cycle + PI) * leg_swing_amount * movement_intensity
		
		if left_arm:
			left_arm.rotation.x = opposite_swing
		if right_arm:
			right_arm.rotation.x = arm_swing
		if left_leg:
			left_leg.rotation.x = leg_swing
		if right_leg:
			right_leg.rotation.x = opposite_swing
		if head:
			head.rotation.y = -direction.x * 0.2
	else:
		# Reset to default pose
		if left_arm:
			left_arm.rotation.x = lerp(left_arm.rotation.x, 0.0, 0.1)
		if right_arm:
			right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, 0.1)
		if left_leg:
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, 0.1)
		if right_leg:
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, 0.1)
		if head:
			head.rotation.y = lerp(head.rotation.y, 0.0, 0.1) 