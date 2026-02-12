extends Node
class_name MapNetworkController
## Bridges ProvinceMap with the multiplayer network.
##
## Connects to ProvinceMap's data_changed / owners_changed signals and
## sends the serialised state to the server whenever a *local* change
## occurs.  Remote changes (received from the server) are applied to
## ProvinceMap with a guard flag so they are not echoed back.
##
## **Usage**: Add this node as a sibling (or child) of ProvinceMap in the
## scene tree and point `province_map_path` at the ProvinceMap node.
## It will automatically discover the NetworkController at runtime.

# ── Configuration ─────────────────────────────────────────────────────────

## Path to the ProvinceMap node (resolved in _ready).
@export var province_map_path: NodePath

## Debounce interval — rapid local edits are batched into a single
## network message within this window (seconds).
@export var debounce_interval: float = 0.15

# ── Internal state ────────────────────────────────────────────────────────

var _province_map: ProvinceMap
var _network_controller: Node           # NetworkController (has send_json)

## True while we are applying a remote update — prevents re-sending.
var _applying_remote: bool = false

## Debounce bookkeeping.
var _pending_send: bool = false
var _debounce_timer: float = 0.0

## True after we've received the initial state from the server.
var _initial_state_received: bool = false


# ══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	# Resolve the ProvinceMap reference.
	if not province_map_path.is_empty():
		_province_map = get_node_or_null(province_map_path)
	if not _province_map:
		_province_map = _find_child_of_type(get_parent(), "ProvinceMap")
	if not _province_map:
		_province_map = _find_child_of_type(get_tree().current_scene, "ProvinceMap")

	if _province_map:
		_province_map.data_changed.connect(_on_local_change)
		_province_map.owners_changed.connect(_on_local_change)
		print("MapNetworkController: Connected to ProvinceMap")
	else:
		push_warning("MapNetworkController: ProvinceMap not found — map sync disabled")

	# Discover the NetworkController (may not exist yet if we're in the
	# offline map-prototype project — that's fine, sync is just disabled).
	_network_controller = _find_network_controller()
	if _network_controller:
		print("MapNetworkController: NetworkController found — network sync enabled")
	else:
		print("MapNetworkController: NetworkController not found — running offline")


func _process(delta: float) -> void:
	if not _pending_send:
		return
	_debounce_timer += delta
	if _debounce_timer >= debounce_interval:
		_flush_state_to_server()


# ══════════════════════════════════════════════════════════════════════════════
#  LOCAL → SERVER  (outgoing)
# ══════════════════════════════════════════════════════════════════════════════

## Called by ProvinceMap signals when a local change happens.
func _on_local_change() -> void:
	if _applying_remote:
		return
	# Don't send until we've received the initial state — otherwise we'd
	# overwrite the server state with our empty/default map.
	if not _initial_state_received:
		return
	# Schedule a debounced send.
	_pending_send = true
	_debounce_timer = 0.0


## Actually serialize and send the full state.
func _flush_state_to_server() -> void:
	_pending_send = false
	_debounce_timer = 0.0

	if not _province_map or not _network_controller:
		return

	var state := _province_map.serialize_state()
	_network_controller.send_json({
		"type": "map_full_update",
		"state": state,
	})


# ══════════════════════════════════════════════════════════════════════════════
#  SERVER → LOCAL  (incoming)
# ══════════════════════════════════════════════════════════════════════════════

## Apply a full state snapshot received from the server.
## Called by NetworkController when it receives "map_state" or
## "map_full_update" messages.
func apply_remote_state(state: Dictionary) -> void:
	if not _province_map:
		push_warning("MapNetworkController: Can't apply remote state — no ProvinceMap")
		return

	_applying_remote = true
	_province_map.apply_state(state)
	_applying_remote = false
	_initial_state_received = true

	# Cancel any pending local send — the remote state is now authoritative.
	_pending_send = false
	_debounce_timer = 0.0
	print("MapNetworkController: Applied remote map state")


## Request the server to re-send the current map state.
func request_state_from_server() -> void:
	if not _network_controller:
		return
	_network_controller.send_json({
		"type": "map_request_state",
	})


# ══════════════════════════════════════════════════════════════════════════════
#  PLAYER OWNER IDENTITY  (incoming: map_player_owner)
# ══════════════════════════════════════════════════════════════════════════════

## Called by NetworkController when the server assigns the player's map owner.
func handle_player_owner(data: Dictionary) -> void:
	var owner_id: String = data.get("owner_id", "")
	var color: String = data.get("color", "")
	print("MapNetworkController: Received player owner — %s (#%s)" % [owner_id, color])

	# Register the owner in ProvinceMap so set_province_owner/occupier won't
	# silently bail because the owner_id is unknown.
	if _province_map and not color.is_empty():
		var c := Color(color)
		_province_map.register_owner(owner_id, owner_id, c)
		print("MapNetworkController: Registered owner in ProvinceMap")

	# Forward to the main.gd gameplay script
	var main_node := _find_main_gd()
	if main_node and main_node.has_method("set_player_owner"):
		main_node.set_player_owner(owner_id, color)


## Called by NetworkController when the server sends the online-owners list.
func handle_online_owners(data: Dictionary) -> void:
	var online_ids: Array = data.get("online_owner_ids", [])
	var require_online: bool = data.get("require_online", true)
	var main_node := _find_main_gd()
	if main_node and main_node.has_method("set_online_owners"):
		main_node.set_online_owners(online_ids, require_online)


# ══════════════════════════════════════════════════════════════════════════════
#  TREATY  (incoming & outgoing)
# ══════════════════════════════════════════════════════════════════════════════

## Called by NetworkController — an incoming treaty proposal from another player.
func handle_treaty_incoming(data: Dictionary) -> void:
	var treaty_id: String = data.get("treaty_id", "")
	var proposer: String = data.get("proposer", "")
	var expires_in: float = float(data.get("expires_in", 30))
	print("MapNetworkController: Incoming treaty %s from %s" % [treaty_id, proposer])
	var main_node := _find_main_gd()
	if main_node and main_node.has_method("show_treaty_incoming"):
		main_node.show_treaty_incoming(treaty_id, proposer, expires_in)


## Called by NetworkController — a pending treaty confirmation to the proposer.
func handle_treaty_pending(data: Dictionary) -> void:
	var treaty_id: String = data.get("treaty_id", "")
	var target: String = data.get("target", "")
	print("MapNetworkController: Treaty %s pending (target: %s)" % [treaty_id, target])
	# Optionally update UI — the proposer already knows they proposed.


## Called by NetworkController — a treaty has been resolved (accepted or rejected).
func handle_treaty_resolved(data: Dictionary) -> void:
	var accepted: bool = data.get("accepted", false)
	var proposer: String = data.get("proposer", "")
	var target: String = data.get("target", "")
	print("MapNetworkController: Treaty resolved — accepted=%s (%s <-> %s)" %
		  [str(accepted), proposer, target])
	var main_node := _find_main_gd()
	if main_node and main_node.has_method("show_treaty_resolved"):
		main_node.show_treaty_resolved(accepted, proposer, target)


## Send a treaty proposal to a target player.
func send_treaty_propose(target_username: String) -> void:
	if not _network_controller:
		return
	_network_controller.send_json({
		"type": "treaty_propose",
		"target": target_username,
	})


## Respond to an incoming treaty (accept or reject).
func send_treaty_respond(treaty_id: String, accept: bool) -> void:
	if not _network_controller:
		return
	_network_controller.send_json({
		"type": "treaty_respond",
		"treaty_id": treaty_id,
		"accept": accept,
	})


# ══════════════════════════════════════════════════════════════════════════════
#  HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _find_main_gd() -> Node:
	# main.gd is attached to the parent (Main node in map_3d.tscn)
	var p := get_parent()
	if p and p.has_method("set_player_owner"):
		return p
	return null

func _find_network_controller() -> Node:
	# 1. Check workspace siblings
	var workspace := get_tree().get_root().find_child("workspace", true, false)
	if workspace:
		var nc := workspace.find_child("NetworkController", true, false)
		if nc and nc.has_method("send_json"):
			return nc
	# 2. Autoload
	var nc := get_node_or_null("/root/NetworkController")
	if nc and nc.has_method("send_json"):
		return nc
	return null


func _find_child_of_type(node: Node, type_name: String) -> ProvinceMap:
	if node == null:
		return null
	if node.get_class() == type_name or (node is ProvinceMap):
		return node as ProvinceMap
	for child in node.get_children():
		var found := _find_child_of_type(child, type_name)
		if found:
			return found
	return null
