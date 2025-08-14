extends Node3D

@export var mouse_sensitivity := 0.005
@export var rotation_smoothing := 10.0
@export var zoom_sensitivity := 0.5  # Controls how fast zooming occurs
@export var min_zoom_distance := 1.0  # Minimum zoom distance
@export var max_zoom_distance := 10.0  # Maximum zoom distance

# Camera nodes
var cam_look: Node3D
var camera: Camera3D

# Camera state
var target_rotation := Vector2.ZERO
var current_rotation := Vector2.ZERO
var initial_rotation := Vector2.ZERO
var is_rotating := false
var current_zoom := 4.0  # Default zoom distance
var ui_has_focus := false  # Add this to track UI focus state

func _ready():
	# Get camera nodes
	cam_look = $CamLook
	camera = $CamLook/Camera3D
	
	# Store initial rotation
	initial_rotation.x = rotation.y
	initial_rotation.y = cam_look.rotation.x
	target_rotation = initial_rotation
	current_rotation = initial_rotation
	
	# Set initial zoom position
	camera.position.y = current_zoom
	
	# Set initial mouse mode to visible, not captured
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _input(event):
	# Skip camera input handling if UI has focus
	if has_ui_focus():
		return
		
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT:
				# Toggle camera rotation with left mouse button
				is_rotating = event.pressed
				if is_rotating:
					Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
				else:
					Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
			
			MOUSE_BUTTON_WHEEL_UP:
				# Zoom in
				current_zoom = max(current_zoom - zoom_sensitivity, min_zoom_distance)
			
			MOUSE_BUTTON_WHEEL_DOWN:
				# Zoom out
				current_zoom = min(current_zoom + zoom_sensitivity, max_zoom_distance)
	
	elif event is InputEventMouseMotion and is_rotating:
		# Rotate camera with mouse movement
		target_rotation.x -= event.relative.x * mouse_sensitivity
		target_rotation.y -= event.relative.y * mouse_sensitivity
		
		# Clamp vertical rotation to prevent camera flipping
		target_rotation.y = clamp(target_rotation.y, -PI/2, PI/2)

func _process(delta):
	# Smoothly update camera rotation
	current_rotation = current_rotation.lerp(target_rotation, delta * rotation_smoothing)
	rotation.y = current_rotation.x
	cam_look.rotation.x = current_rotation.y
	
	# Smoothly update camera zoom
	camera.position.y = lerp(camera.position.y, current_zoom, delta * rotation_smoothing)

# Check if any UI element has focus
func has_ui_focus() -> bool:
	# Find the LineEdit in the scene
	var line_edit = get_viewport().gui_get_focus_owner()
	return line_edit != null
