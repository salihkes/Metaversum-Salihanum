extends NpcAction

## Walks the NPC toward the player stored in "detected_player" metadata.
## Finishes when within stop_distance OR after max_chase_time seconds
## (so the NPC doesn't follow forever).

var stop_distance: float = 4.0
var walk_speed: float = 3.0
var max_chase_time: float = 10.0

var _timer: float = 0.0


func start(npc: CharacterBody3D) -> void:
	_finished = false
	_timer = 0.0
	print("[WalkToPlayer] %s walking toward player" % npc.name)


func process(npc: CharacterBody3D, delta: float) -> void:
	_timer += delta

	var player = npc.get_meta("detected_player", null)
	if not is_instance_valid(player) or _timer >= max_chase_time:
		npc.velocity.x = 0.0
		npc.velocity.z = 0.0
		_finished = true
		return

	# Use global_position to avoid coordinate space issues with 0.2x workspace scale
	var player_node: Node3D = player as Node3D
	var to_player: Vector3 = player_node.global_position - npc.global_position
	to_player.y = 0.0
	var dist: float = to_player.length()

	# stop_distance is in global (world) units — workspace is 0.2x scaled
	if dist <= stop_distance:
		npc.velocity.x = 0.0
		npc.velocity.z = 0.0
		if npc.character_model and dist > 0.01:
			var dir: Vector3 = to_player.normalized()
			npc.character_model.rotation.y = atan2(dir.x, dir.z) + PI
		_finished = true
		return

	var dir: Vector3 = to_player.normalized()
	# Convert global direction back to local velocity
	var local_dir: Vector3 = npc.global_transform.basis.inverse() * dir
	# But since we set velocity directly and move_and_slide works in local space,
	# just use the direction components (workspace scale applies uniformly)
	npc.velocity.x = dir.x * walk_speed
	npc.velocity.z = dir.z * walk_speed

	if npc.character_model:
		var target_rot: float = atan2(dir.x, dir.z) + PI
		npc.character_model.rotation.y = lerp_angle(
			npc.character_model.rotation.y, target_rot, delta * 10.0
		)
