extends Control

# Color Tool for Build Tools
# Paint mode: Pick a color, then click on objects to paint them

var selection_manager: Node = null
var paint_mode: bool = false  # True when color tool is active
var camera: Camera3D = null

# Predefined ROBLOX-style color palette (RGB values 0-255)
var color_palette = [
	[163, 162, 165],
	[159, 161, 172],
	[202, 203, 209],
	[231, 231, 236],
	[248, 248, 248],
	[190, 104, 98],
	[91, 93, 105],
	[234, 184, 146],
	[136, 62, 62],
	[177, 229, 166],
	[199, 212, 228],
	[218, 134, 122],
	[160, 95, 53],
	[193, 190, 66],
	[245, 205, 48],
	[215, 197, 154],
	[180, 128, 255],
	[163, 75, 75],
	[193, 202, 222],
	[255, 255, 255],
	[0, 0, 0],
	[107, 50, 124],
	[75, 151, 75],
	[153, 0, 0],
	[27, 42, 53],
	[0, 32, 96],
	[0, 143, 156],
	[0, 87, 166],
	[218, 133, 65],
	[245, 205, 47],
	[164, 189, 71],
	[217, 0, 0],
	[196, 40, 28],
	[105, 64, 40],
	[13, 105, 172],
	[170, 85, 0],
	[123, 47, 123],
	[52, 142, 64],
	[218, 134, 122]
]

var current_color: Color = Color.WHITE
@onready var color_container: GridContainer = null
@onready var current_color_display: ColorRect = null

func _ready():
	# Create color grid container
	create_color_grid()
	
	# Find selection manager
	await get_tree().process_frame
	var workspace = get_tree().current_scene
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	# Set initial paint mode based on visibility
	paint_mode = visible
	
	# Connect visibility change to enable/disable paint mode
	visibility_changed.connect(_on_visibility_changed)

func _on_visibility_changed():
	"""Enable/disable paint mode when tool is shown/hidden"""
	paint_mode = visible
	if paint_mode:
		print("Color Paint Mode: ENABLED - Click on objects to paint them")
	else:
		print("Color Paint Mode: DISABLED")

func _input(event):
	"""Handle mouse clicks to paint objects in paint mode"""
	if not paint_mode:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Try to find object at mouse position
			var clicked_object = get_object_at_mouse(event.position)
			if clicked_object:
				# Apply color to the clicked object
				apply_color_to_object(clicked_object)
				# Mark input as handled to prevent selection
				get_viewport().set_input_as_handled()

func get_object_at_mouse(mouse_pos: Vector2) -> Node3D:
	"""Raycast from mouse to find object"""
	var active_camera = get_viewport().get_camera_3d()
	if not active_camera:
		return null
	
	var from = active_camera.project_ray_origin(mouse_pos)
	var to = from + active_camera.project_ray_normal(mouse_pos) * 1000.0
	
	var space_state = get_viewport().world_3d.direct_space_state
	var query = PhysicsRayQueryParameters3D.create(from, to)
	query.collide_with_areas = false
	query.collide_with_bodies = true
	
	var result = space_state.intersect_ray(query)
	if result and result.collider:
		return find_selectable_parent(result.collider)
	
	return null

func find_selectable_parent(node: Node) -> Node3D:
	"""Find the parent object that should be painted (similar to selection logic)"""
	var current = node
	var found_part: Node3D = null
	
	while current:
		if current is Node3D:
			# Don't paint gizmos/selection markers or their children
			if current.name == "SelectionMarkers" or is_child_of_node(current, "SelectionMarkers"):
				return null
			# Don't paint the humanoid or its children
			if current.name == "humanoid" or is_child_of_node(current, "humanoid"):
				return null
			# Don't paint the workspace root
			if current.name == "workspace":
				return null
			# Don't paint UI or camera related nodes
			if current.name.contains("Lightning") or current.name.contains("Camera"):
				return null
			
			# Check if it's a valid paintable object
			var parent = current.get_parent()
			if parent and (parent.name == "workspace" or parent.name == "InteractiveObjects"):
				# This is a top-level object (either a part or a group)
				found_part = current
				break
			# Check if current is inside a group
			elif parent and parent is Node3D and parent.name.begins_with("Group"):
				var grandparent = parent.get_parent()
				if grandparent and grandparent.name == "workspace":
					# Paint the individual part, not the whole group
					found_part = current
					break
		current = current.get_parent()
	
	# Check if the found part is locked
	if found_part and is_object_locked(found_part):
		return null
	
	return found_part

func is_child_of_node(node: Node, parent_name: String) -> bool:
	"""Check if node is a child of a node with given name"""
	var current = node.get_parent()
	while current:
		if current.name == parent_name:
			return true
		current = current.get_parent()
	return false

func is_object_locked(obj: Node3D) -> bool:
	"""Check if an object is locked"""
	var locked_value = obj.get("locked")
	if locked_value == null:
		var parent = obj.get_parent()
		if parent:
			locked_value = parent.get("locked")
	
	if locked_value != null and locked_value == true:
		return true
	return false

func create_color_grid():
	"""Create a grid of color buttons from the palette"""
	# Find or create the color container
	color_container = get_node_or_null("ColorGrid")
	
	if not color_container:
		# Create the grid container
		color_container = GridContainer.new()
		color_container.name = "ColorGrid"
		color_container.columns = 7  # 7 colors per row
		color_container.add_theme_constant_override("h_separation", 4)
		color_container.add_theme_constant_override("v_separation", 4)
		
		# Position it in the tool UI
		color_container.position = Vector2(8, 60)
		color_container.size = Vector2(200, 100)
		
		add_child(color_container)
	
	# Create current color display
	current_color_display = get_node_or_null("CurrentColorDisplay")
	if not current_color_display:
		current_color_display = ColorRect.new()
		current_color_display.name = "CurrentColorDisplay"
		current_color_display.custom_minimum_size = Vector2(80, 25)
		current_color_display.position = Vector2(110, 28)
		current_color_display.color = Color.WHITE
		add_child(current_color_display)
	
	# Generate color buttons
	for rgb in color_palette:
		var color = Color(rgb[0] / 255.0, rgb[1] / 255.0, rgb[2] / 255.0)
		create_color_button(color)

func create_color_button(color: Color):
	"""Create a single color button"""
	var button = Button.new()
	button.custom_minimum_size = Vector2(24, 24)
	
	# Create a StyleBoxFlat for the button background
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = color
	style_normal.border_width_left = 1
	style_normal.border_width_right = 1
	style_normal.border_width_top = 1
	style_normal.border_width_bottom = 1
	style_normal.border_color = Color(0.3, 0.3, 0.3, 1.0)
	
	var style_hover = StyleBoxFlat.new()
	style_hover.bg_color = color.lightened(0.2)
	style_hover.border_width_left = 2
	style_hover.border_width_right = 2
	style_hover.border_width_top = 2
	style_hover.border_width_bottom = 2
	style_hover.border_color = Color(1, 1, 1, 1.0)
	
	var style_pressed = StyleBoxFlat.new()
	style_pressed.bg_color = color.darkened(0.1)
	style_pressed.border_width_left = 2
	style_pressed.border_width_right = 2
	style_pressed.border_width_top = 2
	style_pressed.border_width_bottom = 2
	style_pressed.border_color = Color(1, 1, 1, 1.0)
	
	button.add_theme_stylebox_override("normal", style_normal)
	button.add_theme_stylebox_override("hover", style_hover)
	button.add_theme_stylebox_override("pressed", style_pressed)
	
	# Connect the button press to apply color
	button.pressed.connect(func(): _on_color_selected(color, button))
	
	color_container.add_child(button)

func _on_color_selected(color: Color, button: Button):
	"""Handle color selection"""
	current_color = color
	if current_color_display:
		current_color_display.color = color
	button.release_focus()
	print("Paint color selected: RGB(", int(color.r * 255), ", ", int(color.g * 255), ", ", int(color.b * 255), ") - Click on objects to paint them")

func apply_color_to_object(obj: Node3D):
	"""Apply the current color to a single object (paint mode)"""
	if not is_instance_valid(obj):
		return
	
	var total_meshes_changed = 0
	
	# Get all mesh instances (handles both single parts and groups)
	var mesh_instances = find_all_mesh_instances(obj)
	
	for mesh_instance in mesh_instances:
		if not mesh_instance:
			continue
		
		# Apply color to all surfaces
		for i in range(mesh_instance.mesh.get_surface_count()):
			var material = mesh_instance.get_surface_override_material(i)
			
			# If no override material, get the default material and duplicate it
			if not material:
				material = mesh_instance.mesh.surface_get_material(i)
				if material:
					material = material.duplicate()
				else:
					material = StandardMaterial3D.new()
			else:
				material = material.duplicate()
			
			if material is StandardMaterial3D:
				# Preserve the alpha channel
				var alpha = material.albedo_color.a
				material.albedo_color = Color(current_color.r, current_color.g, current_color.b, alpha)
				
				# Set the override material
				mesh_instance.set_surface_override_material(i, material)
		
		total_meshes_changed += 1
	
	print("Painted '", obj.name, "' with color RGB(", int(current_color.r * 255), ", ", int(current_color.g * 255), ", ", int(current_color.b * 255), ")")

func find_mesh_instance(node: Node) -> MeshInstance3D:
	"""Recursively find a MeshInstance3D in the node hierarchy"""
	if node is MeshInstance3D:
		return node
	
	for child in node.get_children():
		if child is MeshInstance3D:
			return child
		var result = find_mesh_instance(child)
		if result:
			return result
	
	return null

func find_all_mesh_instances(node: Node) -> Array[MeshInstance3D]:
	"""Recursively find ALL MeshInstance3D nodes in the hierarchy (for groups)"""
	var meshes: Array[MeshInstance3D] = []
	
	if node is MeshInstance3D:
		meshes.append(node)
		return meshes
	
	for child in node.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
		else:
			# Recursively search children
			var child_meshes = find_all_mesh_instances(child)
			meshes.append_array(child_meshes)
	
	return meshes

func get_first_material(mesh_instance: MeshInstance3D) -> Material:
	"""Get the first material from a mesh instance"""
	if not mesh_instance or not mesh_instance.mesh:
		return null
	
	# Try override material first
	var material = mesh_instance.get_surface_override_material(0)
	if material:
		return material
	
	# Otherwise get default material
	if mesh_instance.mesh.get_surface_count() > 0:
		return mesh_instance.mesh.surface_get_material(0)
	
	return null
