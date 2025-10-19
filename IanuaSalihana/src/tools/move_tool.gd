extends Control

# Move Tool for Build Tools
# Handles moving selected objects with different axis modes

@onready var global_btn = $Global
@onready var local_btn = $Local
@onready var last_btn = $Last
@onready var increment_input = $IncrementLen
@onready var position_x_input = $PositionX
@onready var position_y_input = $PositionY
@onready var position_z_input = $PositionZ

var selection_manager: Node = null
var selected_objects: Array[Node3D] = []  # All selected objects
var selected_object: Node3D = null  # Primary object for UI display
var increment_length: float = 0.1

# Axis modes
enum AxisMode {
	GLOBAL,  # World space axes
	LOCAL,   # Object's local axes
	LAST     # Last selected object's axes
}

var current_axis_mode: AxisMode = AxisMode.GLOBAL
var last_object_transform: Transform3D = Transform3D.IDENTITY

func _ready():
	# Connect button signals
	global_btn.pressed.connect(_on_global_pressed)
	local_btn.pressed.connect(_on_local_pressed)
	last_btn.pressed.connect(_on_last_pressed)
	
	# Connect input signals
	increment_input.text_submitted.connect(_on_increment_changed)
	position_x_input.text_submitted.connect(_on_position_x_changed)
	position_y_input.text_submitted.connect(_on_position_y_changed)
	position_z_input.text_submitted.connect(_on_position_z_changed)
	
	# Make sure inputs release focus after submission
	increment_input.focus_exited.connect(func(): increment_input.release_focus())
	position_x_input.focus_exited.connect(func(): position_x_input.release_focus())
	position_y_input.focus_exited.connect(func(): position_y_input.release_focus())
	position_z_input.focus_exited.connect(func(): position_z_input.release_focus())
	
	# Find selection manager
	await get_tree().process_frame
	var workspace = get_tree().current_scene
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	if selection_manager:
		selection_manager.objects_selected.connect(_on_objects_selected)
		selection_manager.objects_deselected.connect(_on_objects_deselected)
	
	# Set default button state
	global_btn.button_pressed = true

func _input(event):
	# Only handle input when this tool is visible (active)
	if not visible or not selected_object:
		return
	
	# Handle keyboard shortcuts for moving
	if event is InputEventKey and event.pressed:
		var axis = -1
		var direction = 0
		
		# Get the current axis system
		var axis_x = Vector3.RIGHT
		var axis_y = Vector3.UP
		var axis_z = Vector3.FORWARD
		
		match current_axis_mode:
			AxisMode.GLOBAL:
				# Use world axes (already set above)
				pass
			AxisMode.LOCAL:
				# Use object's local axes
				if selected_object:
					axis_x = selected_object.global_transform.basis.x.normalized()
					axis_y = selected_object.global_transform.basis.y.normalized()
					axis_z = selected_object.global_transform.basis.z.normalized()
			AxisMode.LAST:
				# Use last object's axes
				axis_x = last_object_transform.basis.x.normalized()
				axis_y = last_object_transform.basis.y.normalized()
				axis_z = last_object_transform.basis.z.normalized()
		
		# Arrow keys for X/Z movement
		var move_vector = Vector3.ZERO
		if event.keycode == KEY_LEFT:
			move_vector = -axis_x * increment_length
		elif event.keycode == KEY_RIGHT:
			move_vector = axis_x * increment_length
		elif event.keycode == KEY_UP:
			move_vector = axis_z * increment_length
		elif event.keycode == KEY_DOWN:
			move_vector = -axis_z * increment_length
		# Page Up/Down for Y axis
		elif event.keycode == KEY_PAGEUP:
			move_vector = axis_y * increment_length
		elif event.keycode == KEY_PAGEDOWN:
			move_vector = -axis_y * increment_length
		
		if move_vector != Vector3.ZERO:
			move_object(move_vector)
			update_position_display()

func _on_global_pressed():
	current_axis_mode = AxisMode.GLOBAL
	local_btn.button_pressed = false
	last_btn.button_pressed = false
	global_btn.release_focus()
	print("Axis mode: Global")

func _on_local_pressed():
	current_axis_mode = AxisMode.LOCAL
	global_btn.button_pressed = false
	last_btn.button_pressed = false
	local_btn.release_focus()
	print("Axis mode: Local")

func _on_last_pressed():
	current_axis_mode = AxisMode.LAST
	global_btn.button_pressed = false
	local_btn.button_pressed = false
	last_btn.release_focus()
	print("Axis mode: Last")

func _on_increment_changed(new_text: String):
	var value = new_text.to_float()
	if value > 0:
		increment_length = value
	else:
		increment_input.text = str(increment_length)
	increment_input.release_focus()

func _on_position_x_changed(new_text: String):
	if not selected_object:
		position_x_input.release_focus()
		return
	var value = new_text.to_float()
	set_object_position_axis(0, value)
	position_x_input.release_focus()

func _on_position_y_changed(new_text: String):
	if not selected_object:
		position_y_input.release_focus()
		return
	var value = new_text.to_float()
	set_object_position_axis(1, value)
	position_y_input.release_focus()

func _on_position_z_changed(new_text: String):
	if not selected_object:
		position_z_input.release_focus()
		return
	var value = new_text.to_float()
	set_object_position_axis(2, value)
	position_z_input.release_focus()

func _on_objects_selected(objects: Array):
	# Save the last object's transform before switching
	if selected_object:
		last_object_transform = selected_object.global_transform
	
	selected_objects = objects.duplicate()
	selected_object = objects[0] if objects.size() > 0 else null
	# Don't auto-show - let ToolManager control visibility
	update_position_display()

func _on_objects_deselected():
	# Save transform before deselecting
	if selected_object:
		last_object_transform = selected_object.global_transform
	
	selected_objects.clear()
	selected_object = null
	clear_position_display()

func update_position_display():
	if not selected_object:
		return
	
	var pos = selected_object.global_position
	position_x_input.text = "%.2f" % pos.x
	position_y_input.text = "%.2f" % pos.y
	position_z_input.text = "%.2f" % pos.z

func clear_position_display():
	position_x_input.text = ""
	position_y_input.text = ""
	position_z_input.text = ""

func move_object(offset: Vector3):
	if selected_objects.size() == 0:
		return
	
	# Move all selected objects
	for obj in selected_objects:
		if is_instance_valid(obj):
			obj.global_position += offset
	
	update_position_display()

func set_object_position_axis(axis: int, value: float):
	if not selected_object:
		return
	
	# Calculate the delta from the primary object's current position
	var pos = selected_object.global_position
	var delta = value - pos[axis]
	
	# Apply the delta to all selected objects
	for obj in selected_objects:
		if is_instance_valid(obj):
			var obj_pos = obj.global_position
			obj_pos[axis] += delta
			obj.global_position = obj_pos
	
	update_position_display()

func set_object_position(new_position: Vector3):
	if not selected_object:
		return
	
	# Calculate the delta from the primary object's current position
	var delta = new_position - selected_object.global_position
	
	# Apply the delta to all selected objects
	for obj in selected_objects:
		if is_instance_valid(obj):
			obj.global_position += delta
	
	update_position_display()
