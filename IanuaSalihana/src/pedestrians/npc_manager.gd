extends Node

## Manages all pre-placed NPCs in the scene.
##
## Responsibilities:
##  • Discover NPC nodes under the "NPCs" container
##  • Track authority (earliest connected client owns NPC movement)
##  • When authority: run AI locally, send transforms to server
##  • When not authority: apply transforms received from server
##  • Broadcast/receive action events (text, animations) for sync
##  • When offline: always act as authority

var _npcs: Dictionary = {}         # npc_id -> NPC node
var _is_authority := true          # default true (offline)
var _network_controller = null
var _path_network = null           # NpcPathNetwork node (if present)
var _send_timer := 0.0
var _ready_done := false
var _pending_messages: Array = []  # messages received before discovery
const SEND_INTERVAL := 0.1        # seconds between network updates


func _ready():
	# Discover immediately — NPC nodes are already in the tree
	_path_network = get_parent().get_node_or_null("NpcPathNetwork")
	_discover_npcs()

	_network_controller = get_node_or_null("/root/NetworkController")
	if _network_controller == null:
		print("[NpcManager] No NetworkController found – running in offline mode")
		_set_authority(true)
	else:
		_set_authority(not _network_controller._connected)

	_ready_done = true

	# Replay any messages that arrived before we were ready
	for msg in _pending_messages:
		_process_pending(msg)
	_pending_messages.clear()


func _discover_npcs():
	var container = get_parent().get_node_or_null("NPCs")
	if not container:
		print("[NpcManager] No 'NPCs' node found in workspace")
		return

	for child in container.get_children():
		if child.has_method("set_authority"):
			var npc_id = child.npc_id if child.npc_id != "" else child.name
			_npcs[npc_id] = child
			child.npc_id = npc_id
			if _path_network and child.has_method("set_path_network"):
				child.set_path_network(_path_network)
			if child.has_method("set_npc_manager"):
				child.set_npc_manager(self)
			print("[NpcManager] Registered NPC: ", npc_id)

	print("[NpcManager] Total NPCs: ", _npcs.size())


func _process(delta):
	if not _is_authority:
		return
	if _npcs.is_empty():
		return

	_send_timer += delta
	if _send_timer >= SEND_INTERVAL:
		_send_timer = 0.0
		_send_npc_transforms()


func _send_npc_transforms():
	if _network_controller == null or not _network_controller._connected:
		return

	var transforms = {}
	for npc_id in _npcs:
		var npc = _npcs[npc_id]
		if not is_instance_valid(npc):
			continue
		transforms[npc_id] = {
			"x": npc.position.x,
			"y": npc.position.y,
			"z": npc.position.z,
			"rot_y": npc.get_model_rotation_y()
		}

	if transforms.is_empty():
		return

	_network_controller._send_message({
		"type": "npc_transform",
		"transforms": transforms
	})


# ── NPC Chat ────────────────────────────────────────────────────────

const NPC_CHAT_RADIUS := 15.0  # global units — how close you need to be to talk

func find_nearest_npc_to_player() -> String:
	"""Find the nearest NPC within chat radius of the local player."""
	if not _network_controller or not is_instance_valid(_network_controller._local_player):
		return ""

	var player_pos: Vector3 = _network_controller._local_player.global_position
	var best_id := ""
	var best_dist := INF

	for npc_id in _npcs:
		var npc = _npcs[npc_id]
		if not is_instance_valid(npc):
			continue
		var dist: float = player_pos.distance_to(npc.global_position)
		if dist < best_dist:
			best_dist = dist
			best_id = npc_id

	if best_dist <= NPC_CHAT_RADIUS:
		return best_id
	return ""


func send_npc_chat(npc_id: String, message: String):
	"""Send a chat message to an NPC (server handles LLM)."""
	if _network_controller and _network_controller._connected:
		# Stop the NPC immediately while LLM is thinking
		if npc_id in _npcs:
			var npc = _npcs[npc_id]
			if is_instance_valid(npc) and _network_controller._local_player:
				npc.start_chatting(_network_controller._local_player)
		_network_controller._send_message({
			"type": "npc_chat",
			"npc_id": npc_id,
			"message": message
		})


func handle_npc_chat_response(data: Dictionary):
	"""Server sent an NPC's LLM response — show it on the NPC."""
	var npc_id = str(data.get("npc_id", ""))
	var message = str(data.get("message", ""))
	var is_error = data.get("error", false)

	if npc_id in _npcs:
		var npc = _npcs[npc_id]
		if is_instance_valid(npc):
			if _network_controller and is_instance_valid(_network_controller._local_player):
				npc.start_chatting(_network_controller._local_player)
			npc.show_chat_bubble(message)

			# Play TTS audio if included, otherwise just talk animation
			var audio_b64 = data.get("audio", "")
			if typeof(audio_b64) == TYPE_STRING and audio_b64 != "":
				npc.play_inline_audio(audio_b64)
			else:
				npc.start_talk_animation(max(3.0, message.length() * 0.05))

			var dur = max(4.0, message.length() * 0.06)
			if npc.has_method("_auto_hide_bubble"):
				npc._auto_hide_bubble(dur)

	# Also show in the chat UI so the player can read the full response
	if _network_controller:
		var display_name = npc_id
		# Try to get a nicer name from the NPC node
		if npc_id in _npcs and is_instance_valid(_npcs[npc_id]):
			display_name = _npcs[npc_id].name
		_network_controller.emit_signal("chat_message_received", display_name, message)


# ── Action event broadcasting (authority → server → other clients) ──

func broadcast_npc_event(npc_id: String, event: String, data: Dictionary):
	"""Called by authority NPC when an action effect should be visible to all."""
	if not _is_authority:
		return
	if _network_controller == null or not _network_controller._connected:
		return

	_network_controller._send_message({
		"type": "npc_action_event",
		"npc_id": npc_id,
		"event": event,
		"data": data
	})


# ── Network message handlers (called by NetworkController) ─────────

func handle_npc_authority(data: Dictionary):
	if not _ready_done or _npcs.is_empty():
		_pending_messages.append({"handler": "authority", "data": data})
		return
	_do_handle_authority(data)

func handle_npc_transform(data: Dictionary):
	if not _ready_done or _npcs.is_empty():
		return  # drop stale transforms, no need to queue
	_do_handle_transform(data)

func handle_npc_initial_state(data: Dictionary):
	if not _ready_done or _npcs.is_empty():
		_pending_messages.append({"handler": "initial_state", "data": data})
		return
	_do_handle_initial_state(data)

func handle_npc_schedule(data: Dictionary):
	if not _ready_done or _npcs.is_empty():
		_pending_messages.append({"handler": "schedule", "data": data})
		return
	_do_handle_schedule(data)

func handle_npc_action_event(data: Dictionary):
	if not _ready_done or _npcs.is_empty():
		return  # drop, visual only
	_do_handle_action_event(data)


# ── Actual handlers ────────────────────────────────────────────────

func _do_handle_authority(data: Dictionary):
	var authority_id = int(data.get("authority_client_id", -1))
	if _network_controller:
		var is_me = authority_id == _network_controller._client_id
		print("[NpcManager] Authority update: client ", authority_id,
			  " (me: ", is_me, ")")
		_set_authority(is_me)
	else:
		_set_authority(true)


func _do_handle_transform(data: Dictionary):
	if _is_authority:
		return
	var transforms = data.get("transforms", {})
	for npc_id in transforms:
		if npc_id in _npcs:
			var npc = _npcs[npc_id]
			if not is_instance_valid(npc):
				continue
			var t = transforms[npc_id]
			npc.apply_remote_transform(
				Vector3(t.x, t.y, t.z),
				float(t.rot_y)
			)


func _do_handle_initial_state(data: Dictionary):
	var transforms = data.get("transforms", {})
	for npc_id in transforms:
		if npc_id in _npcs:
			var npc = _npcs[npc_id]
			if not is_instance_valid(npc):
				continue
			var t = transforms[npc_id]
			var pos = Vector3(t.x, t.y, t.z)
			npc.position = pos
			npc.apply_remote_transform(pos, float(t.get("rot_y", 0.0)))
			npc._spawn_position = pos
			npc._active_schedule_idx = -1
			npc._schedule_check_timer = 0.0


func _do_handle_schedule(data: Dictionary):
	var npc_id = str(data.get("npc_id", ""))
	var entries = data.get("schedule", [])
	if npc_id in _npcs:
		var npc = _npcs[npc_id]
		if is_instance_valid(npc) and npc.has_method("apply_server_schedule"):
			npc.apply_server_schedule(entries)
	else:
		print("[NpcManager] Schedule received for unknown NPC: ", npc_id)


func _do_handle_action_event(data: Dictionary):
	if _is_authority:
		return
	var npc_id = str(data.get("npc_id", ""))
	var event = str(data.get("event", ""))
	var event_data = data.get("data", {})
	if npc_id in _npcs:
		var npc = _npcs[npc_id]
		if is_instance_valid(npc) and npc.has_method("handle_remote_event"):
			npc.handle_remote_event(event, event_data)


func handle_npc_audio_data(data: Dictionary):
	"""Server sent an audio file we requested. Cache it locally."""
	var path = str(data.get("path", ""))
	var audio_b64 = str(data.get("data", ""))
	var fmt = str(data.get("format", "mp3"))
	if path == "" or audio_b64 == "":
		return

	var cache_path = "user://npc_audio_cache/" + path
	var dir_path = cache_path.get_base_dir()

	# Ensure cache directory exists
	DirAccess.make_dir_recursive_absolute(dir_path)

	var raw_bytes = Marshalls.base64_to_raw(audio_b64)
	var file = FileAccess.open(cache_path, FileAccess.WRITE)
	if file:
		file.store_buffer(raw_bytes)
		file.close()
		print("[NpcManager] Cached NPC audio: %s (%d bytes)" % [cache_path, raw_bytes.size()])

		# Signal any NPC waiting for this audio
		for npc_id in _npcs:
			var npc = _npcs[npc_id]
			if is_instance_valid(npc) and npc.has_method("_on_audio_cached"):
				npc._on_audio_cached(path)


func handle_npc_audio_sync(data: Dictionary):
	"""Server tells us an NPC is currently playing audio (mid-join sync)."""
	var npc_id = str(data.get("npc_id", ""))
	var path = str(data.get("path", ""))
	var offset = float(data.get("offset", 0.0))
	var duration = float(data.get("duration", 0.0))

	if npc_id in _npcs:
		var npc = _npcs[npc_id]
		if is_instance_valid(npc) and npc.has_method("play_audio_from_server"):
			npc.play_audio_from_server(path, offset, duration)
	else:
		print("[NpcManager] Audio sync for unknown NPC: ", npc_id)


func request_npc_audio(path: String):
	"""Request an audio file from the server."""
	if _network_controller and _network_controller._connected:
		_network_controller._send_message({
			"type": "npc_audio_request",
			"path": path
		})
		print("[NpcManager] Requesting audio from server: ", path)


func _process_pending(msg: Dictionary):
	match msg.handler:
		"authority":
			_do_handle_authority(msg.data)
		"initial_state":
			_do_handle_initial_state(msg.data)
		"schedule":
			_do_handle_schedule(msg.data)


# ── Internal ───────────────────────────────────────────────────────

func _set_authority(is_auth: bool):
	_is_authority = is_auth
	for npc_id in _npcs:
		var npc = _npcs[npc_id]
		if is_instance_valid(npc):
			npc.set_authority(is_auth)
	print("[NpcManager] Authority set to: ", is_auth)
