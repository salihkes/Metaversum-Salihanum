extends Control

# Mode Toggle UI for switching between Part and Group selection modes
# This is a standalone UI component that doesn't affect networking

var selection_manager: Node = null
var part_mode_button: Button = null
var group_mode_button: Button = null

func _ready():
	# Wait for scene to be ready
	await get_tree().process_frame
	
	var workspace = get_tree().current_scene
	
	# Get selection manager reference
	selection_manager = workspace.get_node_or_null("SelectionManager")
	
	# Get button references
	part_mode_button = get_node_or_null("Panel/PartModeButton")
	group_mode_button = get_node_or_null("Panel/GroupModeButton")
	
	# Connect button signals
	if part_mode_button:
		part_mode_button.pressed.connect(_on_part_mode_pressed)
	if group_mode_button:
		group_mode_button.pressed.connect(_on_group_mode_pressed)
	
	# Set initial button states (Part mode is default)
	update_button_states()

func _on_part_mode_pressed():
	if selection_manager:
		# Access the SelectionMode enum from selection_manager
		var SelectionMode = selection_manager.get("SelectionMode")
		if SelectionMode:
			selection_manager.set_selection_mode(SelectionMode.PART)
			update_button_states()

func _on_group_mode_pressed():
	if selection_manager:
		# Access the SelectionMode enum from selection_manager
		var SelectionMode = selection_manager.get("SelectionMode")
		if SelectionMode:
			selection_manager.set_selection_mode(SelectionMode.GROUP)
			update_button_states()

func update_button_states():
	if not selection_manager:
		return
	
	var current_mode = selection_manager.get_selection_mode()
	
	# Access the SelectionMode enum from selection_manager
	var SelectionMode = selection_manager.get("SelectionMode")
	if not SelectionMode:
		return
	
	# Update button states to show which mode is active
	if part_mode_button:
		if current_mode == SelectionMode.PART:
			part_mode_button.disabled = true
		else:
			part_mode_button.disabled = false
	
	if group_mode_button:
		if current_mode == SelectionMode.GROUP:
			group_mode_button.disabled = true
		else:
			group_mode_button.disabled = false

