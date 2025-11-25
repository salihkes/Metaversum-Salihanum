extends Node

# Selection Manager for Build Tools
# Handles object selection via mouse clicks in the scene

signal objects_selected(objects: Array)
signal objects_deselected()

# Tool modes (synced with ToolManager)
enum ToolType {
	NONE,
	MOVE,
	RESIZE,
	ROTATE,
	MATERIAL,
	NEW_PART,
	COLOR,
	GROUP
}

enum SelectionMode {
	PART,  # Select individual parts
	GROUP  # Select entire groups
}

var current_tool_mode: ToolType = ToolType.NONE
var selection_mode: SelectionMode = SelectionMode.PART  # Default to part mode
var selected_objects: Array[Node3D] = []  # Changed from single object to array
var camera: Camera3D = null

# Drag box selection state
var is_box_selecting: bool = false
var box_select_start_pos: Vector2
var box_select_current_pos: Vector2
var box_select_canvas: Control = null

# Dragging state (gizmo-based manipulation)
var is_dragging: bool = false
var dragged_sphere: MeshInstance3D = null
var drag_start_mouse_pos: Vector2
var drag_start_object_scale: Vector3
var drag_start_object_pos: Vector3
var drag_start_object_basis: Basis  # For rotation
var drag_axis: int = 0
var drag_direction: int = 1
var drag_start_gizmo_pos: Vector3  # Fixed gizmo position at drag start
var drag_screen_axis_dir: Vector2  # Screen direction for dragging

# Natural object dragging state
var is_object_dragging: bool = false
var object_drag_start_time: float = 0.0
var object_drag_start_mouse_pos: Vector2
var object_drag_initial_pos: Vector3
var object_drag_plane_point: Vector3
var object_drag_plane_normal: Vector3
var object_drag_offset: Vector3  # Offset from object center to initial hit point
var drag_threshold_time: float = 0.15  # Time in seconds before drag activates
var drag_threshold_distance: float = 5.0  # Pixels moved before drag activates
var is_waiting_for_drag: bool = false

func _ready():
	
	# Don't cache camera - we'll get it dynamically to support camera switching
	await get_tree().process_frame
	
	# Create selection box canvas
	create_selection_box_canvas()
	
func _unhandled_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var shift_pressed = Input.is_key_pressed(KEY_SHIFT)
				
				# Check if we're clicking on a gizmo first
				if selected_objects.size() > 0:
					var gizmo = get_gizmo_at_mouse(event.position)
					if gizmo:
						start_gizmo_drag(gizmo, event.position)
						return
					
					# Check if clicking on an already selected object for natural dragging
					# Only allow natural dragging in MOVE mode (and not when shift is pressed for toggling)
					if current_tool_mode == ToolType.MOVE and not shift_pressed:
						var hit_result = raycast_from_mouse(event.position)
						if hit_result and hit_result.collider:
							var target = find_selectable_parent(hit_result.collider)
							if target and target in selected_objects:
								# Start waiting for drag mode
								start_waiting_for_drag(event.position, hit_result.position)
								return
				
				# Check if clicking on an object
				var hit_result = raycast_from_mouse(event.position)
				var clicked_object = null
				if hit_result and hit_result.collider:
					clicked_object = find_selectable_parent(hit_result.collider)
				
				if clicked_object:
					# Object was clicked
					if shift_pressed:
						# Toggle selection
						toggle_object_selection(clicked_object)
					else:
						# Replace selection with this object
						select_objects([clicked_object])
				else:
					# Empty space clicked - start box selection or deselect
					if shift_pressed:
						# Start box selection to add more objects
						start_box_selection(event.position)
					else:
						# Check if we should start box selection or just deselect
						# Start box selection on empty space
						start_box_selection(event.position)
			else:
				# Mouse released - stop dragging or finish box selection
				if is_dragging:
					stop_gizmo_drag()
				elif is_object_dragging or is_waiting_for_drag:
					stop_object_drag()
				elif is_box_selecting:
					finish_box_selection(Input.is_key_pressed(KEY_SHIFT))
	
	elif event is InputEventMouseMotion:
		if is_dragging:
			update_gizmo_drag(event.position)
		elif is_waiting_for_drag:
			check_drag_threshold(event.position)
		elif is_object_dragging:
			update_object_drag(event.position)
		elif is_box_selecting:
			update_box_selection(event.position)
	
	elif event is InputEventKey:
		# Handle Delete key for deleting selected objects
		if event.keycode == KEY_DELETE and event.pressed and not event.echo:
			if selected_objects.size() > 0:
				# Save undo state before deleting
				var tool_manager = get_tree().current_scene.get_node_or_null("ToolManager")
				if tool_manager and tool_manager.has_method("save_undo_state"):
					tool_manager.save_undo_state("Delete objects")
				delete_selected_objects()
				get_viewport().set_input_as_handled()

func _process(delta):
	# Check time-based drag threshold
	if is_waiting_for_drag and not is_object_dragging:
		if Time.get_ticks_msec() / 1000.0 - object_drag_start_time >= drag_threshold_time:
			activate_object_drag()

# Box selection functions
func create_selection_box_canvas():
	box_select_canvas = Control.new()
	box_select_canvas.name = "SelectionBoxCanvas"
	box_select_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box_select_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	box_select_canvas.visible = false
	box_select_canvas.draw.connect(_draw_selection_box)
	add_child(box_select_canvas)

func _draw_selection_box():
	"""Draw the selection box on the canvas"""
	if not is_box_selecting:
		return
	
	var rect_min = Vector2(
		min(box_select_start_pos.x, box_select_current_pos.x),
		min(box_select_start_pos.y, box_select_current_pos.y)
	)
	var rect_max = Vector2(
		max(box_select_start_pos.x, box_select_current_pos.x),
		max(box_select_start_pos.y, box_select_current_pos.y)
	)
	var rect_size = rect_max - rect_min
	
	# Draw filled rectangle with transparency
	box_select_canvas.draw_rect(Rect2(rect_min, rect_size), Color(0.3, 0.6, 1.0, 0.2))
	# Draw border
	box_select_canvas.draw_rect(Rect2(rect_min, rect_size), Color(0.3, 0.6, 1.0, 0.8), false, 2.0)

func start_box_selection(mouse_pos: Vector2):
	is_box_selecting = true
	box_select_start_pos = mouse_pos
	box_select_current_pos = mouse_pos
	box_select_canvas.visible = true
	box_select_canvas.queue_redraw()
	print("Started box selection")

func update_box_selection(mouse_pos: Vector2):
	box_select_current_pos = mouse_pos
	box_select_canvas.queue_redraw()

func finish_box_selection(additive: bool):
	is_box_selecting = false
	box_select_canvas.visible = false
	box_select_canvas.queue_redraw()
	
	# Calculate selection rectangle
	var min_x = min(box_select_start_pos.x, box_select_current_pos.x)
	var max_x = max(box_select_start_pos.x, box_select_current_pos.x)
	var min_y = min(box_select_start_pos.y, box_select_current_pos.y)
	var max_y = max(box_select_start_pos.y, box_select_current_pos.y)
	
	# Check if the box is too small (just a click)
	var box_size = Vector2(max_x - min_x, max_y - min_y)
	if box_size.length() < 5.0:
		# Too small, treat as deselect if not additive
		if not additive:
			deselect_all_objects()
		print("Box too small, treating as click")
		return
	
	var rect = Rect2(Vector2(min_x, min_y), box_size)
	
	# Find all selectable objects in the scene
	var workspace = get_tree().current_scene
	var objects_to_check = []
	
	# Check if we're in localworkspace mode
	var is_localworkspace = workspace and workspace.name == "localworkspace"
	
	# Get all direct children of workspace that are Node3D and not excluded
	for child in workspace.get_children():
		if child is Node3D and child.name != "humanoid" and child.name != "Lightning" and child.name != "InteractiveObjects" and child.name != "SelectionMarkers":
			# In localworkspace, allow all objects; otherwise only plot objects
			if is_localworkspace:
				objects_to_check.append(child)
			elif child.has_meta("is_plot_object"):
				objects_to_check.append(child)
	
	# Also check InteractiveObjects if it exists
	if workspace.has_node("InteractiveObjects"):
		var io_node = workspace.get_node("InteractiveObjects")
		for child in io_node.get_children():
			if child is Node3D:
				# In localworkspace, allow all objects; otherwise only plot objects
				if is_localworkspace:
					objects_to_check.append(child)
				elif child.has_meta("is_plot_object"):
					objects_to_check.append(child)
	
	print("Box selection: Found ", objects_to_check.size(), " objects to check")
	
	# Check which objects are inside the selection box (and not locked)
	var objects_in_box: Array[Node3D] = []
	for obj in objects_to_check:
		if is_object_in_screen_rect(obj, rect) and not is_object_locked(obj):
			objects_in_box.append(obj)
	
	# Update selection
	if additive:
		# Add to existing selection
		for obj in objects_in_box:
			if obj not in selected_objects:
				selected_objects.append(obj)
		if objects_in_box.size() > 0:
			update_selection_visuals()
			objects_selected.emit(selected_objects)
	else:
		# Replace selection
		if objects_in_box.size() > 0:
			select_objects(objects_in_box)
		else:
			deselect_all_objects()
	
	print("Box selection finished. Selected ", objects_in_box.size(), " objects")

func is_object_locked(obj: Node3D) -> bool:
	"""Check if an object has the locked property set to true"""
	# Check the object itself first
	var locked_value = obj.get("locked")
	
	# If not found on this node, check the parent (in case we're on a child mesh like MATERIAL)
	if locked_value == null:
		var parent = obj.get_parent()
		if parent:
			locked_value = parent.get("locked")
	
	# Debug output
	print("Checking lock status for: ", obj.name, " | Parent: ", obj.get_parent().name if obj.get_parent() else "none", " | Locked: ", locked_value)
	
	if locked_value != null and locked_value == true:
		return true
	return false

func find_selectable_parent(node: Node) -> Node3D:
	# Look for a parent Node3D that isn't the workspace itself
	# and isn't a child of the humanoid
	# IMPORTANT: Only allow selection of plot objects (objects with "is_plot_object" metadata)
	# EXCEPTION: If workspace is "localworkspace", allow all unlocked objects (localworkspace means we are in editor)
	var current = node
	var found_part: Node3D = null
	
	# Check if we're in localworkspace mode
	var workspace = get_tree().current_scene
	var is_localworkspace = workspace and workspace.name == "localworkspace"
	
	while current:
		if current is Node3D:
			# Don't select gizmos/selection markers or their children
			if current.name == "SelectionMarkers" or is_child_of_selection_markers(current):
				return null
			# Don't select the humanoid or its children
			if current.name == "humanoid" or is_child_of_humanoid(current):
				return null
			# Don't select the workspace root
			if current.name == "workspace" or current.name == "localworkspace":
				return null
			# Don't select UI or camera related nodes
			if current.name.contains("Lightning") or current.name.contains("Camera"):
				return null
			
			# Check if it's a valid selectable object
			var parent = current.get_parent()
			if parent and (parent.name == "workspace" or parent.name == "localworkspace" or parent.name == "InteractiveObjects"):
				# In localworkspace, allow all objects; otherwise only plot objects
				if not is_localworkspace:
					# ONLY allow plot objects - reject everything else (map elements, etc)
					if not current.has_meta("is_plot_object"):
						return null
				# This is a top-level object
				found_part = current
				break
			# Check if current is inside a group (parent is a Node3D named "Group..." and grandparent is workspace)
			elif parent and parent is Node3D and parent.name.begins_with("Group"):
				var grandparent = parent.get_parent()
				if grandparent and (grandparent.name == "workspace" or grandparent.name == "localworkspace"):
					# Current is a part inside a group - always select the group
					print("Selecting group '", parent.name, "' (contains '", current.name, "')")
					if is_object_locked(parent):
						return null
					return parent
		current = current.get_parent()
	
	# Check if the found part is locked
	if found_part and is_object_locked(found_part):
		return null
	
	return found_part

func is_child_of_humanoid(node: Node) -> bool:
	var current = node.get_parent()
	while current:
		if current.name == "humanoid":
			return true
		current = current.get_parent()
	return false

func is_child_of_selection_markers(node: Node) -> bool:
	var current = node.get_parent()
	while current:
		if current.name == "SelectionMarkers":
			return true
		current = current.get_parent()
	return false

func is_object_in_screen_rect(obj: Node3D, rect: Rect2) -> bool:
	"""Check if an object is inside the screen rectangle"""
	var active_camera = get_viewport().get_camera_3d()
	if not active_camera:
		return false
	var camera = active_camera
	
	# Get object's AABB and check corners
	var aabb = get_object_aabb(obj)
	if not aabb:
		# Just check center point
		var screen_pos = camera.unproject_position(obj.global_position)
		return rect.has_point(screen_pos)
	
	# Transform AABB to world space and check multiple points
	var world_transform = obj.global_transform
	var corners = [
		world_transform * (aabb.position),
		world_transform * (aabb.position + Vector3(aabb.size.x, 0, 0)),
		world_transform * (aabb.position + Vector3(0, aabb.size.y, 0)),
		world_transform * (aabb.position + Vector3(0, 0, aabb.size.z)),
		world_transform * (aabb.position + Vector3(aabb.size.x, aabb.size.y, 0)),
		world_transform * (aabb.position + Vector3(aabb.size.x, 0, aabb.size.z)),
		world_transform * (aabb.position + Vector3(0, aabb.size.y, aabb.size.z)),
		world_transform * (aabb.position + aabb.size)
	]
	
	# Check if any corner is inside the rectangle
	for corner in corners:
		var screen_pos = camera.unproject_position(corner)
		if rect.has_point(screen_pos):
			return true
	
	# Also check center
	var center = world_transform * aabb.get_center()
	var center_screen = camera.unproject_position(center)
	if rect.has_point(center_screen):
		return true
	
	return false

func select_objects(objects: Array[Node3D]):
	"""Select multiple objects, replacing current selection"""
	# Deselect all first
	deselect_all_objects()
	
	selected_objects = objects.duplicate()
	print("Selected ", selected_objects.size(), " object(s)")
	
	# Add visual feedback
	update_selection_visuals()
	
	# Emit signal
	if selected_objects.size() > 0:
		objects_selected.emit(selected_objects)

func toggle_object_selection(obj: Node3D):
	"""Toggle an object's selection state"""
	if obj in selected_objects:
		# Remove from selection
		selected_objects.erase(obj)
		remove_selection_outline_for_object(obj)
		print("Removed from selection: ", obj.name)
		
		if selected_objects.size() == 0:
			objects_deselected.emit()
		else:
			objects_selected.emit(selected_objects)
	else:
		# Add to selection
		selected_objects.append(obj)
		print("Added to selection: ", obj.name)
		update_selection_visuals()
		objects_selected.emit(selected_objects)

func update_selection_visuals():
	"""Update visual markers for all selected objects"""
	# Remove old markers
	remove_all_selection_outlines()
	
	# Add markers for all selected objects
	if selected_objects.size() > 0:
		add_selection_outlines(selected_objects)

func set_tool_mode(tool_mode: ToolType):
	current_tool_mode = tool_mode
	
	# Always keep GROUP mode - groups should always be selectable as groups
	# The tool only determines what operations are available, not how selection works
	selection_mode = SelectionMode.GROUP
	print("Tool changed to: ", ToolType.keys()[tool_mode])
	
	# Refresh gizmos if objects are selected
	if selected_objects.size() > 0:
		update_selection_visuals()

func deselect_all_objects():
	"""Deselect all objects"""
	if selected_objects.size() > 0:
		print("Deselected ", selected_objects.size(), " object(s)")
		remove_all_selection_outlines()
		selected_objects.clear()
		objects_deselected.emit()

func add_selection_outlines(objects: Array[Node3D]):
	"""Add visual indicators for multiple selected objects"""
	var workspace = get_tree().current_scene
	if workspace.has_node("SelectionMarkers"):
		return
	
	var markers_parent = Node3D.new()
	markers_parent.name = "SelectionMarkers"
	# Add to root workspace instead of as child of object to maintain independence
	get_tree().current_scene.add_child(markers_parent)
	
	# Store references to all objects for updates
	markers_parent.set_meta("target_objects", objects)
	markers_parent.set_meta("tool_mode", current_tool_mode)
	
	# Create gizmos for each object
	for obj in objects:
		var obj_markers = Node3D.new()
		obj_markers.name = "Markers_" + obj.name
		obj_markers.set_meta("target_object", obj)
		markers_parent.add_child(obj_markers)
		
		# Create different gizmos based on tool mode
		match current_tool_mode:
			ToolType.MOVE:
				create_move_gizmos(obj_markers, obj)
			ToolType.RESIZE:
				create_resize_gizmos(obj_markers, obj)
			ToolType.ROTATE:
				create_rotate_gizmos(obj_markers, obj)
			_:
				pass
	
	# Connect to update function
	if not get_tree().process_frame.is_connected(update_selection_markers):
		get_tree().process_frame.connect(update_selection_markers)

func create_resize_gizmos(parent: Node3D, obj: Node3D):
	# Create 6 spheres for resize (current behavior)
	var aabb = get_object_aabb(obj)
	if not aabb:
		return
	
	var world_transform = obj.global_transform
	var center = world_transform * aabb.get_center()
	
	var size = Vector3(
		(world_transform * Vector3(aabb.size.x / 2.0, 0, 0)).length() * 2.0,
		(world_transform * Vector3(0, aabb.size.y / 2.0, 0)).length() * 2.0,
		(world_transform * Vector3(0, 0, aabb.size.z / 2.0)).length() * 2.0
	)
	
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = 0.2
	sphere_mesh.height = 0.4
	
	var material = StandardMaterial3D.new()
	material.albedo_color = Color(0, 0.8, 1, 1)  # Cyan for resize
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.render_priority = 10
	material.no_depth_test = true
	
	var directions = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]
	
	var direction_names = ["PosX", "NegX", "PosY", "NegY", "PosZ", "NegZ"]
	
	for i in range(6):
		var sphere = MeshInstance3D.new()
		sphere.name = direction_names[i]
		sphere.mesh = sphere_mesh
		sphere.material_override = material
		sphere.set_meta("axis", i / 2)
		sphere.set_meta("direction", 1 if i % 2 == 0 else -1)
		sphere.set_meta("gizmo_type", "resize")
		
		# Calculate offset in local space, then transform to world space
		var axis_index = i / 2
		var local_offset = Vector3.ZERO
		local_offset[axis_index] = directions[i][axis_index] * (aabb.size[axis_index] / 2.0 + 0.2)
		
		# Transform local offset through object's basis and add to center
		sphere.global_position = center + world_transform.basis * local_offset
		parent.add_child(sphere)

func create_move_gizmos(parent: Node3D, obj: Node3D):
	# Create 6 arrow cones for movement
	var aabb = get_object_aabb(obj)
	if not aabb:
		return
	
	var world_transform = obj.global_transform
	var center = world_transform * aabb.get_center()
	
	var size = Vector3(
		(world_transform * Vector3(aabb.size.x / 2.0, 0, 0)).length() * 2.0,
		(world_transform * Vector3(0, aabb.size.y / 2.0, 0)).length() * 2.0,
		(world_transform * Vector3(0, 0, aabb.size.z / 2.0)).length() * 2.0
	)
	
	# Create cone mesh for arrows
	var cone_mesh = CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = 0.15
	cone_mesh.height = 0.4
	
	var colors = [
		Color(1, 0, 0, 1), Color(1, 0, 0, 1),  # Red for X
		Color(0, 1, 0, 1), Color(0, 1, 0, 1),  # Green for Y
		Color(0, 0, 1, 1), Color(0, 0, 1, 1)   # Blue for Z
	]
	
	var directions = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]
	
	var direction_names = ["PosX", "NegX", "PosY", "NegY", "PosZ", "NegZ"]
	
	for i in range(6):
		var arrow = MeshInstance3D.new()
		arrow.name = direction_names[i]
		arrow.mesh = cone_mesh
		
		var material = StandardMaterial3D.new()
		material.albedo_color = colors[i]
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.render_priority = 10
		material.no_depth_test = true
		arrow.material_override = material
		
		arrow.set_meta("axis", i / 2)
		arrow.set_meta("direction", 1 if i % 2 == 0 else -1)
		arrow.set_meta("gizmo_type", "move")
		
		# Calculate offset in local space, then transform to world space
		var axis_index = i / 2
		var local_offset = Vector3.ZERO
		local_offset[axis_index] = directions[i][axis_index] * (aabb.size[axis_index] / 2.0 + 0.4)
		
		# Transform local offset through object's basis and add to center
		arrow.global_position = center + world_transform.basis * local_offset
		
		# Rotate cone to point in the right direction
		# Apply object's rotation first, then arrow rotation
		var arrow_rotation = Basis()
		if i / 2 == 0:  # X axis
			arrow_rotation = arrow_rotation.rotated(Vector3.FORWARD, -PI / 2 if i % 2 == 0 else PI / 2)
		elif i / 2 == 1:  # Y axis
			arrow_rotation = arrow_rotation.rotated(Vector3.RIGHT, PI if i % 2 == 1 else 0)
		else:  # Z axis
			arrow_rotation = arrow_rotation.rotated(Vector3.RIGHT, PI / 2 if i % 2 == 0 else -PI / 2)
		
		arrow.global_transform.basis = world_transform.basis * arrow_rotation
		
		parent.add_child(arrow)

func create_rotate_gizmos(parent: Node3D, obj: Node3D):
	# Create 3 torus rings for rotation around each axis
	var aabb = get_object_aabb(obj)
	if not aabb:
		return
	
	var world_transform = obj.global_transform
	var center = world_transform * aabb.get_center()
	
	var size = Vector3(
		(world_transform * Vector3(aabb.size.x / 2.0, 0, 0)).length() * 2.0,
		(world_transform * Vector3(0, aabb.size.y / 2.0, 0)).length() * 2.0,
		(world_transform * Vector3(0, 0, aabb.size.z / 2.0)).length() * 2.0
	)
	
	# Use torus for rotation rings
	var torus_mesh = TorusMesh.new()
	var avg_size = (size.x + size.y + size.z) / 3.0
	torus_mesh.inner_radius = avg_size / 2.0 + 0.3
	torus_mesh.outer_radius = avg_size / 2.0 + 0.4
	torus_mesh.rings = 32
	torus_mesh.ring_segments = 16
	
	var colors = [
		Color(1, 0, 0, 0.8),  # Red for X
		Color(0, 1, 0, 0.8),  # Green for Y
		Color(0, 0, 1, 0.8)   # Blue for Z
	]
	
	var axis_names = ["X", "Y", "Z"]
	
	for i in range(3):
		var ring = MeshInstance3D.new()
		ring.name = "Ring" + axis_names[i]
		ring.mesh = torus_mesh
		
		var material = StandardMaterial3D.new()
		material.albedo_color = colors[i]
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.render_priority = 10
		material.no_depth_test = true
		ring.material_override = material
		
		ring.set_meta("axis", i)
		ring.set_meta("gizmo_type", "rotate")
		
		ring.global_position = center
		
		# Rotate ring to align with axis
		if i == 0:  # X axis
			ring.rotation.y = PI / 2
		elif i == 2:  # Z axis
			ring.rotation.x = PI / 2
		# Y axis needs no rotation (default orientation)
		
		parent.add_child(ring)

func remove_all_selection_outlines():
	"""Remove all selection visual markers"""
	var workspace = get_tree().current_scene
	if workspace.has_node("SelectionMarkers"):
		var markers = workspace.get_node("SelectionMarkers")
		markers.queue_free()

func remove_selection_outline_for_object(obj: Node3D):
	"""Remove selection markers for a specific object"""
	var workspace = get_tree().current_scene
	if workspace.has_node("SelectionMarkers"):
		var markers = workspace.get_node("SelectionMarkers")
		var marker_name = "Markers_" + obj.name
		if markers.has_node(marker_name):
			markers.get_node(marker_name).queue_free()

func update_selection_markers():
	# Update marker positions every frame to follow selected objects
	if selected_objects.size() == 0:
		return
	
	var workspace = get_tree().current_scene
	if not workspace.has_node("SelectionMarkers"):
		return
	
	var markers = workspace.get_node("SelectionMarkers")
	if not markers.has_meta("target_objects"):
		return
	
	# Get the tool mode
	var tool_mode = markers.get_meta("tool_mode") if markers.has_meta("tool_mode") else ToolType.NONE
	
	# Update each object's markers
	for obj_marker in markers.get_children():
		if not obj_marker.has_meta("target_object"):
			continue
		
		var obj = obj_marker.get_meta("target_object")
		if not is_instance_valid(obj):
			obj_marker.queue_free()
			continue
		
		var aabb = get_object_aabb(obj)
		if not aabb:
			continue
		
		var world_transform = obj.global_transform
		var center = world_transform * aabb.get_center()
		
		# Update gizmo positions based on type
		match tool_mode:
			ToolType.MOVE:
				update_move_gizmos(obj_marker, center, obj, aabb)
			ToolType.RESIZE:
				update_resize_gizmos(obj_marker, center, obj, aabb)
			ToolType.ROTATE:
				update_rotate_gizmos(obj_marker, center, obj, aabb)
			_:
				pass

func update_resize_gizmos(markers: Node3D, center: Vector3, obj: Node3D, aabb: AABB):
	var world_transform = obj.global_transform
	var directions = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]
	
	for i in range(min(6, markers.get_child_count())):
		var gizmo = markers.get_child(i)
		var axis_index = i / 2
		
		# Calculate offset in local space, then transform to world space
		var local_offset = Vector3.ZERO
		local_offset[axis_index] = directions[i][axis_index] * (aabb.size[axis_index] / 2.0 + 0.2)
		
		gizmo.global_position = center + world_transform.basis * local_offset

func update_move_gizmos(markers: Node3D, center: Vector3, obj: Node3D, aabb: AABB):
	var world_transform = obj.global_transform
	var directions = [
		Vector3(1, 0, 0), Vector3(-1, 0, 0),
		Vector3(0, 1, 0), Vector3(0, -1, 0),
		Vector3(0, 0, 1), Vector3(0, 0, -1)
	]
	
	for i in range(min(6, markers.get_child_count())):
		var gizmo = markers.get_child(i)
		var axis_index = i / 2
		
		# Calculate offset in local space, then transform to world space
		var local_offset = Vector3.ZERO
		local_offset[axis_index] = directions[i][axis_index] * (aabb.size[axis_index] / 2.0 + 0.4)
		
		gizmo.global_position = center + world_transform.basis * local_offset
		
		# Update arrow rotation to match object rotation
		var arrow_rotation = Basis()
		if i / 2 == 0:  # X axis
			arrow_rotation = arrow_rotation.rotated(Vector3.FORWARD, -PI / 2 if i % 2 == 0 else PI / 2)
		elif i / 2 == 1:  # Y axis
			arrow_rotation = arrow_rotation.rotated(Vector3.RIGHT, PI if i % 2 == 1 else 0)
		else:  # Z axis
			arrow_rotation = arrow_rotation.rotated(Vector3.RIGHT, PI / 2 if i % 2 == 0 else -PI / 2)
		
		gizmo.global_transform.basis = world_transform.basis * arrow_rotation

func update_rotate_gizmos(markers: Node3D, center: Vector3, obj: Node3D, aabb: AABB):
	var world_transform = obj.global_transform
	
	# Update ring positions and rotations
	for i in range(min(3, markers.get_child_count())):
		var ring = markers.get_child(i)
		ring.global_position = center
		
		# Update ring rotation to match object rotation
		var ring_rotation = Basis()
		if i == 0:  # X axis
			ring_rotation = ring_rotation.rotated(Vector3.UP, PI / 2)
		elif i == 2:  # Z axis
			ring_rotation = ring_rotation.rotated(Vector3.RIGHT, PI / 2)
		# Y axis needs no rotation (default orientation)
		
		ring.global_transform.basis = world_transform.basis * ring_rotation


func get_object_aabb(obj: Node3D) -> AABB:
	# Get the AABB of the object
	if obj is MeshInstance3D:
		return obj.get_aabb()
	elif obj is CSGShape3D:
		return obj.get_meshes()[0].get_aabb() if obj.get_meshes().size() > 0 else AABB()
	else:
		# For other Node3D types, try to find mesh children
		for child in obj.get_children():
			if child is MeshInstance3D:
				return child.get_aabb()
		# Return a default AABB if nothing found
		return AABB(Vector3.ZERO, Vector3.ONE)

func get_selected_objects() -> Array[Node3D]:
	"""Get all currently selected objects"""
	return selected_objects.duplicate()

func get_selected_object() -> Node3D:
	"""Get the first selected object (for backward compatibility)"""
	if selected_objects.size() > 0:
		return selected_objects[0]
	return null

func set_selection_mode(mode: SelectionMode):
	selection_mode = mode
	print("Selection mode changed to: ", "GROUP" if mode == SelectionMode.GROUP else "PART")
	
	# If objects are selected, re-evaluate selection based on new mode
	if selected_objects.size() > 0:
		var current_selections = selected_objects.duplicate()
		deselect_all_objects()
		
		var new_selections: Array[Node3D] = []
		for current_selection in current_selections:
			# Try to find appropriate selection based on new mode
			if mode == SelectionMode.GROUP:
				# If the part was in a group, select the group
				var parent = current_selection.get_parent()
				if parent and parent.get_parent() and parent.get_parent().name == "workspace":
					if parent not in new_selections:
						new_selections.append(parent)
				else:
					if current_selection not in new_selections:
						new_selections.append(current_selection)
			else:
				# In part mode, keep the current selection
				if current_selection not in new_selections:
					new_selections.append(current_selection)
		
		if new_selections.size() > 0:
			select_objects(new_selections)

func get_selection_mode() -> SelectionMode:
	return selection_mode

func delete_selected_objects():
	"""Delete all currently selected objects"""
	if selected_objects.size() == 0:
		return
	
	var objects_to_delete = selected_objects.duplicate()
	var count = objects_to_delete.size()
	
	# Deselect first (this removes gizmos and clears references)
	deselect_all_objects()
	
	# Delete the objects
	for obj in objects_to_delete:
		if is_instance_valid(obj):
			obj.queue_free()
	
	print("Deleted ", count, " object(s)")

func get_gizmo_at_mouse(mouse_pos: Vector2) -> MeshInstance3D:
	var active_camera = get_viewport().get_camera_3d()
	if selected_objects.size() == 0 or not active_camera:
		return null
	var camera = active_camera
	
	var workspace = get_tree().current_scene
	if not workspace.has_node("SelectionMarkers"):
		return null
	
	var markers = workspace.get_node("SelectionMarkers")
	
	# Perform raycast
	var from = camera.project_ray_origin(mouse_pos)
	var to = from + camera.project_ray_normal(mouse_pos) * 1000.0
	
	# Find the closest gizmo to the mouse ray
	var closest_gizmo: MeshInstance3D = null
	var closest_distance = INF
	var click_radius_3d = 0.5  # 3D click radius
	var click_radius_screen = 30.0  # Screen-space click radius in pixels
	
	# Check each object's gizmos
	for obj_markers in markers.get_children():
		for gizmo in obj_markers.get_children():
			if gizmo is MeshInstance3D:
				var gizmo_pos = gizmo.global_position
				
				# Use both 3D distance and screen distance for better detection
				var distance_to_ray = point_distance_to_ray(gizmo_pos, from, to - from)
				
				# Also check screen-space distance
				var gizmo_screen_pos = camera.unproject_position(gizmo_pos)
				var screen_distance = mouse_pos.distance_to(gizmo_screen_pos)
				
				# Gizmo is clickable if either 3D or screen distance is within threshold
				var is_clickable = (distance_to_ray < click_radius_3d) or (screen_distance < click_radius_screen)
				
				# Use combined distance for prioritization (prefer screen distance for UI feel)
				var combined_distance = screen_distance * 0.01 + distance_to_ray
				
				if is_clickable and combined_distance < closest_distance:
					closest_gizmo = gizmo
					closest_distance = combined_distance
	
	return closest_gizmo

func point_distance_to_ray(point: Vector3, ray_origin: Vector3, ray_direction: Vector3) -> float:
	var ray_dir_normalized = ray_direction.normalized()
	var to_point = point - ray_origin
	var projection = to_point.dot(ray_dir_normalized)
	
	# If projection is negative, point is behind the ray origin
	if projection < 0:
		return INF
	
	var closest_point = ray_origin + ray_dir_normalized * projection
	return point.distance_to(closest_point)

var drag_initial_states: Array[Dictionary] = []  # Store initial state for each selected object

func start_gizmo_drag(gizmo: MeshInstance3D, mouse_pos: Vector2):
	is_dragging = true
	dragged_sphere = gizmo
	drag_start_mouse_pos = mouse_pos
	drag_axis = gizmo.get_meta("axis", 0)
	drag_direction = gizmo.get_meta("direction", 1)
	
	# Store initial states for all selected objects
	drag_initial_states.clear()
	for obj in selected_objects:
		var state = {
			"object": obj,
			"scale": obj.scale,
			"position": obj.global_position,
			"basis": obj.global_transform.basis
		}
		drag_initial_states.append(state)
	
	# Use first selected object for reference
	if selected_objects.size() > 0:
		drag_start_object_scale = selected_objects[0].scale
		drag_start_object_pos = selected_objects[0].global_position
		drag_start_object_basis = selected_objects[0].global_transform.basis
	
	# Store the initial gizmo position
	drag_start_gizmo_pos = gizmo.global_position
	
	# Calculate the screen space direction for this axis at drag start
	var active_camera = get_viewport().get_camera_3d()
	if active_camera:
		var gizmo_screen = active_camera.unproject_position(drag_start_gizmo_pos)
		# Create test offset in local space, then transform to world space
		var local_offset = Vector3.ZERO
		local_offset[drag_axis] = drag_direction * 1.0
		var world_offset = drag_start_object_basis * local_offset
		var test_world_pos = drag_start_gizmo_pos + world_offset
		var test_screen_pos = active_camera.unproject_position(test_world_pos)
		drag_screen_axis_dir = (test_screen_pos - gizmo_screen).normalized()
	
	# Change gizmo color to indicate dragging
	var material = gizmo.material_override.duplicate()
	material.albedo_color = Color(1, 0.5, 0, 1)  # Orange
	gizmo.material_override = material
	
	var gizmo_type = gizmo.get_meta("gizmo_type") if gizmo.has_meta("gizmo_type") else "resize"
	print("Started dragging ", gizmo_type, " gizmo on axis ", drag_axis, " direction ", drag_direction, " for ", selected_objects.size(), " object(s)")

func stop_gizmo_drag():
	if dragged_sphere and is_instance_valid(dragged_sphere):
		# Reset gizmo to original color based on type
		var gizmo_type = dragged_sphere.get_meta("gizmo_type") if dragged_sphere.has_meta("gizmo_type") else "resize"
		var material = dragged_sphere.material_override.duplicate()
		
		# Restore original color based on gizmo type
		match gizmo_type:
			"resize":
				material.albedo_color = Color(0, 0.8, 1, 1)  # Cyan
			"move":
				var axis = dragged_sphere.get_meta("axis")
				var colors = [Color(1, 0, 0, 1), Color(0, 1, 0, 1), Color(0, 0, 1, 1)]
				material.albedo_color = colors[axis]
			"rotate":
				var axis = dragged_sphere.get_meta("axis")
				var colors = [Color(1, 0, 0, 0.8), Color(0, 1, 0, 0.8), Color(0, 0, 1, 0.8)]
				material.albedo_color = colors[axis]
		
		dragged_sphere.material_override = material
	
	is_dragging = false
	dragged_sphere = null
	drag_initial_states.clear()
	
	# Emit signal so UI can update
	if selected_objects.size() > 0:
		objects_selected.emit(selected_objects)
	
	print("Stopped dragging gizmo")

func update_gizmo_drag(mouse_pos: Vector2):
	if not is_dragging or selected_objects.size() == 0 or not dragged_sphere:
		return
	
	var active_camera = get_viewport().get_camera_3d()
	if not active_camera:
		return
	
	var gizmo_type = dragged_sphere.get_meta("gizmo_type") if dragged_sphere.has_meta("gizmo_type") else "resize"
	
	match gizmo_type:
		"resize":
			update_resize_drag(mouse_pos)
		"move":
			update_move_drag(mouse_pos)
		"rotate":
			update_rotate_drag(mouse_pos)

func update_resize_drag(mouse_pos: Vector2):
	# Get increment value and resize mode from resize tool
	var increment = get_increment_value()
	var resize_both_directions = get_resize_both_directions()
	
	# Use the stored screen axis direction (calculated at drag start)
	# This prevents feedback loops from gizmo position updates
	var mouse_delta = mouse_pos - drag_start_mouse_pos
	var movement_along_axis = mouse_delta.dot(drag_screen_axis_dir)
	
	# Convert to scale change with much lower sensitivity
	var sensitivity = 0.002
	# Note: Don't multiply by drag_direction here - screen_axis_dir already encodes the direction
	var scale_delta_raw = movement_along_axis * sensitivity
	
	# If both directions mode, double the scale change (since it grows on both sides)
	if resize_both_directions:
		scale_delta_raw *= 2.0
	
	# Snap to increment
	var scale_delta = round(scale_delta_raw / increment) * increment
	
	# Apply scale change to all selected objects
	for state in drag_initial_states:
		var obj = state.object
		if not is_instance_valid(obj):
			continue
		
		var new_scale = state.scale
		new_scale[drag_axis] = max(0.1, state.scale[drag_axis] + scale_delta)
		obj.scale = new_scale
		
		# For single-direction resize, move the object so the opposite face stays in place
		if not resize_both_directions:
			# Get the object's AABB to calculate actual size
			var aabb = get_object_aabb(obj)
			if aabb:
				# Calculate how much the size changed in world units
				var old_size_world = state.scale[drag_axis] * aabb.size[drag_axis]
				var new_size_world = new_scale[drag_axis] * aabb.size[drag_axis]
				var size_change_world = new_size_world - old_size_world
				
				# Move the object by half the size change in the gizmo's direction
				# This keeps the opposite face fixed in place
				var position_offset = Vector3.ZERO
				position_offset[drag_axis] = size_change_world * 0.5 * drag_direction
				# Use the initial basis to maintain consistency
				obj.global_position = state.position + state.basis * position_offset
		else:
			# In both directions mode, keep center in place
			obj.global_position = state.position

func update_move_drag(mouse_pos: Vector2):
	# Move object along axis based on mouse movement
	var increment = get_move_increment_value()
	
	# Use the stored screen axis direction (calculated at drag start)
	# This prevents feedback loops from gizmo position updates
	var mouse_delta = mouse_pos - drag_start_mouse_pos
	var movement_along_axis = mouse_delta.dot(drag_screen_axis_dir)
	
	# Convert screen movement to world movement with much lower sensitivity
	var sensitivity = 0.002
	var move_delta_raw = movement_along_axis * sensitivity * drag_direction
	
	# Snap to increment
	var move_delta = round(move_delta_raw / increment) * increment
	
	# Apply movement to all selected objects
	for state in drag_initial_states:
		var obj = state.object
		if not is_instance_valid(obj):
			continue
		
		# Apply movement along each object's local axis direction
		var local_axis = Vector3.ZERO
		local_axis[drag_axis] = 1.0
		var world_axis = state.basis * local_axis
		var movement_vector = world_axis.normalized() * move_delta
		
		obj.global_position = state.position + movement_vector

func update_rotate_drag(mouse_pos: Vector2):
	# Rotate object around axis based on mouse movement
	var increment_deg = get_rotate_increment_value()
	var increment_rad = deg_to_rad(increment_deg)
	
	# Get active camera
	var active_camera = get_viewport().get_camera_3d()
	if not active_camera:
		return
	
	# Calculate rotation based on circular motion around the object center
	# Project object center to screen
	var object_center = drag_start_object_pos
	var center_screen = active_camera.unproject_position(object_center)
	
	# Get vectors from center to start and current mouse positions
	var start_vec = drag_start_mouse_pos - center_screen
	var current_vec = mouse_pos - center_screen
	
	# Calculate angle between vectors
	var rotation_amount = start_vec.angle_to(current_vec)
	
	# Determine rotation direction based on cross product sign
	# In 2D screen space, cross product gives us the perpendicular (z) component
	var cross = start_vec.x * current_vec.y - start_vec.y * current_vec.x
	if cross < 0:
		rotation_amount = -rotation_amount
	
	# Snap to increment
	var rotation_snapped = round(rotation_amount / increment_rad) * increment_rad
	
	# Apply rotation to all selected objects
	for state in drag_initial_states:
		var obj = state.object
		if not is_instance_valid(obj):
			continue
		
		# Apply rotation around the axis in the object's local space
		# Transform the axis from local to global space using the object's initial basis
		var local_axis_vector = Vector3.ZERO
		local_axis_vector[drag_axis] = 1.0
		var global_axis = state.basis * local_axis_vector
		global_axis = global_axis.normalized()
		
		# Calculate new rotation
		var rotation_delta = Basis(global_axis, rotation_snapped)
		obj.global_transform.basis = rotation_delta * state.basis

func get_increment_value() -> float:
	# Get the increment value from the resize tool
	var workspace = get_tree().current_scene
	if not workspace:
		return 0.1
	
	var resize_tool = workspace.get_node_or_null("UI/BuildUI/ResizeTool")
	if not resize_tool:
		return 0.1
	
	# Access the increment_length variable
	if resize_tool.has_method("get") and "increment_length" in resize_tool:
		return resize_tool.increment_length
	
	return 0.1

func get_move_increment_value() -> float:
	# Get the increment value from the move tool
	var workspace = get_tree().current_scene
	if not workspace:
		return 0.1
	
	var move_tool = workspace.get_node_or_null("UI/BuildUI/MoveTool")
	if not move_tool:
		return 0.1
	
	# Access the increment_length variable
	if move_tool.has_method("get") and "increment_length" in move_tool:
		return move_tool.increment_length
	
	return 0.1

func get_rotate_increment_value() -> float:
	# Get the increment value from the rotate tool
	var workspace = get_tree().current_scene
	if not workspace:
		return 15.0
	
	var rotate_tool = workspace.get_node_or_null("UI/BuildUI/RotateTool")
	if not rotate_tool:
		return 15.0
	
	# Access the increment_degrees variable
	if rotate_tool.has_method("get") and "increment_degrees" in rotate_tool:
		return rotate_tool.increment_degrees
	
	return 15.0

func get_resize_both_directions() -> bool:
	# Get the resize mode from the resize tool
	var workspace = get_tree().current_scene
	if not workspace:
		return false
	
	var resize_tool = workspace.get_node_or_null("UI/BuildUI/ResizeTool")
	if not resize_tool:
		return false
	
	# Access the resize_both_directions variable
	if resize_tool.has_method("get") and "resize_both_directions" in resize_tool:
		return resize_tool.resize_both_directions
	
	return false

# Natural object dragging functions
func raycast_from_mouse(mouse_pos: Vector2) -> Dictionary:
	var active_camera = get_viewport().get_camera_3d()
	if not active_camera:
		return {}
	
	var from = active_camera.project_ray_origin(mouse_pos)
	var to = from + active_camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	return space_state.intersect_ray(query)

func start_waiting_for_drag(mouse_pos: Vector2, hit_position: Vector3):
	is_waiting_for_drag = true
	object_drag_start_time = Time.get_ticks_msec() / 1000.0
	object_drag_start_mouse_pos = mouse_pos
	
	# Store initial positions for all selected objects
	drag_initial_states.clear()
	for obj in selected_objects:
		var state = {
			"object": obj,
			"position": obj.global_position
		}
		drag_initial_states.append(state)
	
	# Use first object for reference
	if selected_objects.size() > 0:
		object_drag_initial_pos = selected_objects[0].global_position
	
	# Store the hit position as our drag plane point (fixed depth)
	object_drag_plane_point = hit_position
	
	# Calculate offset from first object center to hit point
	if selected_objects.size() > 0:
		object_drag_offset = hit_position - selected_objects[0].global_position
	
	# Set up drag plane normal now (perpendicular to camera)
	var active_camera = get_viewport().get_camera_3d()
	if active_camera:
		object_drag_plane_normal = -active_camera.global_transform.basis.z
	
	print("Waiting for drag threshold...")

func check_drag_threshold(mouse_pos: Vector2):
	# Check if mouse moved beyond threshold distance
	var distance = mouse_pos.distance_to(object_drag_start_mouse_pos)
	if distance >= drag_threshold_distance:
		activate_object_drag()

func activate_object_drag():
	if is_object_dragging:
		return
	
	is_waiting_for_drag = false
	is_object_dragging = true
	
	# Drag plane was already set up in start_waiting_for_drag
	# We keep it fixed to maintain consistent depth
	
	# Hide selection markers during drag for cleaner visual
	var workspace = get_tree().current_scene
	if workspace.has_node("SelectionMarkers"):
		var markers = workspace.get_node("SelectionMarkers")
		markers.visible = false
	
	print("Started natural object dragging")

func update_object_drag(mouse_pos: Vector2):
	var active_camera = get_viewport().get_camera_3d()
	if not is_object_dragging or selected_objects.size() == 0 or not active_camera:
		return
	
	# Cast ray from mouse
	var from = active_camera.project_ray_origin(mouse_pos)
	var ray_dir = active_camera.project_ray_normal(mouse_pos)
	
	# Intersect ray with the FIXED drag plane (maintains depth)
	var intersection = plane_ray_intersection(object_drag_plane_point, object_drag_plane_normal, from, ray_dir)
	
	if intersection:
		# Calculate target position for the reference point
		var target_pos = intersection - object_drag_offset
		
		# Get increment from move tool and snap to grid
		var increment = get_move_increment_value()
		if increment > 0:
			target_pos.x = round(target_pos.x / increment) * increment
			target_pos.y = round(target_pos.y / increment) * increment
			target_pos.z = round(target_pos.z / increment) * increment
		
		# Calculate the movement delta
		var movement_delta = target_pos - object_drag_initial_pos
		
		# Apply movement to all selected objects
		for state in drag_initial_states:
			var obj = state.object
			if is_instance_valid(obj):
				obj.global_position = state.position + movement_delta

func stop_object_drag():
	if is_object_dragging:
		print("Stopped natural object dragging")
		
		# Show selection markers again
		var workspace = get_tree().current_scene
		if workspace.has_node("SelectionMarkers"):
			var markers = workspace.get_node("SelectionMarkers")
			markers.visible = true
	
	is_object_dragging = false
	is_waiting_for_drag = false

func plane_ray_intersection(plane_point: Vector3, plane_normal: Vector3, ray_origin: Vector3, ray_direction: Vector3) -> Variant:
	# Calculate intersection between ray and plane
	var denom = plane_normal.dot(ray_direction)
	
	# Check if ray is parallel to plane
	if abs(denom) < 0.0001:
		return null
	
	var t = (plane_point - ray_origin).dot(plane_normal) / denom
	
	# Check if intersection is behind the ray origin
	if t < 0:
		return null
	
	return ray_origin + ray_direction * t
