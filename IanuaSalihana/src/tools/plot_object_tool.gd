extends Control

# Plot Object Tool for placing objects in player plots
# Dynamically loads objects from res://src/assets/Objects/

signal object_placed(object_type: String, position: Vector3, transform: Transform3D)

@onready var object_list_container = $ScrollContainer/ObjectList
@onready var place_btn = $ButtonContainer/PlaceButton
@onready var cancel_btn = $ButtonContainer/CancelButton
@onready var scroll_container = $ScrollContainer

var camera: Camera3D = null
var preview_instance: Node3D = null
var is_placing: bool = false
var current_object_type: String = ""
var available_objects: Dictionary = {}  # object_name -> scene_path

# Grid snapping
var grid_size: float = 0.5

# References
var network_controller: Node = null
var selection_manager: Node = null

func _ready():
	# Connect button signals
	if place_btn:
		place_btn.pressed.connect(_on_place_pressed)
	if cancel_btn:
		cancel_btn.pressed.connect(_on_cancel_pressed)
	
	# Get camera reference
	await get_tree().process_frame
	camera = get_viewport().get_camera_3d()
	
	# Get network controller reference
	network_controller = get_node_or_null("/root/NetworkController")
	if not network_controller:
		network_controller = get_tree().root.find_child("NetworkController", true, false)
	
	# Get manager references
	var workspace = get_tree().current_scene
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	# Load available objects
	_load_available_objects()
	
	# Populate UI
	_populate_object_list()
	
	if place_btn:
		place_btn.disabled = true
	if cancel_btn:
		cancel_btn.disabled = true

func _load_available_objects():
	"""Scan the Objects directory and load all available objects"""
	var objects_path = "res://src/assets/Objects/"
	var dir = DirAccess.open(objects_path)
	
	if dir:
		dir.list_dir_begin()
		var folder_name = dir.get_next()
		
		while folder_name != "":
			if dir.current_is_dir() and not folder_name.begins_with("."):
				# Check if mesh.tscn exists in this folder (prioritize .tscn over .glb)
				var mesh_tscn_path = objects_path + folder_name + "/mesh.tscn"
				var mesh_glb_path = objects_path + folder_name + "/mesh.glb"
				
				if FileAccess.file_exists(mesh_tscn_path):
					available_objects[folder_name] = mesh_tscn_path
					print("Found object: ", folder_name, " at ", mesh_tscn_path)
				elif FileAccess.file_exists(mesh_glb_path):
					available_objects[folder_name] = mesh_glb_path
					print("Found object: ", folder_name, " at ", mesh_glb_path, " (fallback to .glb)")
			
			folder_name = dir.get_next()
		
		dir.list_dir_end()
		print("Loaded ", available_objects.size(), " objects")
	else:
		print("Failed to open Objects directory at: ", objects_path)

func _populate_object_list():
	"""Create viewport preview items for each available object"""
	if not object_list_container:
		return
	
	# Clear existing items
	for child in object_list_container.get_children():
		child.queue_free()
	
	# Create a preview item for each object
	for object_name in available_objects.keys():
		var preview_item = _create_preview_item(object_name)
		object_list_container.add_child(preview_item)

func _create_preview_item(object_name: String) -> Control:
	"""Create a viewport-based preview item for an object"""
	# Main container
	var container = PanelContainer.new()
	container.custom_minimum_size = Vector2(200, 220)
	
	# VBox for layout
	var vbox = VBoxContainer.new()
	container.add_child(vbox)
	
	# Viewport container for 3D preview
	var viewport_container = SubViewportContainer.new()
	viewport_container.custom_minimum_size = Vector2(200, 180)
	viewport_container.stretch = true
	vbox.add_child(viewport_container)
	
	# SubViewport for rendering - each object gets its own independent viewport
	var viewport = SubViewport.new()
	viewport.size = Vector2i(200, 180)
	viewport.transparent_bg = false
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.own_world_3d = true  # Each viewport gets its own world
	viewport_container.add_child(viewport)
	
	# Environment for the viewport
	var world_env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.2, 0.2, 0.25, 1.0)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.8, 0.8, 0.8, 1.0)
	world_env.environment = environment
	viewport.add_child(world_env)
	
	# Camera for the viewport
	var camera = Camera3D.new()
	camera.position = Vector3(0, 1, 3)
	camera.look_at(Vector3(0, 0.5, 0), Vector3.UP)
	viewport.add_child(camera)
	
	# Load and add the 3D object
	var mesh_path = available_objects.get(object_name, "")
	if mesh_path != "":
		var loaded_scene = load(mesh_path)
		if loaded_scene:
			var object_instance = loaded_scene.instantiate()
			object_instance.name = object_name + "_preview"  # Unique name
			viewport.add_child(object_instance)
			
			# Center and scale the object
			call_deferred("_adjust_object_in_viewport", object_instance, camera)
			
			# Add rotation animation
			var rotation_timer = Timer.new()
			rotation_timer.wait_time = 0.016  # ~60 FPS
			rotation_timer.autostart = true
			rotation_timer.timeout.connect(func(): 
				if is_instance_valid(object_instance):
					object_instance.rotate_y(0.01)
			)
			viewport.add_child(rotation_timer)
	
	# Button overlay for selection
	var button = Button.new()
	button.custom_minimum_size = Vector2(200, 40)
	button.text = object_name
	button.pressed.connect(_on_object_selected.bind(object_name, container))
	vbox.add_child(button)
	
	return container

func _adjust_object_in_viewport(object_instance: Node3D, camera: Camera3D):
	"""Center and scale object to fit nicely in viewport"""
	await get_tree().process_frame
	await get_tree().process_frame  # Wait extra frame for transforms to settle
	
	# Calculate bounding box considering transforms
	var aabb = _get_world_aabb(object_instance, Transform3D.IDENTITY)
	
	if aabb.size.length() > 0:
		# Get the center in world space
		var center = aabb.get_center()
		
		# Move object so its center is at origin
		object_instance.global_position = object_instance.global_position - center
		
		# Adjust camera distance based on object size
		var max_size = max(aabb.size.x, max(aabb.size.y, aabb.size.z))
		var distance = max_size * 1.4  # Adjust multiplier as needed
		camera.position = Vector3(distance * 0.7, max_size * 0.4, distance)
		camera.look_at(Vector3(0, 0, 0), Vector3.UP)
	else:
		# Fallback if no mesh found
		camera.position = Vector3(2, 1, 3)
		camera.look_at(Vector3(0, 0, 0), Vector3.UP)

func _get_world_aabb(node: Node3D, parent_transform: Transform3D) -> AABB:
	"""Get combined AABB for all meshes in node tree, considering transforms"""
	var combined_aabb = AABB()
	var first = true
	
	# Current node's world transform
	var current_transform = parent_transform * node.transform
	
	# If this node is a MeshInstance3D, get its AABB
	if node is MeshInstance3D and node.mesh:
		var mesh_aabb = node.mesh.get_aabb()
		
		# Transform all 8 corners of the AABB
		var corners = [
			mesh_aabb.position,
			mesh_aabb.position + Vector3(mesh_aabb.size.x, 0, 0),
			mesh_aabb.position + Vector3(0, mesh_aabb.size.y, 0),
			mesh_aabb.position + Vector3(0, 0, mesh_aabb.size.z),
			mesh_aabb.position + Vector3(mesh_aabb.size.x, mesh_aabb.size.y, 0),
			mesh_aabb.position + Vector3(mesh_aabb.size.x, 0, mesh_aabb.size.z),
			mesh_aabb.position + Vector3(0, mesh_aabb.size.y, mesh_aabb.size.z),
			mesh_aabb.position + mesh_aabb.size
		]
		
		# Transform corners and create new AABB
		for corner in corners:
			var world_corner = current_transform * corner
			if first:
				combined_aabb = AABB(world_corner, Vector3.ZERO)
				first = false
			else:
				combined_aabb = combined_aabb.expand(world_corner)
	
	# Recursively process children
	for child in node.get_children():
		if child is Node3D:
			var child_aabb = _get_world_aabb(child, current_transform)
			if child_aabb.size.length() > 0:
				if first:
					combined_aabb = child_aabb
					first = false
				else:
					combined_aabb = combined_aabb.merge(child_aabb)
	
	return combined_aabb

func _on_object_selected(object_name: String, selected_container: Control):
	"""Handle object selection from the list"""
	current_object_type = object_name
	print("Selected object: ", object_name)
	print("Place button exists: ", place_btn != null)
	
	# Enable place button
	if place_btn:
		place_btn.disabled = false
		print("Place button enabled")
	else:
		print("ERROR: Place button not found!")
	
	# Highlight selected item
	for item in object_list_container.get_children():
		if item is PanelContainer:
			# Create or update highlight
			if item == selected_container:
				item.modulate = Color(1.5, 1.5, 1.0, 1.0)  # Bright yellow tint
			else:
				item.modulate = Color.WHITE

func _on_place_pressed():
	"""Start placement mode"""
	print("Place button pressed! is_placing: ", is_placing, " current_object_type: ", current_object_type)
	if not is_placing and current_object_type != "":
		start_placing_mode()
	else:
		finish_placing_mode()
	
	if place_btn:
		place_btn.release_focus()

func _on_cancel_pressed():
	"""Cancel placement mode"""
	cancel_placing_mode()
	
	if cancel_btn:
		cancel_btn.release_focus()

func start_placing_mode():
	"""Start the object placement mode"""
	if current_object_type == "":
		print("ERROR: No object selected")
		return
	
	is_placing = true
	print("Starting placement mode for: ", current_object_type)
	
	# Load the mesh
	var mesh_path = available_objects.get(current_object_type, "")
	if mesh_path == "":
		print("ERROR: Object path not found for: ", current_object_type)
		is_placing = false
		return
	
	print("Loading mesh from: ", mesh_path)
	
	# Load the scene
	var loaded_scene = load(mesh_path)
	if loaded_scene:
		preview_instance = loaded_scene.instantiate()
		get_tree().current_scene.add_child(preview_instance)
		print("Preview instance created and added to scene")
		
		# Make preview semi-transparent
		make_preview_transparent(preview_instance)
		
		# Disable collision
		disable_collision(preview_instance)
		set_collision_layer_recursive(preview_instance, 0)
		set_collision_mask_recursive(preview_instance, 0)
	else:
		print("ERROR: Failed to load scene from: ", mesh_path)
		is_placing = false
		return
	
	# Update button states
	if place_btn:
		place_btn.text = "Finish"
	if cancel_btn:
		cancel_btn.disabled = false
	
	print("Object placement mode activated for: ", current_object_type)

func finish_placing_mode():
	"""Finish placement mode (keep placed objects)"""
	is_placing = false
	
	# Remove preview instance
	if preview_instance and is_instance_valid(preview_instance):
		preview_instance.queue_free()
		preview_instance = null
	
	# Reset button states
	if place_btn:
		place_btn.text = "Place"
	if cancel_btn:
		cancel_btn.disabled = true
	
	print("Object placement mode finished")

func cancel_placing_mode():
	"""Cancel placement mode"""
	finish_placing_mode()

func _process(_delta):
	# Only handle preview when this tool is visible and in placing mode
	if not visible or not is_placing:
		return
	
	# Update preview position based on mouse
	update_preview_position()

func _unhandled_input(event):
	# Only handle input when this tool is visible
	if not visible:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_placing:
				# Place the object
				place_object()
				get_viewport().set_input_as_handled()
	
	elif event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed and is_placing:
			# Cancel placement mode
			cancel_placing_mode()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_R and event.pressed and is_placing and preview_instance:
			# Rotate preview object
			preview_instance.rotate_y(deg_to_rad(15))
			get_viewport().set_input_as_handled()

func update_preview_position():
	"""Update the preview instance position based on mouse cursor"""
	if not preview_instance or not camera:
		camera = get_viewport().get_camera_3d()
		return
	
	var mouse_pos = get_viewport().get_mouse_position()
	
	# Perform raycast to find placement position
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	# Exclude the preview instance from the raycast
	if preview_instance:
		query.exclude = [preview_instance]
		var collision_rids = get_collision_rids(preview_instance)
		for rid in collision_rids:
			query.exclude.append(rid)
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Place at hit position, snapped to grid
		var hit_pos = result.position
		var snapped_pos = snap_to_grid(hit_pos)
		preview_instance.global_position = snapped_pos
		preview_instance.visible = true
	else:
		# If no hit, place at a fixed distance from camera
		var placement_pos = from + camera.project_ray_normal(mouse_pos) * 10.0
		var snapped_pos = snap_to_grid(placement_pos)
		preview_instance.global_position = snapped_pos
		preview_instance.visible = true

func place_object():
	"""Place a new object at the current preview position"""
	if not preview_instance:
		return
	
	var mesh_path = available_objects.get(current_object_type, "")
	if mesh_path == "":
		return
	
	# Get the workspace node
	var workspace = get_tree().current_scene
	
	# Store global position and rotation from preview
	var global_pos = preview_instance.global_position
	var global_rot = preview_instance.global_rotation
	
	# CHECK: Can we place here? Don't even place locally if not allowed
	if not can_place_at_position(global_pos):
		print("Cannot place object here - not in your plot or not authenticated")
		return
	
	# Create a new instance
	var loaded_scene = load(mesh_path)
	if not loaded_scene:
		print("Failed to load object scene")
		return
	
	var new_object = loaded_scene.instantiate()
	
	# Add directly to workspace
	workspace.add_child(new_object)
	
	# Set the transform
	var local_pos = workspace.global_transform.affine_inverse() * global_pos
	new_object.position = local_pos
	new_object.rotation = global_rot
	
	# Create a unique ID for this object
	var net_id = "plot_obj_" + str(Time.get_ticks_msec()) + "_" + str(randi())
	new_object.name = net_id
	
	# Store object type as metadata
	new_object.set_meta("object_type", current_object_type)
	new_object.set_meta("is_plot_object", true)
	# plot_id will be set when server responds with plot_object_spawn
	
	# Register in network controller's objects dictionary so server response updates this object
	if network_controller:
		network_controller._objects[net_id] = new_object
	
	print("Placed plot object: ", current_object_type, " at global: ", global_pos)
	
	# Send placement to server
	send_place_object_to_server(net_id, new_object.global_transform, global_pos)
	
	# Emit signal
	object_placed.emit(current_object_type, global_pos, new_object.global_transform)

func can_place_at_position(position: Vector3) -> bool:
	"""Check if player can place an object at this position (client-side validation)"""
	# Must be authenticated
	if not network_controller:
		return false
	
	# Check if we have a username (authenticated)
	var username = network_controller.get("_username")
	if not username or username == "" or username.begins_with("Guest"):
		print("Not authenticated - cannot place objects")
		return false
	
	# For now, allow placement (server will do final validation)
	# In the future, we could check plot boundaries here if we have them cached
	return true

func send_place_object_to_server(net_id: String, xform: Transform3D, position: Vector3):
	"""Send plot object placement to server"""
	if not network_controller:
		print("NetworkController not found, cannot send placement to server")
		return
	
	# Check if we have a send_json method
	if not network_controller.has_method("send_json"):
		print("NetworkController doesn't have send_json method")
		return
	
	var message = {
		"type": "place_plot_object",
		"net_id": net_id,
		"object_type": current_object_type,
		"position": {
			"x": position.x,
			"y": position.y,
			"z": position.z
		},
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
	print("Sent plot object placement to server: ", net_id)

func snap_to_grid(pos: Vector3) -> Vector3:
	"""Snap a position to the grid"""
	return Vector3(
		round(pos.x / grid_size) * grid_size,
		round(pos.y / grid_size) * grid_size,
		round(pos.z / grid_size) * grid_size
	)

func make_preview_transparent(node: Node):
	"""Make the preview instance semi-transparent"""
	if node is MeshInstance3D:
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if mat:
				mat = mat.duplicate()
				if mat is StandardMaterial3D:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color.a = 0.5
				node.set_surface_override_material(i, mat)
		
		if node.mesh:
			for i in range(node.mesh.get_surface_count()):
				if node.get_surface_override_material(i) == null:
					var mat = node.mesh.surface_get_material(i)
					if mat:
						mat = mat.duplicate()
						if mat is StandardMaterial3D:
							mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
							mat.albedo_color.a = 0.5
						node.set_surface_override_material(i, mat)
	
	for child in node.get_children():
		make_preview_transparent(child)

func disable_collision(node: Node):
	"""Disable collision for all collision nodes"""
	if node is StaticBody3D or node is RigidBody3D or node is CharacterBody3D:
		for child in node.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				child.disabled = true
	
	for child in node.get_children():
		disable_collision(child)

func set_collision_layer_recursive(node: Node, layer: int):
	"""Set collision layer recursively"""
	if node is CollisionObject3D:
		node.collision_layer = layer
	
	for child in node.get_children():
		set_collision_layer_recursive(child, layer)

func set_collision_mask_recursive(node: Node, mask: int):
	"""Set collision mask recursively"""
	if node is CollisionObject3D:
		node.collision_mask = mask
	
	for child in node.get_children():
		set_collision_mask_recursive(child, mask)

func get_collision_rids(node: Node) -> Array:
	"""Get all collision RIDs from a node tree"""
	var rids = []
	
	if node is CollisionObject3D:
		rids.append(node.get_rid())
	
	for child in node.get_children():
		rids.append_array(get_collision_rids(child))
	
	return rids

func _notification(what):
	# Clean up preview when tool is hidden
	if what == NOTIFICATION_VISIBILITY_CHANGED:
		if not visible and is_placing:
			cancel_placing_mode()
