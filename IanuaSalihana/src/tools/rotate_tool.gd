extends Control

# Rotate Tool for Build Tools
# Handles rotating selected objects with different pivot modes

@onready var global_btn = $Global
@onready var local_btn = $Local
@onready var last_btn = $Last
@onready var increment_input = $IncrementLen
@onready var rotation_x_input = $RotationX
@onready var rotation_y_input = $RotationY
@onready var rotation_z_input = $RotationZ

var selection_manager: Node = null
var selected_objects: Array[Node3D] = []  # All selected objects
var selected_object: Node3D = null  # Primary object for UI display
var increment_degrees: float = 15.0

# Pivot modes
enum PivotMode {
	GLOBAL,  # Rotate around world axes
	LOCAL,   # Rotate around object's local axes
	LAST     # Use last selected object's axes
}

var current_pivot_mode: PivotMode = PivotMode.GLOBAL
var last_object_transform: Transform3D = Transform3D.IDENTITY

func _ready():
	# Connect button signals
	global_btn.pressed.connect(_on_global_pressed)
	local_btn.pressed.connect(_on_local_pressed)
	last_btn.pressed.connect(_on_last_pressed)
	
	# Connect input signals
	increment_input.text_submitted.connect(_on_increment_changed)
	rotation_x_input.text_submitted.connect(_on_rotation_x_changed)
	rotation_y_input.text_submitted.connect(_on_rotation_y_changed)
	rotation_z_input.text_submitted.connect(_on_rotation_z_changed)
	
	# Make sure inputs release focus after submission
	increment_input.focus_exited.connect(func(): increment_input.release_focus())
	rotation_x_input.focus_exited.connect(func(): rotation_x_input.release_focus())
	rotation_y_input.focus_exited.connect(func(): rotation_y_input.release_focus())
	rotation_z_input.focus_exited.connect(func(): rotation_z_input.release_focus())
	
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
	
	# Handle keyboard shortcuts for rotating
	if event is InputEventKey and event.pressed:
		var rotation_axis = Vector3.ZERO
		var rotation_amount = deg_to_rad(increment_degrees)
		
		# Determine rotation axis based on key
		# Q/E for X axis (Roll)
		# R/F for Y axis (Yaw)
		# T/G for Z axis (Pitch)
		if event.keycode == KEY_Q:
			rotation_axis = Vector3.RIGHT
			rotation_amount = -rotation_amount
		elif event.keycode == KEY_E:
			rotation_axis = Vector3.RIGHT
		elif event.keycode == KEY_R:
			rotation_axis = Vector3.UP
		elif event.keycode == KEY_F:
			rotation_axis = Vector3.UP
			rotation_amount = -rotation_amount
		elif event.keycode == KEY_T:
			rotation_axis = Vector3.FORWARD
		elif event.keycode == KEY_G:
			rotation_axis = Vector3.FORWARD
			rotation_amount = -rotation_amount
		
		if rotation_axis != Vector3.ZERO:
			rotate_object(rotation_axis, rotation_amount)
			update_rotation_display()

func _on_global_pressed():
	current_pivot_mode = PivotMode.GLOBAL
	local_btn.button_pressed = false
	last_btn.button_pressed = false
	global_btn.release_focus()
	print("Pivot mode: Global")

func _on_local_pressed():
	current_pivot_mode = PivotMode.LOCAL
	global_btn.button_pressed = false
	last_btn.button_pressed = false
	local_btn.release_focus()
	print("Pivot mode: Local")

func _on_last_pressed():
	current_pivot_mode = PivotMode.LAST
	global_btn.button_pressed = false
	local_btn.button_pressed = false
	last_btn.release_focus()
	print("Pivot mode: Last")

func _on_increment_changed(new_text: String):
	var value = new_text.to_float()
	if value > 0:
		increment_degrees = value
	else:
		increment_input.text = str(increment_degrees)
	increment_input.release_focus()

func _on_rotation_x_changed(new_text: String):
	if not selected_object:
		rotation_x_input.release_focus()
		return
	var value = deg_to_rad(new_text.to_float())
	set_object_rotation_axis(0, value)
	rotation_x_input.release_focus()

func _on_rotation_y_changed(new_text: String):
	if not selected_object:
		rotation_y_input.release_focus()
		return
	var value = deg_to_rad(new_text.to_float())
	set_object_rotation_axis(1, value)
	rotation_y_input.release_focus()

func _on_rotation_z_changed(new_text: String):
	if not selected_object:
		rotation_z_input.release_focus()
		return
	var value = deg_to_rad(new_text.to_float())
	set_object_rotation_axis(2, value)
	rotation_z_input.release_focus()

func _on_objects_selected(objects: Array):
	# Save the last object's transform before switching
	if selected_object:
		last_object_transform = selected_object.global_transform
	
	selected_objects = objects.duplicate()
	selected_object = objects[0] if objects.size() > 0 else null
	# Don't auto-show - let ToolManager control visibility
	update_rotation_display()

func _on_objects_deselected():
	# Save transform before deselecting
	if selected_object:
		last_object_transform = selected_object.global_transform
	
	selected_objects.clear()
	selected_object = null
	clear_rotation_display()

func update_rotation_display():
	if not selected_object:
		return
	
	# Get rotation in degrees
	var rot = selected_object.rotation_degrees
	rotation_x_input.text = "%.2f" % rot.x
	rotation_y_input.text = "%.2f" % rot.y
	rotation_z_input.text = "%.2f" % rot.z

func clear_rotation_display():
	rotation_x_input.text = ""
	rotation_y_input.text = ""
	rotation_z_input.text = ""

func rotate_object(axis: Vector3, angle_radians: float):
	if selected_objects.size() == 0:
		return
	
	# Apply rotation to all selected objects
	for obj in selected_objects:
		if not is_instance_valid(obj):
			continue
		
		# Transform the rotation axis based on pivot mode
		match current_pivot_mode:
			PivotMode.GLOBAL:
				# Rotate around world axis
				var current_transform = obj.global_transform
				var rotation = Basis(axis, angle_radians)
				obj.global_transform.basis = rotation * current_transform.basis
				
			PivotMode.LOCAL:
				# Rotate around object's local axis
				obj.rotate(axis, angle_radians)
				
			PivotMode.LAST:
				# Rotate around last object's axes in global space
				var last_axis = last_object_transform.basis * axis
				last_axis = last_axis.normalized()
				var current_transform = obj.global_transform
				var rotation = Basis(last_axis, angle_radians)
				obj.global_transform.basis = rotation * current_transform.basis
	
	update_rotation_display()

func set_object_rotation_axis(axis: int, value_radians: float):
	if not selected_object:
		return
	
	# Calculate the delta from the primary object's current rotation
	var rot = selected_object.rotation
	var delta = value_radians - rot[axis]
	
	# Apply the delta to all selected objects
	for obj in selected_objects:
		if is_instance_valid(obj):
			var obj_rot = obj.rotation
			obj_rot[axis] += delta
			obj.rotation = obj_rot
	
	update_rotation_display()

func set_object_rotation(new_rotation: Vector3):
	if not selected_object:
		return
	
	# Calculate the delta from the primary object's current rotation
	var delta = new_rotation - selected_object.rotation
	
	# Apply the delta to all selected objects
	for obj in selected_objects:
		if is_instance_valid(obj):
			obj.rotation += delta
	
	update_rotation_display()
