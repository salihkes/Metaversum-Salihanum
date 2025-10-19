extends Node

# Tool Manager for Build Tools
# Manages switching between Move, Resize, and Rotate tools

signal tool_changed(tool_type: ToolType)

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

var current_tool: ToolType = ToolType.NONE
var selection_manager: Node = null

# Tool UI references
var move_tool_ui: Control = null
var resize_tool_ui: Control = null
var rotate_tool_ui: Control = null
var material_tool_ui: Control = null
var new_part_tool_ui: Control = null
var color_tool_ui: Control = null
var group_tool_ui: Control = null

# Backpack button references
var move_button: Button = null
var resize_button: Button = null
var rotate_button: Button = null
var material_button: Button = null
var new_part_button: Button = null
var color_button: Button = null
var group_button: Button = null

# Clipboard for copy/paste
var clipboard_objects: Array[Dictionary] = []

# Undo/Redo system
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var max_undo_stack_size: int = 50

func _ready():
	# Wait for scene to be ready
	await get_tree().process_frame
	
	var workspace = get_tree().current_scene
	
	# Get tool UI references
	move_tool_ui = workspace.get_node_or_null("UI/BuildUI/MoveTool")
	resize_tool_ui = workspace.get_node_or_null("UI/BuildUI/ResizeTool")
	rotate_tool_ui = workspace.get_node_or_null("UI/BuildUI/RotateTool")
	material_tool_ui = workspace.get_node_or_null("UI/BuildUI/MaterialTool")
	new_part_tool_ui = workspace.get_node_or_null("UI/BuildUI/NewPartTool")
	color_tool_ui = workspace.get_node_or_null("UI/BuildUI/ColorTool")
	group_tool_ui = workspace.get_node_or_null("UI/BuildUI/GroupTool")
	
	# Get backpack button references
	move_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/MoveUI/Button")
	resize_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/ResizeUI/Button")
	rotate_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/RotateUI/Button")
	material_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/MaterialUI/Button")
	new_part_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/NewPartUI/Button")
	color_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/ColorUI/Button")
	group_button = workspace.get_node_or_null("UI/BackpackUI/HBoxContainer/GroupUI/Button")
	
	# Get selection manager reference
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	# Connect button signals
	if move_button:
		move_button.pressed.connect(_on_move_button_pressed)
	if resize_button:
		resize_button.pressed.connect(_on_resize_button_pressed)
	if rotate_button:
		rotate_button.pressed.connect(_on_rotate_button_pressed)
	if material_button:
		material_button.pressed.connect(_on_material_button_pressed)
	if new_part_button:
		new_part_button.pressed.connect(_on_new_part_button_pressed)
	if color_button:
		color_button.pressed.connect(_on_color_button_pressed)
	if group_button:
		group_button.pressed.connect(_on_group_button_pressed)
	
	# No tool selected by default

func _unhandled_input(event):
	if event is InputEventKey and event.pressed and not event.echo:
		var ctrl_pressed = event.ctrl_pressed
		var shift_pressed = event.shift_pressed
		
		# Check if user is typing in a text field
		var focused_control = get_viewport().gui_get_focus_owner()
		if focused_control is LineEdit or focused_control is TextEdit:
			return  # Don't process shortcuts while typing
		
		# Tool switching with number keys (1-7)
		if not ctrl_pressed and not shift_pressed:
			match event.keycode:
				KEY_1:
					set_tool(ToolType.MOVE)
					get_viewport().set_input_as_handled()
				KEY_2:
					set_tool(ToolType.ROTATE)
					get_viewport().set_input_as_handled()
				KEY_3:
					set_tool(ToolType.RESIZE)
					get_viewport().set_input_as_handled()
				KEY_4:
					set_tool(ToolType.MATERIAL)
					get_viewport().set_input_as_handled()
				KEY_5:
					set_tool(ToolType.NEW_PART)
					get_viewport().set_input_as_handled()
				KEY_6:
					set_tool(ToolType.COLOR)
					get_viewport().set_input_as_handled()
				KEY_7:
					set_tool(ToolType.GROUP)
					get_viewport().set_input_as_handled()
		
		# CTRL + Shortcuts
		if ctrl_pressed and not shift_pressed:
			match event.keycode:
				KEY_D:
					duplicate_selected()
					get_viewport().set_input_as_handled()
				KEY_C:
					copy_selected()
					get_viewport().set_input_as_handled()
				KEY_X:
					cut_selected()
					get_viewport().set_input_as_handled()
				KEY_V:
					paste_clipboard()
					get_viewport().set_input_as_handled()
				KEY_Z:
					undo()
					get_viewport().set_input_as_handled()
				KEY_Y:
					redo()
					get_viewport().set_input_as_handled()
				KEY_A:
					select_all()
					get_viewport().set_input_as_handled()
		
		# CTRL + SHIFT + Shortcuts
		if ctrl_pressed and shift_pressed:
			match event.keycode:
				KEY_Z:
					redo()
					get_viewport().set_input_as_handled()

func _on_move_button_pressed():
	if current_tool == ToolType.MOVE:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.MOVE)

func _on_resize_button_pressed():
	if current_tool == ToolType.RESIZE:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.RESIZE)

func _on_rotate_button_pressed():
	if current_tool == ToolType.ROTATE:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.ROTATE)

func _on_material_button_pressed():
	if current_tool == ToolType.MATERIAL:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.MATERIAL)

func _on_new_part_button_pressed():
	if current_tool == ToolType.NEW_PART:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.NEW_PART)

func _on_color_button_pressed():
	if current_tool == ToolType.COLOR:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.COLOR)

func _on_group_button_pressed():
	if current_tool == ToolType.GROUP:
		set_tool(ToolType.NONE)  # Toggle off
	else:
		set_tool(ToolType.GROUP)

func set_tool(tool: ToolType):
	current_tool = tool
	
	# Update UI visibility
	if move_tool_ui:
		move_tool_ui.visible = (tool == ToolType.MOVE)
	if resize_tool_ui:
		resize_tool_ui.visible = (tool == ToolType.RESIZE)
	if rotate_tool_ui:
		rotate_tool_ui.visible = (tool == ToolType.ROTATE)
	if material_tool_ui:
		material_tool_ui.visible = (tool == ToolType.MATERIAL)
	if new_part_tool_ui:
		new_part_tool_ui.visible = (tool == ToolType.NEW_PART)
	if color_tool_ui:
		color_tool_ui.visible = (tool == ToolType.COLOR)
	if group_tool_ui:
		group_tool_ui.visible = (tool == ToolType.GROUP)
	
	# Update button states (visual feedback)
	update_button_states()
	
	# Notify selection manager to update gizmos
	if selection_manager:
		selection_manager.set_tool_mode(tool)
	
	# Emit signal
	tool_changed.emit(tool)
	
	if tool == ToolType.NONE:
		print("Tool deselected")
	else:
		print("Tool changed to: ", ToolType.keys()[tool])

func update_button_states():
	# You could change button colors or styles here to show active tool
	# For now, we'll just use the visible tool UI as indicator
	pass

func get_current_tool() -> ToolType:
	return current_tool

# Clipboard operations
func copy_selected():
	"""Copy selected objects to clipboard"""
	if not selection_manager:
		return
	
	var selected_objects = selection_manager.selected_objects
	if selected_objects.is_empty():
		print("No objects selected to copy")
		return
	
	clipboard_objects.clear()
	
	for obj in selected_objects:
		if obj is Node3D:
			var obj_data = {
				"scene_path": obj.scene_file_path if obj.scene_file_path else "",
				"name": obj.name,
				"position": obj.global_position,
				"rotation": obj.global_rotation,
				"scale": obj.scale,
				"transform": obj.global_transform,
				"properties": {}
			}
			
			# Copy custom properties (like color, material, locked state, etc.)
			for property in obj.get_property_list():
				if property.usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
					var prop_name = property.name
					obj_data.properties[prop_name] = obj.get(prop_name)
			
			clipboard_objects.append(obj_data)
	
	print("Copied ", clipboard_objects.size(), " object(s) to clipboard (position, rotation, scale preserved)")

func cut_selected():
	"""Cut selected objects (copy + delete)"""
	if not selection_manager:
		return
	
	var selected_objects = selection_manager.selected_objects
	if selected_objects.is_empty():
		print("No objects selected to cut")
		return
	
	# First copy to clipboard
	copy_selected()
	
	# Then delete
	save_undo_state("Cut objects")
	selection_manager.delete_selected_objects()
	
	print("Cut ", clipboard_objects.size(), " object(s)")

func paste_clipboard():
	"""Paste objects from clipboard"""
	if clipboard_objects.is_empty():
		print("Clipboard is empty")
		return
	
	var workspace = get_tree().current_scene
	if not workspace:
		return
	
	save_undo_state("Paste objects")
	
	var pasted_objects: Array[Node3D] = []
	
	for obj_data in clipboard_objects:
		var new_obj: Node3D = null
		
		# Try to instantiate from scene path
		if obj_data.scene_path and obj_data.scene_path != "":
			var scene = load(obj_data.scene_path)
			if scene:
				new_obj = scene.instantiate()
		
		# If no scene path, create a generic Node3D
		if not new_obj:
			new_obj = Node3D.new()
		
		# Add to workspace first
		workspace.add_child(new_obj)
		new_obj.owner = workspace
		
		# Set name
		new_obj.name = obj_data.name + "_copy"
		
		# Restore exact position, rotation, and scale (no offset)
		new_obj.global_position = obj_data.position
		new_obj.global_rotation = obj_data.rotation
		new_obj.scale = obj_data.scale
		
		# Restore custom properties (like material, color, etc.)
		for prop_name in obj_data.properties:
			if prop_name in new_obj:
				new_obj.set(prop_name, obj_data.properties[prop_name])
		
		pasted_objects.append(new_obj)
	
	# Select the pasted objects
	if selection_manager and not pasted_objects.is_empty():
		selection_manager.select_objects(pasted_objects)
	
	print("Pasted ", pasted_objects.size(), " object(s) at exact original positions")

func duplicate_selected():
	"""Duplicate selected objects in place"""
	if not selection_manager:
		return
	
	var selected_objects = selection_manager.selected_objects
	if selected_objects.is_empty():
		print("No objects selected to duplicate")
		return
	
	var workspace = get_tree().current_scene
	if not workspace:
		return
	
	save_undo_state("Duplicate objects")
	
	var duplicated_objects: Array[Node3D] = []
	
	for obj in selected_objects:
		if obj is Node3D:
			# Duplicate the object (this preserves all properties)
			var duplicate = obj.duplicate()
			
			# Store original transform before adding to scene
			var original_pos = obj.global_position
			var original_rot = obj.global_rotation
			var original_scale = obj.scale
			
			# Add to workspace
			workspace.add_child(duplicate)
			duplicate.owner = workspace
			
			# Restore exact position, rotation and scale (no offset)
			duplicate.global_position = original_pos
			duplicate.global_rotation = original_rot
			duplicate.scale = original_scale
			
			duplicated_objects.append(duplicate)
	
	# Select the duplicated objects
	if not duplicated_objects.is_empty():
		selection_manager.select_objects(duplicated_objects)
	
	print("Duplicated ", duplicated_objects.size(), " object(s) at exact original positions")

func select_all():
	"""Select all selectable objects in the workspace"""
	if not selection_manager:
		return
	
	var workspace = get_tree().current_scene
	if not workspace:
		return
	
	var all_objects: Array[Node3D] = []
	
	# Get all direct children of workspace that are Node3D and not excluded
	for child in workspace.get_children():
		if child is Node3D and child.name != "humanoid" and child.name != "Lightning" and child.name != "InteractiveObjects" and child.name != "SelectionMarkers" and child.name != "FreeCamera":
			# Check if object is not locked
			var locked_value = child.get("locked")
			if locked_value == null or locked_value != true:
				all_objects.append(child)
	
	# Also check InteractiveObjects if it exists
	if workspace.has_node("InteractiveObjects"):
		var io_node = workspace.get_node("InteractiveObjects")
		for child in io_node.get_children():
			if child is Node3D:
				var locked_value = child.get("locked")
				if locked_value == null or locked_value != true:
					all_objects.append(child)
	
	if not all_objects.is_empty():
		selection_manager.select_objects(all_objects)
		print("Selected all ", all_objects.size(), " object(s)")
	else:
		print("No objects to select")

# Undo/Redo system
func save_undo_state(action_name: String):
	"""Save the current state for undo"""
	var workspace = get_tree().current_scene
	if not workspace:
		return
	
	var state = {
		"action": action_name,
		"timestamp": Time.get_ticks_msec(),
		"objects": []
	}
	
	# Save state of all objects in workspace
	for child in workspace.get_children():
		if child is Node3D and child.name != "humanoid" and child.name != "Lightning" and child.name != "SelectionMarkers" and child.name != "FreeCamera":
			var obj_state = {
				"path": child.get_path(),
				"transform": child.global_transform,
				"scale": child.scale,
				"exists": true
			}
			state.objects.append(obj_state)
	
	undo_stack.append(state)
	
	# Limit stack size
	if undo_stack.size() > max_undo_stack_size:
		undo_stack.pop_front()
	
	# Clear redo stack when new action is performed
	redo_stack.clear()
	
	print("Saved undo state: ", action_name)

func undo():
	"""Undo the last action"""
	if undo_stack.is_empty():
		print("Nothing to undo")
		return
	
	var current_state = capture_current_state()
	redo_stack.append(current_state)
	
	var previous_state = undo_stack.pop_back()
	restore_state(previous_state)
	
	print("Undid: ", previous_state.action)

func redo():
	"""Redo the last undone action"""
	if redo_stack.is_empty():
		print("Nothing to redo")
		return
	
	var current_state = capture_current_state()
	undo_stack.append(current_state)
	
	var next_state = redo_stack.pop_back()
	restore_state(next_state)
	
	print("Redid: ", next_state.action)

func capture_current_state() -> Dictionary:
	"""Capture the current state of all objects"""
	var workspace = get_tree().current_scene
	var state = {
		"action": "Current state",
		"timestamp": Time.get_ticks_msec(),
		"objects": []
	}
	
	if workspace:
		for child in workspace.get_children():
			if child is Node3D and child.name != "humanoid" and child.name != "Lightning" and child.name != "SelectionMarkers" and child.name != "FreeCamera":
				var obj_state = {
					"path": child.get_path(),
					"transform": child.global_transform,
					"scale": child.scale,
					"exists": true
				}
				state.objects.append(obj_state)
	
	return state

func restore_state(state: Dictionary):
	"""Restore workspace to a saved state"""
	# Note: This is a simplified undo/redo system
	# For a full implementation, you'd need to track object creation/deletion
	# and property changes more comprehensively
	
	var workspace = get_tree().current_scene
	if not workspace:
		return
	
	# Restore transforms for existing objects
	for obj_state in state.objects:
		var obj = workspace.get_node_or_null(obj_state.path)
		if obj and obj is Node3D:
			obj.global_transform = obj_state.transform
			obj.scale = obj_state.scale
	
	# Deselect all after undo/redo
	if selection_manager:
		selection_manager.deselect_all_objects()

