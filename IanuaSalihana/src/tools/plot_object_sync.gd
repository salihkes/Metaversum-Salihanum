extends Node

# Synchronizes plot object transforms with the server
# Monitors objects with the "is_plot_object" metadata

var network_controller: Node = null
var selection_manager: Node = null
var tracked_objects: Dictionary = {}  # net_id -> last_transform
var update_interval: float = 0.5
var update_timer: float = 0.0

func _ready():
	# Get network controller
	network_controller = get_node_or_null("/root/NetworkController")
	if not network_controller:
		network_controller = get_tree().root.find_child("NetworkController", true, false)
	
	# Get selection manager
	var workspace = get_tree().current_scene
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	if selection_manager:
		selection_manager.objects_selected.connect(_on_objects_selected)
		selection_manager.objects_deselected.connect(_on_objects_deselected)

func _process(delta):
	update_timer += delta
	if update_timer >= update_interval:
		update_timer = 0.0
		_check_plot_object_updates()

func _on_objects_selected(objects: Array):
	"""Track selected plot objects"""
	for obj in objects:
		if obj.has_meta("is_plot_object"):
			var net_id = obj.name
			tracked_objects[net_id] = obj.global_transform

func _on_objects_deselected():
	"""Send final update for all tracked objects"""
	for net_id in tracked_objects.keys():
		var obj = get_node_or_null("/root/" + get_tree().current_scene.name + "/" + net_id)
		if obj and is_instance_valid(obj):
			_send_plot_object_update(obj)
	
	tracked_objects.clear()

func _check_plot_object_updates():
	"""Check if any tracked plot objects have moved"""
	var objects_to_remove = []
	
	for net_id in tracked_objects.keys():
		var obj = get_node_or_null("/root/" + get_tree().current_scene.name + "/" + net_id)
		
		if not obj or not is_instance_valid(obj):
			objects_to_remove.append(net_id)
			continue
		
		var last_transform = tracked_objects[net_id]
		var current_transform = obj.global_transform
		
		# Check if transform changed significantly
		var pos_delta = current_transform.origin.distance_to(last_transform.origin)
		var rot_changed = not current_transform.basis.is_equal_approx(last_transform.basis)
		
		if pos_delta > 0.01 or rot_changed:
			_send_plot_object_update(obj)
			tracked_objects[net_id] = current_transform
	
	# Clean up removed objects
	for net_id in objects_to_remove:
		tracked_objects.erase(net_id)

func _send_plot_object_update(obj: Node3D):
	"""Send plot object update to server"""
	if not network_controller or not network_controller.has_method("send_json"):
		return
	
	if not obj.has_meta("is_plot_object"):
		return
	
	var net_id = obj.name
	var plot_id = obj.get_meta("plot_id", "")
	var xform = obj.global_transform
	
	var message = {
		"type": "update_plot_object",
		"net_id": net_id,
		"plot_id": plot_id,
		"transform": {
			"origin": {
				"x": xform.origin.x,
				"y": xform.origin.y,
				"z": xform.origin.z
			},
			"basis_x": {"x": xform.basis.x.x, "y": xform.basis.x.y, "z": xform.basis.x.z},
			"basis_y": {"x": xform.basis.y.x, "y": xform.basis.y.y, "z": xform.basis.y.z},
			"basis_z": {"x": xform.basis.z.x, "y": xform.basis.z.y, "z": xform.basis.z.z}
		}
	}
	
	network_controller.send_json(message)
	print("Sent plot object update: ", net_id)

