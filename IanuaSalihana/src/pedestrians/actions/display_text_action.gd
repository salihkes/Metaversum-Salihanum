extends NpcAction

## Shows a text message above the NPC's head.
## Finishes after `duration` seconds.

var message: String = ""
var duration: float = 3.0
var _timer: float = 0.0


func start(npc: CharacterBody3D) -> void:
	_finished = false
	_timer = 0.0

	if npc.has_method("show_chat_bubble"):
		npc.show_chat_bubble(message)

	print("[DisplayText] %s says: '%s'" % [npc.name, message])


func process(npc: CharacterBody3D, delta: float) -> void:
	_timer += delta
	if _timer >= duration:
		_finished = true


func stop(npc: CharacterBody3D) -> void:
	if npc.has_method("hide_chat_bubble"):
		npc.hide_chat_bubble()
