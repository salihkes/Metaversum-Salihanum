extends Control

# New Part Tool for Build Tools
# Handles placing new parts in the workspace

@onready var brick_btn = $SingleDirection
@onready var delete_btn = null  # Will be set in _ready

var camera: Camera3D = null
var brick_scene: PackedScene = null
var preview_instance: Node3D = null
var is_placing: bool = false

# Grid snapping
var grid_size: float = 0.2

# Double-click detection
var last_click_time: float = 0.0
var last_clicked_object: Node3D = null
var double_click_threshold: float = 0.4  # Time in seconds for double-click

# References to managers
var tool_manager: Node = null
var selection_manager: Node = null

func _ready():
	# Connect button signals
	brick_btn.pressed.connect(_on_brick_pressed)
	
	# Get delete button
	delete_btn = get_node_or_null("DeleteButton")
	if delete_btn:
		delete_btn.pressed.connect(_on_delete_pressed)
	
	# Load the brick scene
	brick_scene = load("res://src/texture/brick.tscn")
	
	# Get camera reference
	await get_tree().process_frame
	camera = get_viewport().get_camera_3d()
	
	# Get manager references
	var workspace = get_tree().current_scene
	tool_manager = workspace.get_node_or_null("ToolManager")
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	brick_btn.release_focus()

func _on_brick_pressed():
	if not is_placing:
		start_placing_mode()
	else:
		cancel_placing_mode()
	brick_btn.release_focus()

func _on_delete_pressed():
	"""Delete the currently selected object"""
	if not selection_manager:
		return
	
	var selected = selection_manager.get_selected_object()
	if selected:
		delete_object(selected)
	else:
		print("No object selected to delete")
	
	if delete_btn:
		delete_btn.release_focus()

func delete_object(obj: Node3D):
	"""Delete an object from the workspace"""
	if not obj:
		return
	
	var obj_name = obj.name
	
	# Deselect first
	if selection_manager:
		selection_manager.deselect_all_objects()
	
	# Delete the object
	obj.queue_free()
	
	print("Deleted object: ", obj_name)

func start_placing_mode():
	"""Start the part placement mode"""
	is_placing = true
	
	# Create preview instance
	if brick_scene:
		preview_instance = brick_scene.instantiate()
		get_tree().current_scene.add_child(preview_instance)
		
		# Make preview semi-transparent
		make_preview_transparent(preview_instance)
		
		# Disable collision on preview to avoid interfering with raycasts
		disable_collision(preview_instance)
		
		# Add to a special collision layer so we can exclude it from raycasts
		set_collision_layer_recursive(preview_instance, 0)
		set_collision_mask_recursive(preview_instance, 0)
	
	print("Part placement mode activated. Click to place, ESC to cancel.")

func cancel_placing_mode():
	"""Cancel the part placement mode"""
	is_placing = false
	
	# Remove preview instance
	if preview_instance and is_instance_valid(preview_instance):
		preview_instance.queue_free()
		preview_instance = null
	
	print("Part placement mode cancelled.")

func _process(_delta):
	# Only handle preview when this tool is visible (active) and in placing mode
	if not visible or not is_placing:
		return
	
	# Update preview position based on mouse
	update_preview_position()

func _unhandled_input(event):
	# Only handle input when this tool is visible (active)
	if not visible:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if is_placing:
				# Place the part
				place_part()
				get_viewport().set_input_as_handled()
			else:
				# Check for double-click on existing part (only mark as handled if duplication happened)
				if check_for_duplicate_click(event.position):
					get_viewport().set_input_as_handled()
	
	elif event is InputEventKey:
		if event.keycode == KEY_ESCAPE and event.pressed and is_placing:
			# Cancel placement mode
			cancel_placing_mode()
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
		# Also exclude all children with collision
		var collision_rids = get_collision_rids(preview_instance)
		for rid in collision_rids:
			query.exclude.append(rid)
	
	var result = space_state.intersect_ray(query)
	
	if result:
		# Place at hit position, snapped to grid
		var hit_pos = result.position
		var snapped_pos = snap_to_grid(hit_pos)
		preview_instance.global_position = snapped_pos
		
		# Make preview visible
		preview_instance.visible = true
	else:
		# If no hit, place at a fixed distance from camera
		var placement_pos = from + camera.project_ray_normal(mouse_pos) * 10.0
		var snapped_pos = snap_to_grid(placement_pos)
		preview_instance.global_position = snapped_pos
		preview_instance.visible = true

func place_part():
	"""Place a new part at the current preview position"""
	if not preview_instance or not brick_scene:
		return
	
	# Create a new instance
	var new_part = brick_scene.instantiate()
	
	# Get the workspace node - the root node with scale 0.2
	var workspace = get_tree().current_scene
	
	# Store global position and rotation from preview
	var global_pos = preview_instance.global_position
	var global_rot = preview_instance.global_rotation
	
	# Add directly to workspace
	workspace.add_child(new_part)
	
	# Convert from global space to workspace's local space
	# Since workspace has scale 0.2, we need to account for that
	var local_pos = workspace.global_transform.affine_inverse() * global_pos
	new_part.position = local_pos
	new_part.rotation = global_rot
	
	print("Placed new part at global: ", global_pos, " local: ", new_part.position)
	
	# Keep placement mode active for placing multiple parts
	# User can press ESC or click the button again to exit

func check_for_duplicate_click(mouse_pos: Vector2) -> bool:
	"""Check if user double-clicked on an existing part to duplicate it. Returns true if duplication was triggered."""
	if not camera:
		camera = get_viewport().get_camera_3d()
		if not camera:
			return false
	
	# Perform raycast to find clicked object
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	
	if result:
		var collider = result.collider
		# Find the selectable parent (same logic as selection_manager)
		var target = find_selectable_parent(collider)
		
		if target:
			var current_time = Time.get_ticks_msec() / 1000.0
			
			# Check if this is a double-click on the same object
			if target == last_clicked_object and (current_time - last_click_time) < double_click_threshold:
				# Double-click detected! Duplicate the part
				duplicate_part(target)
				last_clicked_object = null
				last_click_time = 0.0
				return true  # Duplication was triggered
			else:
				# First click, just remember it
				last_clicked_object = target
				last_click_time = current_time
			
			return false  # Just tracking click, not duplicating
	
	# Click on empty space, reset
	last_clicked_object = null
	last_click_time = 0.0
	return false  # Nothing happened

func duplicate_part(original: Node3D):
	"""Duplicate a part and activate move tool"""
	print("Duplicating part: ", original.name)
	
	# Duplicate the node
	var duplicate = original.duplicate()
	
	# Add to workspace (same parent as original)
	var workspace = get_tree().current_scene
	workspace.add_child(duplicate)
	
	# Copy transform from original (exact position, no offset)
	duplicate.global_transform = original.global_transform
	
	print("Created duplicate at: ", duplicate.global_position)
	
	# Switch to move tool
	if tool_manager:
		# Use enum value 1 for MOVE (NONE=0, MOVE=1, RESIZE=2, ROTATE=3, MATERIAL=4, NEW_PART=5)
		tool_manager.set_tool(1)  # ToolType.MOVE
	
	# Select the duplicated object
	if selection_manager:
		await get_tree().process_frame
		var objects: Array[Node3D] = [duplicate]
		selection_manager.select_objects(objects)

func find_selectable_parent(node: Node) -> Node3D:
	"""Find the selectable parent node (same logic as selection_manager)"""
	var current = node
	while current:
		if current is Node3D:
			# Don't select the humanoid or its children
			if current.name == "humanoid" or is_child_of_humanoid(current):
				return null
			# Don't select the workspace root
			if current.name == "workspace":
				return null
			# Don't select UI or camera related nodes
			if current.name.contains("Lightning") or current.name.contains("Camera"):
				return null
			# Check if it's a valid selectable object
			if current.get_parent() and (current.get_parent().name == "workspace" or current.get_parent().name == "InteractiveObjects"):
				return current
		current = current.get_parent()
	return null

func is_child_of_humanoid(node: Node) -> bool:
	"""Check if node is a child of humanoid"""
	var current = node.get_parent()
	while current:
		if current.name == "humanoid":
			return true
		current = current.get_parent()
	return false

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
		# Duplicate materials to avoid affecting the original
		for i in range(node.get_surface_override_material_count()):
			var mat = node.get_surface_override_material(i)
			if mat:
				mat = mat.duplicate()
				if mat is StandardMaterial3D:
					mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					mat.albedo_color.a = 0.5
				node.set_surface_override_material(i, mat)
		
		# Also handle mesh materials if no override
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
	
	# Recursively process children
	for child in node.get_children():
		make_preview_transparent(child)

func disable_collision(node: Node):
	"""Disable collision for all StaticBody3D children"""
	if node is StaticBody3D or node is RigidBody3D or node is CharacterBody3D:
		# Remove all collision shapes
		for child in node.get_children():
			if child is CollisionShape3D or child is CollisionPolygon3D:
				child.disabled = true
	
	# Recursively process children
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
