extends Node3D
## Gameplay controller for the province map.
## Handles 3D raycasting for hover/click and routes click actions through the
## player's assigned owner identity.  Editor UI has been disabled.
##
## Integrated into the Metaversum-Salihanum workspace — uses the viewport's
## active camera (provided by whichever character is spawned).

@onready var province_map: ProvinceMap = $ProvinceMap

# ── Top bar (kept for info display) ──
@onready var info_label: Label = %InfoLabel
@onready var modified_label: Label = %ModifiedLabel

# ── Treaty popup ──
@onready var treaty_popup: PanelContainer = %TreatyPopup
@onready var treaty_info: Label = %TreatyInfo
@onready var treaty_countdown: Label = %TreatyCountdown
@onready var accept_button: Button = %AcceptButton
@onready var reject_button: Button = %RejectButton

# ── State ──
var _my_owner_id: String = ""
var _my_color: String = ""

# Incoming treaty waiting for response
var _incoming_treaty_id: String = ""
var _incoming_treaty_proposer: String = ""
var _incoming_treaty_expires: float = 0.0  # OS time when it expires

# Online protection — when enabled, you can't occupy offline players' land
var _online_owner_ids: Array = []
var _require_online_to_occupy: bool = true


# ══════════════════════════════════════════════════════════════════════════════
#  READY
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	province_map.province_hovered.connect(_on_hovered)
	province_map.owners_changed.connect(_on_owners_changed)
	province_map.data_changed.connect(_refresh_counts)

	# Treaty popup buttons
	accept_button.pressed.connect(_on_treaty_accept)
	reject_button.pressed.connect(_on_treaty_reject)

	treaty_popup.visible = false
	_refresh_counts()


# ══════════════════════════════════════════════════════════════════════════════
#  3D RAYCASTING
# ══════════════════════════════════════════════════════════════════════════════

func _process(delta: float) -> void:
	if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		return
	# Continuous hover tracking via raycast
	var pid := _raycast_province()
	province_map.set_hovered_province(pid)

	# Update treaty countdown timer
	if treaty_popup.visible and _incoming_treaty_expires > 0.0:
		var remaining := _incoming_treaty_expires - Time.get_unix_time_from_system()
		if remaining <= 0.0:
			_close_treaty_popup()
		else:
			treaty_countdown.text = "Expires in %ds" % ceili(remaining)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			var pid := _raycast_province()
			if pid >= 0:
				if mb.shift_pressed:
					_on_shift_clicked(pid)
				else:
					_on_clicked(pid)


func _raycast_province() -> int:
	var cam := get_viewport().get_camera_3d()
	if not cam:
		return -1
	var mouse_pos := get_viewport().get_mouse_position()
	var ray_origin := cam.project_ray_origin(mouse_pos)
	var ray_dir := cam.project_ray_normal(mouse_pos)

	var space := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(
		ray_origin,
		ray_origin + ray_dir * 500.0
	)
	var local_player := _find_local_player()
	if local_player:
		query.exclude = [local_player.get_rid()]
	var result := space.intersect_ray(query)
	if result.is_empty():
		return -1

	var hit_point: Vector3 = result["position"]
	var uv := _hit_to_uv(hit_point)
	return province_map.get_province_at_uv(uv)


func _find_local_player() -> Node3D:
	var workspace := get_tree().get_root().find_child("workspace", true, false)
	if not workspace:
		return null
	for child in workspace.get_children():
		if child is CharacterBody3D and child.get_node_or_null("LocalPlayer"):
			return child
	return null


func _hit_to_uv(hit_point: Vector3) -> Vector2:
	var local := province_map.to_local(hit_point)
	return Vector2(
		local.x / province_map.plane_size.x + 0.5,
		local.z / province_map.plane_size.y + 0.5,
	)


# ══════════════════════════════════════════════════════════════════════════════
#  HOVER / CLICK
# ══════════════════════════════════════════════════════════════════════════════

func _on_hovered(pid: int) -> void:
	if pid >= 0:
		var parts: Array[String] = [province_map.get_province_name(pid)]
		var oid := province_map.get_province_owner(pid)
		if not oid.is_empty():
			var o := province_map.get_owner_data(oid)
			parts.append("(%s)" % o.get("name", oid))
		var occ := province_map.get_province_occupier(pid)
		if not occ.is_empty():
			var oc := province_map.get_owner_data(occ)
			parts.append("[OCC: %s]" % oc.get("name", occ))
		# Contextual hint
		if not _my_owner_id.is_empty():
			if oid == _my_owner_id and not occ.is_empty():
				parts.append("  | Click: defend  |  Shift+Click: propose peace")
			elif occ == _my_owner_id:
				parts.append("  | Shift+Click: propose peace")
			elif oid == _my_owner_id and occ.is_empty():
				parts.append("  | Click: unclaim")
			elif oid.is_empty():
				parts.append("  | Click: claim")
			elif oid != _my_owner_id:
				if _require_online_to_occupy and oid not in _online_owner_ids:
					parts.append("  | OFFLINE — protected")
				else:
					parts.append("  | Click: occupy")
		info_label.text = "  ".join(parts)
	else:
		info_label.text = ""


func _on_clicked(pid: int) -> void:
	if _my_owner_id.is_empty():
		info_label.text = "Not logged in — waiting for server to assign your identity."
		return

	var current_owner := province_map.get_province_owner(pid)
	var current_occ := province_map.get_province_occupier(pid)

	if current_owner.is_empty():
		# Unowned — claim it
		province_map.set_province_owner(pid, _my_owner_id)
		info_label.text = "Claimed province %d" % pid

	elif current_owner == _my_owner_id:
		if not current_occ.is_empty():
			# Your province is occupied — kick the occupier out (defend!)
			province_map.clear_province_occupier(pid)
			var oc := province_map.get_owner_data(current_occ)
			info_label.text = "Defended! Removed %s from your province %d" % [oc.get("name", current_occ), pid]
		else:
			# Your own unoccupied province — unclaim it
			province_map.clear_province_owner(pid)
			info_label.text = "Unclaimed province %d" % pid

	elif current_occ == _my_owner_id:
		# You're already occupying it — no-op
		var o := province_map.get_owner_data(current_owner)
		info_label.text = "Already occupying %s's province. Right-click to propose peace." % o.get("name", current_owner)

	else:
		# Owned by someone else (not you) — occupy it
		if _require_online_to_occupy and current_owner not in _online_owner_ids:
			var o := province_map.get_owner_data(current_owner)
			info_label.text = "%s is offline — cannot occupy their land." % o.get("name", current_owner)
		else:
			province_map.set_province_occupier(pid, _my_owner_id)
			var o := province_map.get_owner_data(current_owner)
			info_label.text = "Occupying %s's province %d" % [o.get("name", current_owner), pid]

	_refresh_counts()


## Shift+Click: propose a peace treaty with the other player involved in this
## province's occupation (either you occupy theirs or they occupy yours).
func _on_shift_clicked(pid: int) -> void:
	if _my_owner_id.is_empty():
		return

	var current_owner := province_map.get_province_owner(pid)
	var current_occ := province_map.get_province_occupier(pid)
	var other_owner_id: String = ""

	if current_owner == _my_owner_id and not current_occ.is_empty():
		# Someone occupies your province — propose peace with them
		other_owner_id = current_occ
	elif current_occ == _my_owner_id and not current_owner.is_empty():
		# You occupy their province — propose peace with the owner
		other_owner_id = current_owner
	elif not current_owner.is_empty() and current_owner != _my_owner_id:
		# Not directly involved but you can still try
		other_owner_id = current_owner

	if other_owner_id.is_empty():
		info_label.text = "No one to propose peace with here."
		return

	# Derive the username from the owner_id ("owner_Tester" → "Tester")
	var target_username := other_owner_id
	if target_username.begins_with("owner_"):
		target_username = target_username.substr(6)

	propose_peace(target_username)


# ══════════════════════════════════════════════════════════════════════════════
#  OWNERS CHANGED
# ══════════════════════════════════════════════════════════════════════════════

func _on_owners_changed() -> void:
	_refresh_counts()


# ══════════════════════════════════════════════════════════════════════════════
#  MAP PLAYER IDENTITY  (called by MapNetworkController)
# ══════════════════════════════════════════════════════════════════════════════

func set_player_owner(owner_id: String, color: String) -> void:
	_my_owner_id = owner_id
	_my_color = color
	info_label.text = "You are %s  (colour #%s)" % [owner_id, color]
	print("[Map] My owner_id = %s, color = #%s" % [owner_id, color])


## Update the list of currently online map owners and the protection setting.
func set_online_owners(online_ids: Array, require_online: bool) -> void:
	_online_owner_ids = online_ids
	_require_online_to_occupy = require_online


# ══════════════════════════════════════════════════════════════════════════════
#  TREATY UI
# ══════════════════════════════════════════════════════════════════════════════

## Show an incoming treaty proposal popup.
func show_treaty_incoming(treaty_id: String, proposer: String, expires_in: float) -> void:
	_incoming_treaty_id = treaty_id
	_incoming_treaty_proposer = proposer
	_incoming_treaty_expires = Time.get_unix_time_from_system() + expires_in
	treaty_info.text = "%s proposes a peace treaty." % proposer
	treaty_countdown.text = "Expires in %ds" % int(expires_in)
	treaty_popup.visible = true


## Called when the server resolves a treaty (either accepted or rejected/expired).
func show_treaty_resolved(accepted: bool, proposer: String, target: String) -> void:
	_close_treaty_popup()
	if accepted:
		info_label.text = "Peace treaty ACCEPTED between %s and %s" % [proposer, target]
	else:
		info_label.text = "Peace treaty REJECTED between %s and %s" % [proposer, target]


func _on_treaty_accept() -> void:
	if _incoming_treaty_id.is_empty():
		return
	var mnc := _find_map_network_controller()
	if mnc:
		mnc.send_treaty_respond(_incoming_treaty_id, true)
	_close_treaty_popup()


func _on_treaty_reject() -> void:
	if _incoming_treaty_id.is_empty():
		return
	var mnc := _find_map_network_controller()
	if mnc:
		mnc.send_treaty_respond(_incoming_treaty_id, false)
	_close_treaty_popup()


func _close_treaty_popup() -> void:
	treaty_popup.visible = false
	_incoming_treaty_id = ""
	_incoming_treaty_proposer = ""
	_incoming_treaty_expires = 0.0


func _find_map_network_controller() -> Node:
	return get_node_or_null("MapNetworkController")


# ══════════════════════════════════════════════════════════════════════════════
#  PROPOSE PEACE  (call from external code / chat command)
# ══════════════════════════════════════════════════════════════════════════════

## Propose a peace treaty to the given target username.
func propose_peace(target_username: String) -> void:
	var mnc := _find_map_network_controller()
	if mnc:
		mnc.send_treaty_propose(target_username)
		info_label.text = "Peace proposal sent to %s …" % target_username


# ══════════════════════════════════════════════════════════════════════════════
#  STATUS LABELS
# ══════════════════════════════════════════════════════════════════════════════

func _refresh_counts() -> void:
	var nm := province_map.get_modified_count()
	modified_label.text = "%d modified" % nm if nm > 0 else ""
