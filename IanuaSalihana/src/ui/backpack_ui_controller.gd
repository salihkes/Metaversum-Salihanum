extends Control

# Controller for the BackpackUI buttons at the bottom of the screen

@onready var move_button = $HBoxContainer/MoveUI/Button
@onready var rotate_button = $HBoxContainer/RotateUI/Button
@onready var new_object_button = $HBoxContainer/NewObjectUI/Button

var plot_object_ui: Control = null
var tool_manager: Node = null

func _ready():
	# Get reference to PlotObjectUI and ToolManager
	await get_tree().process_frame
	var ui_layer = get_parent()
	if ui_layer:
		plot_object_ui = ui_layer.get_node_or_null("PlotObjectUI")
	
	var workspace = get_tree().current_scene
	tool_manager = workspace.get_node_or_null("ToolManager")
	
	# Connect buttons
	if move_button:
		move_button.pressed.connect(_on_move_pressed)
	if rotate_button:
		rotate_button.pressed.connect(_on_rotate_pressed)
	if new_object_button:
		new_object_button.pressed.connect(_on_new_object_pressed)

func _on_move_pressed():
	"""Activate move tool"""
	if tool_manager and tool_manager.has_method("set_tool"):
		tool_manager.set_tool(1)  # MOVE = 1
	if move_button:
		move_button.release_focus()

func _on_rotate_pressed():
	"""Activate rotate tool"""
	if tool_manager and tool_manager.has_method("set_tool"):
		tool_manager.set_tool(3)  # ROTATE = 3
	if rotate_button:
		rotate_button.release_focus()

func _on_new_object_pressed():
	"""Toggle the plot object UI"""
	if plot_object_ui:
		plot_object_ui.visible = not plot_object_ui.visible
		print("Plot Object UI toggled: ", plot_object_ui.visible)
	
	if new_object_button:
		new_object_button.release_focus()

func _input(event):
	# Handle keyboard shortcuts
	if event is InputEventKey and event.pressed and not event.echo:
		# Don't process shortcuts if any input field has focus
		pass
		
