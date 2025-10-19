extends Control

# Material Tool for Build Tools
# Paint mode: Pick a material, then click on objects to apply it

@onready var material_dropdown = $MaterialDropdown
@onready var transparency_input = $IncrementLen
@onready var reflectance_input = $Reflectance

var selection_manager: Node = null
var paint_mode: bool = false  # True when material tool is active

# Material types
enum MaterialType {
	SLATE,
	WOOD,
	COBBLESTONE,
	ASPHALT,
	BRICK,
	CLAYROOFTILES,
	CONCRETE,
	CORRODEDMETAL,
	FABRIC,
	MARBLE,
	METAL,
	PAVEMENT,
	PEBBLE,
	ROCK,
	WOODPLANKS
}

var current_material: MaterialType = MaterialType.SLATE
var transparency: float = 0.0
var reflectance: float = 0.5

# Texture paths for different materials
var texture_paths = {
	MaterialType.SLATE: {
		"albedo": "res://src/assets/BrickMeshes/Slate/Brick_Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Slate/Brick_Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Slate/Brick_Part1_spec.png"
	},
	MaterialType.WOOD: {
		"albedo": "res://src/assets/BrickMeshes/Wood/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Wood/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Wood/Part1_spec.png"
	},
	MaterialType.COBBLESTONE: {
		"albedo": "res://src/assets/BrickMeshes/Cobblestone/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Cobblestone/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Cobblestone/Part1_spec.png"
	},
	MaterialType.ASPHALT: {
		"albedo": "res://src/assets/BrickMeshes/Asphalt/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Asphalt/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Asphalt/Part1_spec.png"
	},
	MaterialType.BRICK: {
		"albedo": "res://src/assets/BrickMeshes/Brick/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Brick/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Brick/Part1_spec.png"
	},
	MaterialType.CLAYROOFTILES: {
		"albedo": "res://src/assets/BrickMeshes/ClayRoofTiles/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/ClayRoofTiles/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/ClayRoofTiles/Part1_spec.png"
	},
	MaterialType.CONCRETE: {
		"albedo": "res://src/assets/BrickMeshes/Concrete/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Concrete/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Concrete/Part1_spec.png"
	},
	MaterialType.CORRODEDMETAL: {
		"albedo": "res://src/assets/BrickMeshes/CorrodedMetal/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/CorrodedMetal/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/CorrodedMetal/Part1_spec.png"
	},
	MaterialType.FABRIC: {
		"albedo": "res://src/assets/BrickMeshes/Fabric/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Fabric/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Fabric/Part1_spec.png"
	},
	MaterialType.MARBLE: {
		"albedo": "res://src/assets/BrickMeshes/Marble/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Marble/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Marble/Part1_spec.png"
	},
	MaterialType.METAL: {
		"albedo": "res://src/assets/BrickMeshes/Metal/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Metal/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Metal/Part1_spec.png"
	},
	MaterialType.PAVEMENT: {
		"albedo": "res://src/assets/BrickMeshes/Pavement/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Pavement/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Pavement/Part1_spec.png"
	},
	MaterialType.PEBBLE: {
		"albedo": "res://src/assets/BrickMeshes/Pebble/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Pebble/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Pebble/Part1_spec.png"
	},
	MaterialType.ROCK: {
		"albedo": "res://src/assets/BrickMeshes/Rock/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/Rock/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/Rock/Part1_spec.png"
	},
	MaterialType.WOODPLANKS: {
		"albedo": "res://src/assets/BrickMeshes/WoodPlanks/Part1_diff.png",
		"normal": "res://src/assets/BrickMeshes/WoodPlanks/Part1_nmap.png",
		"specular": "res://src/assets/BrickMeshes/WoodPlanks/Part1_spec.png"
	}
}

func _ready():
	# Populate material dropdown
	material_dropdown.clear()
	material_dropdown.add_item("Slate", MaterialType.SLATE)
	material_dropdown.add_item("Wood", MaterialType.WOOD)
	material_dropdown.add_item("Cobblestone", MaterialType.COBBLESTONE)
	material_dropdown.add_item("Asphalt", MaterialType.ASPHALT)
	material_dropdown.add_item("Brick", MaterialType.BRICK)
	material_dropdown.add_item("Clay Roof Tiles", MaterialType.CLAYROOFTILES)
	material_dropdown.add_item("Concrete", MaterialType.CONCRETE)
	material_dropdown.add_item("Corroded Metal", MaterialType.CORRODEDMETAL)
	material_dropdown.add_item("Fabric", MaterialType.FABRIC)
	material_dropdown.add_item("Marble", MaterialType.MARBLE)
	material_dropdown.add_item("Metal", MaterialType.METAL)
	material_dropdown.add_item("Pavement", MaterialType.PAVEMENT)
	material_dropdown.add_item("Pebble", MaterialType.PEBBLE)
	material_dropdown.add_item("Rock", MaterialType.ROCK)
	material_dropdown.add_item("Wood Planks", MaterialType.WOODPLANKS)
	
	# Set default selection
	material_dropdown.select(0)
	
	# Connect dropdown signal
	material_dropdown.item_selected.connect(_on_material_selected)
	
	# Connect input signals
	transparency_input.text_submitted.connect(_on_transparency_changed)
	reflectance_input.text_submitted.connect(_on_reflectance_changed)
	
	# Make sure inputs release focus after submission
	transparency_input.focus_exited.connect(func(): transparency_input.release_focus())
	reflectance_input.focus_exited.connect(func(): reflectance_input.release_focus())
	
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
		print("Material Paint Mode: ENABLED - Click on objects to apply material")
	else:
		print("Material Paint Mode: DISABLED")

func _input(event):
	"""Handle mouse clicks to apply material to objects in paint mode"""
	if not paint_mode:
		return
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			# Try to find object at mouse position
			var clicked_object = get_object_at_mouse(event.position)
			if clicked_object:
				# Apply material to the clicked object
				apply_material_to_object(clicked_object)
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
	"""Find the parent object that should have material applied (similar to selection logic)"""
	var current = node
	var found_part: Node3D = null
	
	while current:
		if current is Node3D:
			# Don't apply to gizmos/selection markers or their children
			if current.name == "SelectionMarkers" or is_child_of_node(current, "SelectionMarkers"):
				return null
			# Don't apply to the humanoid or its children
			if current.name == "humanoid" or is_child_of_node(current, "humanoid"):
				return null
			# Don't apply to the workspace root
			if current.name == "workspace":
				return null
			# Don't apply to UI or camera related nodes
			if current.name.contains("Lightning") or current.name.contains("Camera"):
				return null
			
			# Check if it's a valid object
			var parent = current.get_parent()
			if parent and (parent.name == "workspace" or parent.name == "InteractiveObjects"):
				# This is a top-level object (either a part or a group)
				found_part = current
				break
			# Check if current is inside a group
			elif parent and parent is Node3D and parent.name.begins_with("Group"):
				var grandparent = parent.get_parent()
				if grandparent and grandparent.name == "workspace":
					# Apply to the individual part, not the whole group
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

func _on_material_selected(index: int):
	# Get the material type from the selected item's ID
	current_material = material_dropdown.get_item_id(index) as MaterialType
	material_dropdown.release_focus()
	print("Material selected: ", MaterialType.keys()[current_material], " - Click on objects to apply")

func _on_transparency_changed(new_text: String):
	var value = new_text.to_float()
	transparency = clamp(value, 0.0, 1.0)
	transparency_input.text = str(transparency)
	transparency_input.release_focus()
	print("Transparency set to: ", transparency, " - Click on objects to apply")

func _on_reflectance_changed(new_text: String):
	var value = new_text.to_float()
	reflectance = clamp(value, 0.0, 1.0)
	reflectance_input.text = str(reflectance)
	reflectance_input.release_focus()
	print("Reflectance set to: ", reflectance, " - Click on objects to apply")

func apply_material_to_object(obj: Node3D):
	"""Apply the current material settings to a single object (paint mode)"""
	if not is_instance_valid(obj):
		return
	
	# Load textures for the selected material
	var textures = texture_paths[current_material]
	var total_meshes_changed = 0
	
	# Get all mesh instances (handles both single parts and groups)
	var mesh_instances = find_all_mesh_instances(obj)
	
	for mesh_instance in mesh_instances:
		if not mesh_instance:
			continue
		
		# Apply material to all surfaces
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
				# Load and apply textures
				if ResourceLoader.exists(textures["albedo"]):
					material.albedo_texture = load(textures["albedo"])
				
				if ResourceLoader.exists(textures["normal"]):
					material.normal_enabled = true
					material.normal_texture = load(textures["normal"])
				
				# Apply transparency
				if transparency > 0.0:
					material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
					material.albedo_color.a = 1.0 - transparency
				else:
					material.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					material.albedo_color.a = 1.0
				
				# Apply reflectance (using metallic as reflectance)
				material.metallic = reflectance
				material.roughness = 1.0 - reflectance * 0.5
				
				# Set the override material
				mesh_instance.set_surface_override_material(i, material)
		
		total_meshes_changed += 1
	
	print("Applied material '", MaterialType.keys()[current_material], 
		  "' (T:", transparency, ", R:", reflectance, ") to '", obj.name, "'")

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
