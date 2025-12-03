extends Button

# Save button for plot objects in the Move/Rotate tools
# Saves current object transforms to server

var plot_sync: Node = null

func _ready():
	# Find the plot_object_sync node
	await get_tree().process_frame
	var workspace = get_tree().current_scene
	plot_sync = workspace.get_node_or_null("PlotObjectSync")
	
	if not plot_sync:
		print("Warning: PlotObjectSync not found, save button won't work")
	
	# Connect button press
	pressed.connect(_on_save_pressed)
	
	# Connect to plot sync signals for visual feedback
	if plot_sync:
		plot_sync.unsaved_changes_detected.connect(_on_unsaved_changes)
		plot_sync.all_changes_saved.connect(_on_all_saved)

func _on_unsaved_changes():
	"""Visual feedback when unsaved changes exist"""
	modulate = Color(1.0, 0.8, 0.0)  # Yellow tint

func _on_all_saved():
	"""Visual feedback when all saved"""
	modulate = Color(0.0, 1.0, 0.0)  # Green flash
	await get_tree().create_timer(0.5).timeout
	modulate = Color.WHITE

func _on_save_pressed():
	"""Save all changes when button is pressed"""
	if plot_sync and plot_sync.has_method("save_all_changes"):
		plot_sync.save_all_changes()
		print("Save button pressed - changes saved")
	else:
		print("Cannot save - PlotObjectSync not available")
	
	release_focus()

