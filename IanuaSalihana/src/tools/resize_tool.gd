extends Control

# Resize Tool for Build Tools
# Handles resizing of selected objects through UI controls

@onready var single_direction_btn = $SingleDirection
@onready var both_directions_btn = $BothDirections
@onready var increment_input = $IncrementLen
@onready var size_x_input = $SizeX
@onready var size_y_input = $SizeY
@onready var size_z_input = $SizeZ

var selection_manager: Node = null
var selected_objects: Array[Node3D] = []  # All selected objects
var selected_object: Node3D = null  # Primary object for UI display
var resize_both_directions: bool = false
var increment_length: float = 0.1

# Face normals for resizing (in local space)
enum ResizeFace {
	NONE,
	POS_X,
	NEG_X,
	POS_Y,
	NEG_Y,
	POS_Z,
	NEG_Z
}

var active_resize_face: ResizeFace = ResizeFace.NONE

func _ready():
	# Connect button signals
	single_direction_btn.pressed.connect(_on_single_direction_pressed)
	both_directions_btn.pressed.connect(_on_both_directions_pressed)
	
	# Connect input signals
	increment_input.text_submitted.connect(_on_increment_changed)
	size_x_input.text_submitted.connect(_on_size_x_changed)
	size_y_input.text_submitted.connect(_on_size_y_changed)
	size_z_input.text_submitted.connect(_on_size_z_changed)
	
	# Make sure inputs release focus after submission
	increment_input.focus_exited.connect(func(): increment_input.release_focus())
	size_x_input.focus_exited.connect(func(): size_x_input.release_focus())
	size_y_input.focus_exited.connect(func(): size_y_input.release_focus())
	size_z_input.focus_exited.connect(func(): size_z_input.release_focus())
	
	# Find selection manager
	await get_tree().process_frame
	var workspace = get_tree().current_scene
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	if selection_manager:
		selection_manager.objects_selected.connect(_on_objects_selected)
		selection_manager.objects_deselected.connect(_on_objects_deselected)
	
	# Set default button states
	single_direction_btn.button_pressed = true

func _input(event):
	# Only handle input when this tool is visible (active)
	if not visible or not selected_object:
		return
	
	# Handle keyboard shortcuts for resizing
	if event is InputEventKey and event.pressed:
		var axis = -1
		var direction = 0
		
		# Arrow keys for X/Z resize
		if event.keycode == KEY_LEFT:
			axis = 0  # X axis
			direction = -1
		elif event.keycode == KEY_RIGHT:
			axis = 0  # X axis
			direction = 1
		elif event.keycode == KEY_UP:
			axis = 2  # Z axis
			direction = 1
		elif event.keycode == KEY_DOWN:
			axis = 2  # Z axis
			direction = -1
		# Page Up/Down for Y axis
		elif event.keycode == KEY_PAGEUP:
			axis = 1  # Y axis
			direction = 1
		elif event.keycode == KEY_PAGEDOWN:
			axis = 1  # Y axis
			direction = -1
		
		if axis >= 0:
			resize_object_on_axis(axis, direction * increment_length)
			update_size_display()

func _on_single_direction_pressed():
	resize_both_directions = false
	both_directions_btn.button_pressed = false
	single_direction_btn.release_focus()

func _on_both_directions_pressed():
	resize_both_directions = true
	single_direction_btn.button_pressed = false
	both_directions_btn.release_focus()

func _on_increment_changed(new_text: String):
	var value = new_text.to_float()
	if value > 0:
		increment_length = value
	else:
		increment_input.text = str(increment_length)
	increment_input.release_focus()

func _on_size_x_changed(new_text: String):
	if not selected_object:
		size_x_input.release_focus()
		return
	var value = new_text.to_float()
	if value > 0:
		set_object_size_axis(0, value)
	size_x_input.release_focus()

func _on_size_y_changed(new_text: String):
	if not selected_object:
		size_y_input.release_focus()
		return
	var value = new_text.to_float()
	if value > 0:
		set_object_size_axis(1, value)
	size_y_input.release_focus()

func _on_size_z_changed(new_text: String):
	if not selected_object:
		size_z_input.release_focus()
		return
	var value = new_text.to_float()
	if value > 0:
		set_object_size_axis(2, value)
	size_z_input.release_focus()

func _on_objects_selected(objects: Array):
	selected_objects = objects.duplicate()
	selected_object = objects[0] if objects.size() > 0 else null
	# Don't auto-show - let ToolManager control visibility
	update_size_display()

func _on_objects_deselected():
	selected_objects.clear()
	selected_object = null
	#visible = false
	clear_size_display()

func update_size_display():
	if not selected_object:
		return
	
	var size = get_object_size(selected_object)
	size_x_input.text = "%.2f" % size.x
	size_y_input.text = "%.2f" % size.y
	size_z_input.text = "%.2f" % size.z

func clear_size_display():
	size_x_input.text = ""
	size_y_input.text = ""
	size_z_input.text = ""

func get_object_size(obj: Node3D) -> Vector3:
	# Get the current size of the object
	if obj is MeshInstance3D:
		# For mesh instances, get the scale
		return obj.scale
	elif obj is CSGShape3D:
		return obj.scale
	elif obj.has_node("Brick") and obj.get_node("Brick") is MeshInstance3D:
		# Special case for brick scene
		var brick_mesh = obj.get_node("Brick")
		return brick_mesh.scale
	else:
		# Default to scale
		return obj.scale

func set_object_size(obj: Node3D, new_size: Vector3):
	# Set the size of the object
	if obj is MeshInstance3D:
		obj.scale = new_size
	elif obj is CSGShape3D:
		obj.scale = new_size
	elif obj.has_node("Brick") and obj.get_node("Brick") is MeshInstance3D:
		# Special case for brick scene
		var brick_mesh = obj.get_node("Brick")
		brick_mesh.scale = new_size
	else:
		obj.scale = new_size

func set_object_size_axis(axis: int, value: float):
	if not selected_object:
		return
	
	# Calculate the scale factor from the primary object
	var current_size = get_object_size(selected_object)
	var scale_factor = value / current_size[axis] if current_size[axis] != 0 else 1.0
	
	# Apply proportional scaling to all selected objects
	for obj in selected_objects:
		if is_instance_valid(obj):
			var obj_size = get_object_size(obj)
			obj_size[axis] *= scale_factor
			set_object_size(obj, obj_size)
	
	update_size_display()

func resize_object_on_axis(axis: int, amount: float):
	if selected_objects.size() == 0:
		return
	
	# Apply resize to all selected objects
	for obj in selected_objects:
		if not is_instance_valid(obj):
			continue
		
		var current_size = get_object_size(obj)
		
		if resize_both_directions:
			# Resize in both directions (symmetric)
			current_size[axis] += amount * 2
		else:
			# Resize in one direction
			current_size[axis] += amount
			# Also need to move the object to keep one side fixed
			var offset = Vector3.ZERO
			offset[axis] = amount / 2.0
			obj.position += obj.transform.basis * offset
		
		# Ensure size doesn't go negative
		current_size.x = max(0.1, current_size.x)
		current_size.y = max(0.1, current_size.y)
		current_size.z = max(0.1, current_size.z)
		
		set_object_size(obj, current_size)
	
	update_size_display()
