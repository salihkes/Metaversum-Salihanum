extends NpcAction

## Repeats an inner action forever (until the NPC's schedule changes).

var inner_action: NpcAction = null


func start(npc: CharacterBody3D) -> void:
	_finished = false
	if inner_action:
		inner_action.start(npc)


func process(npc: CharacterBody3D, delta: float) -> void:
	if inner_action == null:
		return

	inner_action.process(npc, delta)

	if inner_action.is_finished():
		inner_action.stop(npc)
		# Reset and restart
		if inner_action.has_method("reset"):
			inner_action.reset()
		else:
			inner_action._finished = false
		inner_action.start(npc)


func stop(npc: CharacterBody3D) -> void:
	if inner_action:
		inner_action.stop(npc)
