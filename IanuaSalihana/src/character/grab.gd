extends RefCounted
class_name GrabModule

# General grab module that supports both desktop and VR modes.
# Objects must be in group "grabbable" (recommended) or be a RigidBody3D to be eligible.

# References
var character: CharacterBody3D
var character_model: Node3D
var xr_origin: XROrigin3D
var xr_camera: XRCamera3D

# VR controllers
var left_controller: Node3D
var right_controller: Node3D

# Hold points
var left_hold_point: Node3D
var right_hold_point: Node3D
var camera_hold_point: Node3D

# State
var is_vr_active := false

var held_left: Node3D = null
var held_right: Node3D = null
var held_normal: Node3D = null

# Throw velocity tracking
var _prev_left_positions: Array = []
var _prev_right_positions: Array = []
var _prev_camera_positions: Array = []
var _max_history := 6

# Tuning
var max_camera_grab_distance := 3.0
var max_hand_grab_distance := 0.4
var desktop_hold_distance := 1.2
var desktop_rotation_offset := Basis()

# Networking update throttling while holding
var net_update_interval := 0.1
var _net_update_timer := 0.0
var _last_sent_xf := {}

func setup(char: CharacterBody3D, model: Node3D) -> void:
	character = char
	character_model = model
	xr_origin = character.find_child("XROrigin3D")
	xr_camera = xr_origin.find_child("XRCamera3D") if xr_origin else null
	
	_ensure_hold_points()
	_connect_vr_controllers()

func set_vr_active(active: bool) -> void:
	is_vr_active = active

func update(delta: float) -> void:
	# Update history for throw velocity
	_record_points_history()
	
	if not is_vr_active:
		_update_desktop_grab()
		# While holding in desktop mode, keep the object aligned to the active camera rotation
		# and positioned in front of the PLAYER (character), not at the camera origin
		if held_normal:
			held_normal.global_transform = _compute_desktop_hold_transform()

	# Periodically send network updates while holding
	_net_update_timer += delta
	if _net_update_timer >= net_update_interval:
		_net_update_timer = 0.0
		_send_inflight_updates()

func _ensure_hold_points() -> void:
	# VR hold points under controllers
	if xr_origin:
		left_controller = xr_origin.find_child("LeftHand")
		right_controller = xr_origin.find_child("RightHand")
		
		if left_controller:
			left_hold_point = left_controller.get_node_or_null("HoldPoint")
			if left_hold_point == null:
				left_hold_point = Node3D.new()
				left_hold_point.name = "HoldPoint"
				left_controller.add_child(left_hold_point)
				left_hold_point.transform = Transform3D.IDENTITY
		if right_controller:
			right_hold_point = right_controller.get_node_or_null("HoldPoint")
			if right_hold_point == null:
				right_hold_point = Node3D.new()
				right_hold_point.name = "HoldPoint"
				right_controller.add_child(right_hold_point)
				right_hold_point.transform = Transform3D.IDENTITY
	
	# Desktop hold point in front of camera (or character model fallback)
	var desktop_parent: Node3D = null
	if xr_camera:
		desktop_parent = xr_camera
	else:
		var cam_origin = character.find_child("CamOrigin")
		desktop_parent = cam_origin if cam_origin else character_model
	
	if desktop_parent:
		camera_hold_point = desktop_parent.get_node_or_null("HoldPoint")
		if camera_hold_point == null:
			camera_hold_point = Node3D.new()
			camera_hold_point.name = "HoldPoint"
			desktop_parent.add_child(camera_hold_point)
		# Place a bit in front
		camera_hold_point.transform = Transform3D(Basis(), Vector3(0, 0, -1.2))

func _connect_vr_controllers() -> void:
	if not xr_origin:
		return
	
	left_controller = xr_origin.find_child("LeftHand")
	right_controller = xr_origin.find_child("RightHand")
	
	if left_controller:
		if not left_controller.button_pressed.is_connected(_on_left_button_pressed):
			left_controller.button_pressed.connect(_on_left_button_pressed)
		if not left_controller.button_released.is_connected(_on_left_button_released):
			left_controller.button_released.connect(_on_left_button_released)
	if right_controller:
		if not right_controller.button_pressed.is_connected(_on_right_button_pressed):
			right_controller.button_pressed.connect(_on_right_button_pressed)
		if not right_controller.button_released.is_connected(_on_right_button_released):
			right_controller.button_released.connect(_on_right_button_released)

func _update_desktop_grab() -> void:
	var grab_pressed := false
	var grab_released := false
	
	if InputMap.has_action("grab"):
		grab_pressed = Input.is_action_just_pressed("grab")
		grab_released = Input.is_action_just_released("grab")
	else:
		# Fallbacks (keyboard/controller): use standard select/accept actions
		grab_pressed = Input.is_action_just_pressed("ui_select") or Input.is_action_just_pressed("ui_accept")
		grab_released = Input.is_action_just_released("ui_select") or Input.is_action_just_released("ui_accept")
	
	if grab_pressed:
		if held_normal:
			var v = _estimate_velocity(_prev_camera_positions)
			_release_object(held_normal, camera_hold_point, v)
			_notify_network_release(held_normal, v)
			held_normal = null
		else:
			var target = _ray_pick_from_camera()
			if target:
				_grab_object(target, camera_hold_point)
				_notify_network_grab(target)
				held_normal = target
	elif grab_released and held_normal:
		var v2 = _estimate_velocity(_prev_camera_positions)
		_release_object(held_normal, camera_hold_point, v2)
		_notify_network_release(held_normal, v2)
		held_normal = null

func _on_left_button_pressed(name: String) -> void:
	if name == "grip_click" or name == "trigger_click":
		if held_left:
			var v = _estimate_velocity(_prev_left_positions)
			_release_object(held_left, left_hold_point, v)
			_notify_network_release(held_left, v)
			held_left = null
		else:
			var target = _ray_pick_from_hand(left_controller)
			if target:
				_grab_object(target, left_hold_point)
				_notify_network_grab(target)
				held_left = target

func _on_left_button_released(name: String) -> void:
	# Optional: only release on release event when using hold-to-grab style
	pass

func _on_right_button_pressed(name: String) -> void:
	if name == "grip_click" or name == "trigger_click":
		if held_right:
			var v = _estimate_velocity(_prev_right_positions)
			_release_object(held_right, right_hold_point, v)
			_notify_network_release(held_right, v)
			held_right = null
		else:
			var target = _ray_pick_from_hand(right_controller)
			if target:
				_grab_object(target, right_hold_point)
				_notify_network_grab(target)
				held_right = target

func _on_right_button_released(name: String) -> void:
	# Optional: only release on release event when using hold-to-grab style
	pass

func _ray_pick_from_camera() -> Node3D:
	var camera := character.get_viewport().get_camera_3d()
	if camera == null:
		camera = xr_camera
	if camera == null:
		return null
	
	var from = camera.global_transform.origin
	var to = from + (-camera.global_transform.basis.z) * max_camera_grab_distance
	return _ray_pick(from, to)

func _ray_pick_from_hand(hand_node: Node3D) -> Node3D:
	if hand_node == null:
		return null
	var from = hand_node.global_transform.origin
	var to = from + (-hand_node.global_transform.basis.z) * max_hand_grab_distance
	return _ray_pick(from, to)

func _ray_pick(from: Vector3, to: Vector3) -> Node3D:
	var space_state = character.get_world_3d().direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.exclude = [character]
	var result = space_state.intersect_ray(query)
	if result.is_empty():
		return null
	var collider = result.get("collider")
	return _resolve_grabbable(collider)

func _resolve_grabbable(node: Object) -> Node3D:
	var cur = node as Node
	while cur and cur is Node3D:
		if cur.is_in_group("grabbable"):
			return cur
		if cur is RigidBody3D:
			# Allow any rigid body if not explicitly grouped
			return cur
		cur = cur.get_parent()
	return null

func _grab_object(obj: Node3D, hold_point: Node3D) -> void:
	if obj == null or hold_point == null:
		return
	
	# Store previous parent to restore on release
	obj.set_meta("grab_prev_parent_path", obj.get_parent().get_path())
	obj.set_meta("grab_prev_global_transform", obj.global_transform)
	
	var rb := obj as RigidBody3D
	if rb:
		obj.set_meta("grab_prev_freeze", rb.freeze)
		rb.freeze = true
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
	
	# Reparent under hold point (VR) or position-only (desktop)
	if hold_point == camera_hold_point:
		# Desktop: do not reparent, drive by world transform using camera-facing basis
		obj.global_transform = _compute_desktop_hold_transform()
	else:
		if obj.get_parent() != hold_point:
			obj.reparent(hold_point, false)
		# Snap to hold point
		obj.transform = Transform3D.IDENTITY

func _compute_desktop_hold_transform() -> Transform3D:
	# Use the active viewport camera orientation so the object rotates with the camera.
	var vc: Camera3D = character.get_viewport().get_camera_3d()
	var basis := Basis()
	var forward := Vector3.FORWARD
	if vc:
		basis = vc.global_transform.basis
		forward = -basis.z
	else:
		basis = character.global_transform.basis
		forward = -basis.z
	# Position: in front of the PLAYER (character) along camera forward
	var origin = character.global_transform.origin + forward.normalized() * desktop_hold_distance
	# Apply optional rotation offset if needed by content
	basis = basis * desktop_rotation_offset
	return Transform3D(basis, origin)

func _release_object(obj: Node3D, hold_point: Node3D, throw_velocity: Vector3) -> void:
	if obj == null:
		return
	
	var prev_parent_path = obj.get_meta("grab_prev_parent_path")
	var prev_parent = character.get_node_or_null(prev_parent_path) if prev_parent_path else null
	
	if prev_parent and prev_parent is Node:
		# Keep world position when reparenting back
		if obj.get_parent() != prev_parent:
			obj.reparent(prev_parent, true)
	else:
		# Fallback: detach to character's parent
		var fallback_parent = character.get_parent()
		if fallback_parent and obj.get_parent() != fallback_parent:
			obj.reparent(fallback_parent, true)
	
	var rb := obj as RigidBody3D
	if rb:
		var was_frozen = obj.get_meta("grab_prev_freeze")
		rb.freeze = was_frozen if was_frozen != null else false
		# Apply simple throw impulse based on estimated velocity
		if throw_velocity.length() > 0.01:
			rb.linear_velocity = throw_velocity
	
	# Cleanup metadata
	obj.set_meta("grab_prev_parent_path", null)
	obj.set_meta("grab_prev_global_transform", null)
	obj.set_meta("grab_prev_freeze", null)
	# Cleanup last-sent cache
	var key = obj.get_instance_id()
	if _last_sent_xf.has(key):
		_last_sent_xf.erase(key)

func _record_points_history() -> void:
	if left_hold_point:
		_prev_left_positions.append(left_hold_point.global_transform.origin)
		if _prev_left_positions.size() > _max_history:
			_prev_left_positions.pop_front()
	if right_hold_point:
		_prev_right_positions.append(right_hold_point.global_transform.origin)
		if _prev_right_positions.size() > _max_history:
			_prev_right_positions.pop_front()
	if not is_vr_active:
		_prev_camera_positions.append(_compute_desktop_hold_transform().origin)
	elif camera_hold_point:
		_prev_camera_positions.append(camera_hold_point.global_transform.origin)
		if _prev_camera_positions.size() > _max_history:
			_prev_camera_positions.pop_front()

func _estimate_velocity(history: Array) -> Vector3:
	if history.size() < 2:
		return Vector3.ZERO
	# Rough estimate assuming fixed physics timestep; scale for a modest throw
	var p0: Vector3 = history[max(0, history.size() - 3)]
	var p1: Vector3 = history[history.size() - 1]
	var displacement = p1 - p0
	# Assume ~2 frames apart; scale factor to feel right
	return displacement * 30.0

func _notify_network_grab(obj: Node3D) -> void:
	if not character:
		return
	var tree = character.get_tree()
	if tree == null:
		return
	var root = tree.root
	var nc = root.find_child("network_controller", true, false)
	if not nc:
		nc = root.find_child("NetworkController", true, false)
	if nc and nc.has_method("notify_object_grabbed"):
		nc.notify_object_grabbed(obj)

func _notify_network_release(obj: Node3D, throw_velocity: Vector3) -> void:
	if not character:
		return
	var tree = character.get_tree()
	if tree == null:
		return
	var root = tree.root
	var nc = root.find_child("network_controller", true, false)
	if not nc:
		nc = root.find_child("NetworkController", true, false)
	if nc:
		if nc.has_method("notify_object_released_with_path"):
			# Prefer path-aware API if present
			nc.notify_object_released_with_path(obj.get_path(), obj.global_transform, throw_velocity)
		elif nc.has_method("notify_object_released"):
			nc.notify_object_released(obj, throw_velocity)

func _notify_network_update(obj: Node3D, xf: Transform3D) -> void:
	if not character:
		return
	var tree = character.get_tree()
	if tree == null:
		return
	var root = tree.root
	var nc = root.find_child("network_controller", true, false)
	if not nc:
		nc = root.find_child("NetworkController", true, false)
	if nc:
		if nc.has_method("notify_object_update_with_path"):
			nc.notify_object_update_with_path(obj.get_path(), xf)
		elif nc.has_method("notify_object_update"):
			nc.notify_object_update(obj)

func _send_inflight_updates() -> void:
	# Send updates for any held object if transform changed sufficiently
	var objs := []
	if held_normal:
		objs.append(held_normal)
	if held_left:
		objs.append(held_left)
	if held_right:
		objs.append(held_right)
	for obj in objs:
		if not obj:
			continue
		var key = obj.get_instance_id()
		var xf: Transform3D = obj.global_transform
		var should_send := true
		if _last_sent_xf.has(key):
			var prev: Transform3D = _last_sent_xf[key]
			var pos_delta = xf.origin.distance_to(prev.origin)
			# Quick rotation delta via forward vector dot product
			var dot_fwd = xf.basis.z.dot(prev.basis.z)
			var rot_changed = dot_fwd < 0.999
			should_send = pos_delta > 0.02 or rot_changed
		if should_send:
			_notify_network_update(obj, xf)
			_last_sent_xf[key] = xf
