extends CharacterBody3D

## NPC with schedule-driven waypoint navigation and random wandering.
##
## Navigation priority:
##   1. Path3D network  — NPCs follow sidewalk curves drawn in the editor (DEFAULT)
##   2. NavigationAgent3D — uses baked navmesh if available
##   3. Direct walk      — straight line toward target

# ── Movement ────────────────────────────────────────────────────────
@export var wander_speed := 2.0
@export var travel_speed := 3.0
@export var wander_radius := 30.0
@export var min_walk_time := 2.0
@export var max_walk_time := 4.0
@export var min_idle_time := 1.0
@export var max_idle_time := 3.0
@export var arrival_threshold := 2.0

# ── Animation ───────────────────────────────────────────────────────
@export var arm_swing_amount := 1.2
@export var leg_swing_amount := 0.8
@export var animation_speed := 10.0

# ── Identity ────────────────────────────────────────────────────────
@export var npc_id := ""

# ── Schedule (editable in inspector) ────────────────────────────────
@export var schedule: Array[NpcScheduleEntry] = []

# ── State machine ───────────────────────────────────────────────────
enum State { WANDERING, TRAVELING, AT_WAYPOINT }

var _state: State = State.WANDERING
var _is_authority := true
var _spawn_position := Vector3.ZERO
var _gravity: float

# Chatting (pauses AI while talking to a player)
var _chatting := false
var _chat_target: Node3D = null

# Wandering
var _wander_dir := Vector3.ZERO
var _wander_timer := 0.0
var _wander_walking := false

# Route following (shared by WANDERING-on-path and TRAVELING)
var _route: Array[Vector3] = []
var _route_idx := 0

# Navigation refs
var _path_network = null               # NpcPathNetwork (set by NpcManager)
var _nav_agent: NavigationAgent3D = null
var _target_waypoint_pos := Vector3.ZERO
var _target_waypoint_name := ""

# Schedule
var _active_schedule_idx := -1
var _schedule_check_timer := 0.0
var _env_controller = null

# Action
var _current_action: NpcAction = null
var _pending_action_name := ""

# Stuck detection / avoidance
var _stuck_check_pos := Vector3.ZERO
var _stuck_timer := 0.0
var _avoidance_dir := Vector3.ZERO
var _avoidance_timer := 0.0
const STUCK_CHECK_INTERVAL := 0.4
const STUCK_DISTANCE_THRESHOLD := 0.3
const AVOIDANCE_DURATION := 0.6

# Animation
var _walk_cycle := 0.0

# Remote interpolation
var _remote_target_pos := Vector3.ZERO
var _remote_model_rot_y := 0.0
var _remote_speed := 0.0
var _prev_remote_pos := Vector3.ZERO

# Node refs
var character_model: Node3D
var left_arm: Node3D
var right_arm: Node3D
var left_leg: Node3D
var right_leg: Node3D
var head: MeshInstance3D


# ════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ════════════════════════════════════════════════════════════════════

func _ready():
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity") * 2.5

	for child_name in ["CamOrigin", "XROrigin3D"]:
		var child = get_node_or_null(child_name)
		if child:
			child.queue_free()

	# Keep ChatBubbleViewport for text display actions, just hide the sprite
	var bubble = get_node_or_null("CharacterModel/ChatBubble/Sprite3D")
	if bubble:
		bubble.visible = false

	# Configure spatial audio range for NPC speech/sounds
	var sound = get_node_or_null("SoundPlayer")
	if sound and sound is AudioStreamPlayer3D:
		sound.max_distance = 20.0
		sound.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

	character_model = $CharacterModel
	left_arm  = $CharacterModel/LeftArm
	right_arm = $CharacterModel/RightArm
	left_leg  = $CharacterModel/LeftLeg
	right_leg = $CharacterModel/RightLeg2
	head      = $CharacterModel/head

	_nav_agent = get_node_or_null("NavigationAgent3D")
	if _nav_agent:
		_nav_agent.path_desired_distance = arrival_threshold
		_nav_agent.target_desired_distance = arrival_threshold

	if npc_id == "":
		npc_id = name

	_spawn_position = position
	_remote_target_pos = position
	_prev_remote_pos = position

	await get_tree().process_frame
	_cache_env_controller()
	_enter_wandering()


func _physics_process(delta):
	if not _is_authority:
		position = position.lerp(_remote_target_pos, delta * 10.0)
		if character_model:
			character_model.rotation.y = lerp_angle(
				character_model.rotation.y, _remote_model_rot_y, delta * 10.0
			)
		_animate(delta)
		_update_label_screen_pos()
		return

	if not is_on_floor():
		velocity.y -= _gravity * delta

	# When chatting, stop moving and face the player
	if _chatting:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
		if is_instance_valid(_chat_target) and character_model:
			var to_player: Vector3 = _chat_target.global_position - global_position
			to_player.y = 0.0
			if to_player.length() > 0.1:
				var rot: float = atan2(to_player.x, to_player.z) + PI
				character_model.rotation.y = lerp_angle(character_model.rotation.y, rot, delta * 5.0)
		move_and_slide()
		_animate(delta)
		_update_label_screen_pos()
		return

	_schedule_check_timer -= delta
	if _schedule_check_timer <= 0.0:
		_schedule_check_timer = 1.0
		_check_schedule()

	match _state:
		State.WANDERING:
			_process_wandering(delta)
		State.TRAVELING:
			_process_traveling(delta)
		State.AT_WAYPOINT:
			_process_at_waypoint(delta)

	_update_avoidance(delta)
	move_and_slide()
	_animate(delta)
	_update_label_screen_pos()


# ════════════════════════════════════════════════════════════════════
#  SCHEDULE
# ════════════════════════════════════════════════════════════════════

func _check_schedule():
	if schedule.is_empty():
		if _state != State.WANDERING:
			_enter_wandering()
		return

	var hour := _get_current_hour()
	var best_idx := -1
	var best_hour := -1.0
	for i in schedule.size():
		var entry: NpcScheduleEntry = schedule[i]
		if entry.hour <= hour and entry.hour > best_hour:
			best_hour = entry.hour
			best_idx = i

	if best_idx == _active_schedule_idx:
		return

	_active_schedule_idx = best_idx

	if best_idx < 0:
		_stop_action()
		_enter_wandering()
		return

	var entry: NpcScheduleEntry = schedule[best_idx]
	if entry.waypoint_name == "":
		_stop_action()
		_enter_at_waypoint(entry.action_name)
		return

	var wp_pos = _find_waypoint_position(entry.waypoint_name)
	if wp_pos == null:
		push_warning("[NPC %s] Waypoint '%s' not found" % [npc_id, entry.waypoint_name])
		_enter_wandering()
		return

	_target_waypoint_name = entry.waypoint_name
	_target_waypoint_pos = wp_pos
	_enter_traveling(entry.action_name)


func _get_current_hour() -> float:
	if _env_controller and is_instance_valid(_env_controller):
		return _env_controller.current_time * 24.0
	var t = Time.get_time_dict_from_system()
	return float(t.hour) + float(t.minute) / 60.0


func _cache_env_controller():
	var workspace = _get_workspace()
	if workspace:
		_env_controller = workspace.find_child("EnvironmentController", true, false)


func apply_server_schedule(entries: Array):
	schedule.clear()
	for entry_dict in entries:
		var entry := NpcScheduleEntry.new()
		entry.hour = float(entry_dict.get("hour", 0))
		entry.waypoint_name = str(entry_dict.get("waypoint", ""))
		entry.action_name = str(entry_dict.get("action", ""))
		schedule.append(entry)
	_active_schedule_idx = -1
	_schedule_check_timer = 0.0
	print("[NPC %s] Schedule overridden with %d entries" % [npc_id, schedule.size()])


# ════════════════════════════════════════════════════════════════════
#  STATE: WANDERING
# ════════════════════════════════════════════════════════════════════

func _enter_wandering():
	_state = State.WANDERING
	_wander_walking = false
	_route.clear()
	_route_idx = 0
	_wander_timer = randf_range(min_idle_time, max_idle_time)


func _process_wandering(delta):
	_wander_timer -= delta
	if _wander_timer <= 0.0:
		if _wander_walking:
			_wander_walking = false
			_route.clear()
			_route_idx = 0
			_wander_timer = randf_range(min_idle_time, max_idle_time)
		else:
			_wander_walking = true
			_wander_timer = randf_range(min_walk_time, max_walk_time)
			_pick_wander_target()

	if _wander_walking:
		_follow_route_or_direction(delta, wander_speed)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)


func _pick_wander_target():
	# ── Priority 1: Path3D network ──────────────────────────────────
	if _path_network and _path_network.has_paths():
		var target_pos: Vector3 = _path_network.random_point_near(
			_spawn_position, wander_radius
		)
		_route = _path_network.find_route(position, target_pos)
		_route_idx = 0
		return

	# ── Fallback: random direction ──────────────────────────────────
	_route.clear()
	_route_idx = 0
	var offset = position - _spawn_position
	offset.y = 0.0
	if offset.length() > wander_radius * 0.7:
		_wander_dir = (-offset.normalized() + _random_dir() * 0.3).normalized()
	else:
		_wander_dir = _random_dir()

	if character_model and _wander_dir.length() > 0.1:
		character_model.rotation.y = atan2(_wander_dir.x, _wander_dir.z) + PI


# ════════════════════════════════════════════════════════════════════
#  STATE: TRAVELING (to waypoint)
# ════════════════════════════════════════════════════════════════════

func _enter_traveling(action_name: String):
	_state = State.TRAVELING
	_pending_action_name = action_name
	_route.clear()
	_route_idx = 0
	print("[NPC %s] Traveling to waypoint '%s'" % [npc_id, _target_waypoint_name])

	# ── Priority 1: Path3D network ──────────────────────────────────
	if _path_network and _path_network.has_paths():
		_route = _path_network.find_route(position, _target_waypoint_pos)
		_route_idx = 0
		return

	# ── Priority 2: NavigationAgent3D ───────────────────────────────
	if _nav_agent:
		_nav_agent.target_position = _target_waypoint_pos

	# Priority 3 (direct walk) needs no setup


func _process_traveling(delta):
	var flat_dist := Vector2(
		position.x - _target_waypoint_pos.x,
		position.z - _target_waypoint_pos.z
	).length()

	if flat_dist <= arrival_threshold:
		_enter_at_waypoint(_pending_action_name)
		return

	_follow_route_or_direction(delta, travel_speed)


# ════════════════════════════════════════════════════════════════════
#  ROUTE FOLLOWING (used by both WANDERING and TRAVELING)
# ════════════════════════════════════════════════════════════════════

func _follow_route_or_direction(delta: float, speed: float):
	var direction := Vector3.ZERO

	if _route.size() > 0 and _route_idx < _route.size():
		# ── Following a computed route ──────────────────────────────
		var target := _route[_route_idx]
		var to_target := target - position
		to_target.y = 0.0

		if to_target.length() <= arrival_threshold:
			_route_idx += 1
			if _route_idx >= _route.size():
				# Route complete
				if _state == State.WANDERING:
					_wander_walking = false
					_wander_timer = randf_range(min_idle_time, max_idle_time)
					velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
					velocity.z = lerp(velocity.z, 0.0, delta * 10.0)
					return
				# TRAVELING: arrival handled in _process_traveling
				return
			target = _route[_route_idx]
			to_target = target - position
			to_target.y = 0.0

		if to_target.length() > 0.01:
			direction = to_target.normalized()

	elif _nav_agent and not _nav_agent.is_navigation_finished():
		# ── NavigationAgent3D fallback ──────────────────────────────
		var next_pos := _nav_agent.get_next_path_position()
		direction = (next_pos - position)
		direction.y = 0.0
		if direction.length() > 0.01:
			direction = direction.normalized()

	elif _state == State.TRAVELING:
		# ── Direct walk fallback ────────────────────────────────────
		direction = (_target_waypoint_pos - position)
		direction.y = 0.0
		if direction.length() > 0.01:
			direction = direction.normalized()

	elif _wander_dir.length() > 0.01:
		# ── Random direction fallback (wandering without paths) ─────
		direction = _wander_dir

	if direction.length() > 0.01:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
		if character_model:
			var target_rot = atan2(direction.x, direction.z) + PI
			character_model.rotation.y = lerp_angle(
				character_model.rotation.y, target_rot, delta * 10.0
			)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)


# ════════════════════════════════════════════════════════════════════
#  STATE: AT_WAYPOINT
# ════════════════════════════════════════════════════════════════════

func _enter_at_waypoint(action_name: String):
	_state = State.AT_WAYPOINT
	_route.clear()
	_route_idx = 0
	velocity.x = 0.0
	velocity.z = 0.0
	print("[NPC %s] Arrived at waypoint '%s'" % [npc_id, _target_waypoint_name])
	if action_name != "":
		_start_action(action_name)


func _process_at_waypoint(delta):
	if _current_action:
		# Let the action control movement (walk to player, return to post, etc.)
		_current_action.process(self, delta)
	else:
		velocity.x = lerp(velocity.x, 0.0, delta * 10.0)
		velocity.z = lerp(velocity.z, 0.0, delta * 10.0)


# ════════════════════════════════════════════════════════════════════
#  ACTION SYSTEM (placeholder)
# ════════════════════════════════════════════════════════════════════

func _start_action(action_name: String):
	_stop_action()
	_current_action = NpcAction.create(action_name)
	_current_action.start(self)


func _stop_action():
	if _current_action:
		_current_action.stop(self)
		_current_action = null


# ════════════════════════════════════════════════════════════════════
#  WAYPOINT LOOKUP
# ════════════════════════════════════════════════════════════════════

func _find_waypoint_position(waypoint_name: String) -> Variant:
	var workspace = _get_workspace()
	if not workspace:
		return null
	var waypoints = workspace.get_node_or_null("Waypoints")
	if not waypoints:
		return null
	var marker = waypoints.get_node_or_null(waypoint_name)
	if not marker:
		return null
	return marker.position


func _get_workspace() -> Node:
	var parent = get_parent()
	if parent:
		return parent.get_parent()
	return null


# ════════════════════════════════════════════════════════════════════
#  STUCK DETECTION / AVOIDANCE
# ════════════════════════════════════════════════════════════════════

func _update_avoidance(delta: float):
	# While actively avoiding, steer sideways
	if _avoidance_timer > 0.0:
		_avoidance_timer -= delta
		velocity.x += _avoidance_dir.x * wander_speed * 1.2
		velocity.z += _avoidance_dir.z * wander_speed * 1.2
		return

	# Only check when the NPC is trying to move
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if horiz_speed < 0.1:
		_stuck_check_pos = position
		_stuck_timer = 0.0
		return

	_stuck_timer += delta
	if _stuck_timer >= STUCK_CHECK_INTERVAL:
		var flat_moved := Vector2(
			position.x - _stuck_check_pos.x,
			position.z - _stuck_check_pos.z
		).length()

		if flat_moved < STUCK_DISTANCE_THRESHOLD:
			# Stuck — pick a perpendicular direction to dodge
			var forward := Vector2(velocity.x, velocity.z).normalized()
			# Randomly go left or right
			var side := 1.0 if randf() > 0.5 else -1.0
			_avoidance_dir = Vector3(-forward.y * side, 0.0, forward.x * side)
			_avoidance_timer = AVOIDANCE_DURATION

		_stuck_check_pos = position
		_stuck_timer = 0.0


# ════════════════════════════════════════════════════════════════════
#  ANIMATION
# ════════════════════════════════════════════════════════════════════

func _animate(delta):
	var speed: float
	if _is_authority:
		speed = Vector2(velocity.x, velocity.z).length()
	else:
		speed = _remote_speed

	var max_spd = max(travel_speed, wander_speed)
	var intensity = clamp(speed / max(max_spd, 0.01), 0.0, 1.0)

	if not is_on_floor() and _is_authority:
		left_arm.rotation.x  = lerp(left_arm.rotation.x,  PI, delta * 5.0)
		right_arm.rotation.x = lerp(right_arm.rotation.x, PI, delta * 5.0)
		left_leg.rotation.x  = lerp(left_leg.rotation.x,  0.0, delta * 5.0)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
		return

	# Talk animation — arms gesture, legs stay still
	if _remote_talking:
		_remote_talk_elapsed += delta
		_remote_talk_timer -= delta
		if _remote_talk_timer <= 0.0:
			_remote_talking = false
		else:
			var t := _remote_talk_elapsed
			var wave_a := (sin(t * 0.8) + 1.0) * 0.5
			var wave_b := (sin(t * 2.3) + 1.0) * 0.5
			var talk: float = clampf((wave_a * 0.4 + wave_b * 0.6) * 1.5 - 0.2, 0.0, 1.0)
			right_arm.rotation.x = sin(t * 1.4) * 0.3 * talk
			left_arm.rotation.x = sin(t * 0.7) * 0.08 * talk
			left_leg.rotation.x = lerp(left_leg.rotation.x, 0.0, delta * 5.0)
			right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)
		return

	if intensity > 0.01:
		_walk_cycle += animation_speed * intensity * delta
		_walk_cycle = fmod(_walk_cycle, TAU)
		var arm_sw  = sin(_walk_cycle) * arm_swing_amount * intensity
		var leg_sw  = sin(_walk_cycle) * leg_swing_amount * intensity
		var opp_sw  = sin(_walk_cycle + PI) * leg_swing_amount * intensity
		left_arm.rotation.x  = opp_sw
		right_arm.rotation.x = arm_sw
		left_leg.rotation.x  = leg_sw
		right_leg.rotation.x = opp_sw
	else:
		left_arm.rotation.x  = lerp(left_arm.rotation.x,  0.0, delta * 5.0)
		right_arm.rotation.x = lerp(right_arm.rotation.x, 0.0, delta * 5.0)
		left_leg.rotation.x  = lerp(left_leg.rotation.x,  0.0, delta * 5.0)
		right_leg.rotation.x = lerp(right_leg.rotation.x, 0.0, delta * 5.0)


# ════════════════════════════════════════════════════════════════════
#  CHAT BUBBLE / TEXT DISPLAY
# ════════════════════════════════════════════════════════════════════

var _npc_label: Label = null
var _npc_label_layer: CanvasLayer = null
var _npc_manager_ref = null  # set by NpcManager for event broadcasting

# Remote talk animation (driven by action events on non-authority clients)
var _remote_talking := false
var _remote_talk_timer := 0.0
var _remote_talk_elapsed := 0.0

func show_chat_bubble(message: String):
	_broadcast_event("show_text", {"message": message})
	_show_label(message)


func hide_chat_bubble():
	_broadcast_event("hide_text", {})
	_label_active = false
	if _npc_label:
		_npc_label.visible = false


func _auto_hide_bubble(duration: float):
	await get_tree().create_timer(duration).timeout
	hide_chat_bubble()
	_chatting = false
	_chat_target = null


func start_chatting(player: Node3D):
	"""Pause AI, face the player, enter chatting state."""
	_chatting = true
	_chat_target = player


var _label_active := false  # true while text should be shown (set by show/hide)

func _update_label_screen_pos():
	if _npc_label == null or not _label_active:
		return
	var camera = get_viewport().get_camera_3d()
	if camera == null:
		return
	var head_world = global_position + Vector3(0, 0.6, 0)
	if camera.is_position_behind(head_world):
		_npc_label.visible = false
		return

	# Raycast from camera to NPC head — hide if occluded by geometry
	var space = get_world_3d().direct_space_state
	var from = camera.global_position
	var query = PhysicsRayQueryParameters3D.create(from, head_world)
	query.exclude = [get_rid()]
	var result = space.intersect_ray(query)
	if result and result.position.distance_to(from) < head_world.distance_to(from) - 0.1:
		_npc_label.visible = false
		return

	_npc_label.visible = true
	var screen_pos = camera.unproject_position(head_world)
	var viewport_size = get_viewport().get_visible_rect().size
	var label_x = screen_pos.x - _npc_label.size.x * 0.5
	# Clamp to screen edges
	label_x = clampf(label_x, 10.0, viewport_size.x - _npc_label.size.x - 10.0)
	var label_y = screen_pos.y - _npc_label.size.y - 10.0
	label_y = maxf(label_y, 10.0)
	_npc_label.position = Vector2(label_x, label_y)


# ════════════════════════════════════════════════════════════════════
#  ACTION EVENT BROADCASTING & RECEIVING
# ════════════════════════════════════════════════════════════════════

func _broadcast_event(event: String, data: Dictionary):
	"""Only broadcasts if this client is the authority."""
	if _is_authority and _npc_manager_ref and _npc_manager_ref.has_method("broadcast_npc_event"):
		_npc_manager_ref.broadcast_npc_event(npc_id, event, data)


func start_talk_animation(duration: float):
	"""Start arm-gesture talk animation (called locally or from remote event)."""
	_remote_talking = true
	_remote_talk_timer = duration
	_remote_talk_elapsed = 0.0
	_broadcast_event("talk_start", {"duration": duration})


func stop_talk_animation():
	_remote_talking = false
	_remote_talk_timer = 0.0
	_broadcast_event("talk_stop", {})


func handle_remote_event(event: String, data: Dictionary):
	"""Called by NpcManager on non-authority clients to replay action effects."""
	match event:
		"show_text":
			# Show text locally without re-broadcasting
			_show_label(data.get("message", ""))
		"hide_text":
			_label_active = false
			if _npc_label:
				_npc_label.visible = false
		"talk_start":
			_remote_talking = true
			_remote_talk_timer = float(data.get("duration", 3.0))
			_remote_talk_elapsed = 0.0
		"talk_stop":
			_remote_talking = false
		"audio_play":
			var apath: String = str(data.get("path", ""))
			var adur: float = float(data.get("duration", 3.0))
			_play_remote_audio(apath, adur)
		"audio_stop":
			var sp = get_node_or_null("SoundPlayer")
			if sp and sp is AudioStreamPlayer3D and sp.playing:
				sp.stop()


func _play_remote_audio(audio_path: String, duration: float):
	"""Play audio on non-authority client from action event."""
	if audio_path == "":
		return

	var sp = get_node_or_null("SoundPlayer")
	if sp == null or not (sp is AudioStreamPlayer3D):
		return

	# Check cache first, then bundled
	var cache_path = "user://npc_audio_cache/" + audio_path
	var local_path = "res://src/pedestrians/audio/" + audio_path

	if FileAccess.file_exists(cache_path):
		var stream = _load_cached_audio(cache_path)
		if stream:
			sp.stream = stream
			sp.play()
			print("[NPC %s] Remote audio from cache: %s" % [npc_id, audio_path])
			return
	elif ResourceLoader.exists(local_path):
		var stream = load(local_path)
		if stream:
			sp.stream = stream
			sp.play()
			print("[NPC %s] Remote audio from local: %s" % [npc_id, local_path])
			return

	# Not cached yet — request from server for next time
	if _npc_manager_ref and _npc_manager_ref.has_method("request_npc_audio"):
		_npc_manager_ref.request_npc_audio(audio_path)
	print("[NPC %s] Remote audio not cached, requested from server" % npc_id)


func play_audio_from_server(audio_path: String, offset: float, duration: float):
	"""Mid-join sync: play audio from a specific offset."""
	if audio_path == "":
		return
	var sp = get_node_or_null("SoundPlayer")
	if sp == null or not (sp is AudioStreamPlayer3D):
		return

	var cache_path = "user://npc_audio_cache/" + audio_path
	var local_path = "res://src/pedestrians/audio/" + audio_path
	var stream = null

	if FileAccess.file_exists(cache_path):
		stream = _load_cached_audio(cache_path)
	elif ResourceLoader.exists(local_path):
		stream = load(local_path)

	if stream:
		sp.stream = stream
		sp.play(offset)
		_remote_talking = true
		_remote_talk_timer = duration - offset
		_remote_talk_elapsed = offset
		print("[NPC %s] Mid-join audio at offset %.1fs: %s" % [npc_id, offset, audio_path])
	else:
		if _npc_manager_ref and _npc_manager_ref.has_method("request_npc_audio"):
			_npc_manager_ref.request_npc_audio(audio_path)


func _on_audio_cached(path: String):
	"""Called by NpcManager when a requested audio file arrives from server.
	   Play it immediately if an action is waiting for it."""
	print("[NPC %s] Audio cached: %s" % [npc_id, path])
	var cache_path = "user://npc_audio_cache/" + path

	# Authority: tell the pending PlayAudioAction to late-play
	var pending = get_meta("_pending_audio_action", null)
	if pending and pending.has_method("late_play"):
		pending.late_play(self, cache_path)
		return

	# Non-authority: play directly if we're in a talk animation
	if _remote_talking:
		var sp = get_node_or_null("SoundPlayer")
		if sp and sp is AudioStreamPlayer3D:
			var stream = _load_cached_audio(cache_path)
			if stream:
				sp.stream = stream
				sp.play()
				print("[NPC %s] Late-loaded remote audio: %s" % [npc_id, path])


func play_inline_audio(audio_b64: String):
	"""Play base64-encoded WAV audio directly (from TTS)."""
	var sp = get_node_or_null("SoundPlayer")
	if sp == null or not (sp is AudioStreamPlayer3D):
		start_talk_animation(3.0)
		return

	var raw = Marshalls.base64_to_raw(audio_b64)
	if raw.is_empty():
		start_talk_animation(3.0)
		return

	var stream = AudioStreamWAV.new()
	# Parse WAV header to get format info
	# Minimal WAV: bytes 22-23 = channels, 24-27 = sample rate, 34-35 = bits per sample
	if raw.size() < 44:
		start_talk_animation(3.0)
		return

	var channels = raw.decode_u16(22)
	var sample_rate = raw.decode_u32(24)
	var bits = raw.decode_u16(34)

	# Find "data" chunk
	var data_offset = 44  # standard WAV
	stream.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
	stream.mix_rate = sample_rate
	stream.stereo = channels == 2
	stream.data = raw.slice(data_offset)

	sp.stream = stream
	sp.play()

	var duration = float(stream.data.size()) / float(sample_rate * channels * (bits / 8))
	start_talk_animation(duration)
	print("[NPC %s] Playing TTS audio (%.1fs)" % [npc_id, duration])


func _load_cached_audio(path: String):
	"""Load audio from user:// cache path."""
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var data = file.get_buffer(file.get_length())
	file.close()
	if path.ends_with(".mp3"):
		var stream = AudioStreamMP3.new()
		stream.data = data
		return stream
	elif path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_buffer(data)
	return null


func _show_label(message: String):
	"""Internal: show label without broadcasting."""
	if _npc_label == null:
		_npc_label_layer = CanvasLayer.new()
		_npc_label_layer.layer = 100
		add_child(_npc_label_layer)

		_npc_label = Label.new()
		_npc_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_npc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_npc_label.custom_minimum_size = Vector2(400, 0)
		_npc_label.size = Vector2(400, 0)
		_npc_label.add_theme_font_size_override("font_size", 16)
		_npc_label.add_theme_color_override("font_color", Color.WHITE)
		_npc_label.add_theme_color_override("font_outline_color", Color.BLACK)
		_npc_label.add_theme_constant_override("outline_size", 6)
		_npc_label_layer.add_child(_npc_label)

	_npc_label.text = message
	_npc_label.visible = true
	_label_active = true


# ════════════════════════════════════════════════════════════════════
#  HELPERS
# ════════════════════════════════════════════════════════════════════

func _random_dir() -> Vector3:
	var angle = randf() * TAU
	return Vector3(cos(angle), 0.0, sin(angle))


# ════════════════════════════════════════════════════════════════════
#  PUBLIC API  (called by NpcManager)
# ════════════════════════════════════════════════════════════════════

func set_path_network(network) -> void:
	_path_network = network


func set_npc_manager(manager) -> void:
	_npc_manager_ref = manager


func set_authority(is_auth: bool):
	_is_authority = is_auth
	if is_auth:
		_spawn_position = position
		_active_schedule_idx = -1
		_schedule_check_timer = 0.0
		_route.clear()
		_route_idx = 0
		if schedule.is_empty():
			_enter_wandering()


func apply_remote_transform(pos: Vector3, model_rot_y: float):
	_prev_remote_pos = _remote_target_pos
	_remote_target_pos = pos
	_remote_model_rot_y = model_rot_y
	_remote_speed = _prev_remote_pos.distance_to(pos) / 0.1


func get_model_rotation_y() -> float:
	if character_model:
		return character_model.rotation.y
	return 0.0
