extends Node

# Environment resources
@export var day_environment: Environment
@export var sunset_environment: Environment
@export var night_environment: Environment

# Light references
@export var sun_light: DirectionalLight3D
@export var moon_light: DirectionalLight3D

# Time mode
enum TimeMode { REAL_TIME, MANUAL, ACCELERATED }
@export var time_mode: TimeMode = TimeMode.REAL_TIME

# Manual time settings (0-24 hours)
@export_range(0.0, 24.0, 0.1) var manual_time_hours: float = 12.0

# Accelerated time settings
@export var time_speed_multiplier: float = 60.0  # 1 minute = 1 hour by default
@export var start_time_hours: float = 8.0  # Start at 8 AM

# Time tracking
var current_time: float = 0.0  # 0.0 to 1.0 representing full day cycle
var accelerated_time_offset: float = 0.0

# Environment references
var world_environment: WorldEnvironment

# Time periods (in normalized time 0-1)
# 0.0 = midnight, 0.5 = noon
const SUNRISE_START = 0.208  # 5:00 AM
const DAY_START = 0.292      # 7:00 AM
const SUNSET_START = 0.708   # 5:00 PM
const NIGHT_START = 0.792    # 7:00 PM

func _ready():
	# Find WorldEnvironment in parent
	world_environment = get_parent().get_node_or_null("WorldEnvironment")
	if not world_environment:
		push_error("WorldEnvironment not found in parent!")
		return
	
	# Load default environments if not set
	if not day_environment:
		day_environment = load("res://src/environment/day_environment.tres")
	if not sunset_environment:
		sunset_environment = load("res://src/environment/sunriseset_environment.tres")
	if not night_environment:
		night_environment = load("res://src/environment/night_environment.tres")
	
	# Initialize time based on mode
	match time_mode:
		TimeMode.REAL_TIME:
			update_time_from_os()
		TimeMode.MANUAL:
			current_time = manual_time_hours / 24.0
		TimeMode.ACCELERATED:
			accelerated_time_offset = start_time_hours / 24.0
			current_time = accelerated_time_offset
	
	update_environment()

func _process(delta):
	match time_mode:
		TimeMode.REAL_TIME:
			update_time_from_os()
		TimeMode.MANUAL:
			current_time = manual_time_hours / 24.0
		TimeMode.ACCELERATED:
			# Advance time at accelerated rate
			var time_delta = (delta * time_speed_multiplier) / 86400.0  # 86400 seconds in a day
			accelerated_time_offset += time_delta
			if accelerated_time_offset >= 1.0:
				accelerated_time_offset -= 1.0
			current_time = accelerated_time_offset
	
	update_environment()

func update_time_from_os():
	var time_dict = Time.get_time_dict_from_system()
	var hours = time_dict.hour
	var minutes = time_dict.minute
	var seconds = time_dict.second
	
	# Convert to normalized time (0-1)
	var total_seconds = hours * 3600 + minutes * 60 + seconds
	current_time = total_seconds / 86400.0  # 86400 seconds in a day

func update_environment():
	if not world_environment:
		return
	
	# Determine current period and set environment
	if current_time >= DAY_START and current_time < SUNSET_START:
		# DAY (7 AM - 5 PM)
		world_environment.environment = day_environment
		set_light_levels(1.0, 0.0)
	
	elif current_time >= SUNSET_START and current_time < NIGHT_START:
		# SUNSET (5 PM - 7 PM)
		world_environment.environment = sunset_environment
		var blend = (current_time - SUNSET_START) / (NIGHT_START - SUNSET_START)
		set_light_levels(1.0 - blend * 0.7, blend * 0.5)
	
	elif current_time >= SUNRISE_START and current_time < DAY_START:
		# SUNRISE (5 AM - 7 AM)
		world_environment.environment = sunset_environment
		var blend = (current_time - SUNRISE_START) / (DAY_START - SUNRISE_START)
		set_light_levels(0.3 + blend * 0.7, 0.5 - blend * 0.5)
	
	else:
		# NIGHT (7 PM - 5 AM)
		world_environment.environment = night_environment
		set_light_levels(0.0, 0.5)

func set_light_levels(sun_energy: float, moon_energy: float):
	# Update sun light
	if sun_light:
		sun_light.light_energy = sun_energy * 1.0
		sun_light.visible = sun_energy > 0.01
	
	# Update moon light
	if moon_light:
		moon_light.light_energy = moon_energy * 0.3  # Subtle moonlight
		moon_light.visible = moon_energy > 0.01

# Manual control functions
func set_time_of_day_hours(hours: float):
	"""Set time in hours (0-24)"""
	time_mode = TimeMode.MANUAL
	manual_time_hours = clamp(hours, 0.0, 24.0)
	current_time = manual_time_hours / 24.0
	update_environment()

func set_time_normalized(time: float):
	"""Set time as normalized value (0-1)"""
	current_time = clamp(time, 0.0, 1.0)
	manual_time_hours = current_time * 24.0
	update_environment()

func set_to_day():
	set_time_of_day_hours(12.0)  # Noon

func set_to_sunset():
	set_time_of_day_hours(18.0)  # 6 PM

func set_to_night():
	set_time_of_day_hours(0.0)  # Midnight

func set_to_sunrise():
	set_time_of_day_hours(6.0)  # 6 AM

func get_current_time_string() -> String:
	"""Returns current time as HH:MM format"""
	var hours = int(current_time * 24.0)
	var minutes = int((current_time * 24.0 - hours) * 60.0)
	return "%02d:%02d" % [hours, minutes]

func switch_to_real_time():
	time_mode = TimeMode.REAL_TIME

func switch_to_manual_time():
	time_mode = TimeMode.MANUAL

func switch_to_accelerated_time():
	time_mode = TimeMode.ACCELERATED
	accelerated_time_offset = current_time
