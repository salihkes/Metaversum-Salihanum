extends NpcAction

## Instantly teleports the NPC to a position. Finishes immediately.

var target_position: Vector3 = Vector3.ZERO


func start(npc: CharacterBody3D) -> void:
	_finished = false
	npc.position = target_position
	print("[Teleport] %s teleported to %s" % [npc.name, target_position])
	_finished = true
