extends NpcAction

## Waits until any player enters a radius around the NPC, then finishes.
## The detected player is stored on the NPC as metadata for subsequent actions.
## All distances use global_position to handle workspace 0.2x scale correctly.

var radius: float = 15.0


func start(npc: CharacterBody3D) -> void:
	_finished = false
	print("[RadiusDetect] Watching for players within %.1f global units of %s" % [radius, npc.name])


func process(npc: CharacterBody3D, delta: float) -> void:
	var player = _find_nearest_player(npc)
	if player == null:
		return

	var dist: float = _flat_distance(npc.global_position, player.global_position)
	if dist <= radius:
		npc.set_meta("detected_player", player)
		print("[RadiusDetect] Player '%s' detected by %s (dist=%.2f)" % [player.name, npc.name, dist])
		_finished = true


func _find_nearest_player(npc: CharacterBody3D) -> Node3D:
	var workspace = npc.get_parent().get_parent()  # NPCs -> workspace
	if not workspace:
		return null

	var best: Node3D = null
	var best_dist := INF
	var npc_gpos: Vector3 = npc.global_position

	# Local player (direct child of workspace with LocalPlayer marker)
	for child in workspace.get_children():
		if child is CharacterBody3D and child != npc and child.get_node_or_null("LocalPlayer"):
			var d: float = _flat_distance(npc_gpos, child.global_position)
			if d < best_dist:
				best_dist = d
				best = child

	# Remote players (under Players container)
	var players_node = workspace.get_node_or_null("Players")
	if players_node:
		for child in players_node.get_children():
			if child is CharacterBody3D:
				var d: float = _flat_distance(npc_gpos, child.global_position)
				if d < best_dist:
					best_dist = d
					best = child

	return best


func _flat_distance(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
