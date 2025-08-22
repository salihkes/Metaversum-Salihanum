extends Node

# Skybox textures
@export var day_sky: Texture2D
@export var sunset_sky: Texture2D 
@export var night_sky: Texture2D

# Day/night cycle settings
@export var use_system_time: bool = true
@export var cycle_duration_minutes: float = 24.0
@export var start_time_hours: float = 21.3
@export var time_scale: float = 60.0  # 1 minute real time = 60 minutes game time

# Environment references
@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"
@onready var directional_light: DirectionalLight3D = $"../DirectionalLight3D"
@onready var omni_lights = get_tree().get_nodes_in_group("night_lights")

# Time tracking
var current_time: float = 0.0  # in hours
var transition_duration: float = 0.5  # in hours
var day_started: bool = false

# Environment parameter presets
var day_params = {
	"fog_density": 0.01,
	"fog_albedo": Color(0.6, 0.65, 0.7, 1),
	"fog_emission": Color(0.1, 0.1, 0.1, 1),
	"light_energy": 1.0,
	"tonemap_exposure": 1.1,
	"ambient_light_energy": 1.0,
	"adjustment_brightness": 1.05,
	"adjustment_contrast": 1.25,
	"adjustment_saturation": 0.75
}

var night_params = {
	"fog_density": 0.03,
	"fog_albedo": Color(0.1, 0.12, 0.2, 1),
	"fog_emission": Color(0.05, 0.05, 0.1, 1),
	"light_energy": 0.2,
	"tonemap_exposure": 1.3,
	"ambient_light_energy": 0.3,
	"adjustment_brightness": 0.9,
	"adjustment_contrast": 1.4,
	"adjustment_saturation": 0.5
}

var sunset_params = {
	"fog_density": 0.02,
	"fog_albedo": Color(0.7, 0.5, 0.4, 1),
	"fog_emission": Color(0.2, 0.1, 0.05, 1),
	"light_energy": 0.7,
	"tonemap_exposure": 1.2,
	"ambient_light_energy": 0.7,
	"adjustment_brightness": 1.0,
	"adjustment_contrast": 1.3,
	"adjustment_saturation": 0.9
}

func _ready():
	# Initialize time based on system time if enabled
	if use_system_time:
		var datetime = Time.get_datetime_dict_from_system()
		current_time = float(datetime.hour) + float(datetime.minute) / 60.0
	else:
		current_time = start_time_hours
	
	# Initial update
	update_environment(0)

func _process(delta):
	if use_system_time:
		# Update time from system clock
		var datetime = Time.get_datetime_dict_from_system()
		current_time = float(datetime.hour) + float(datetime.minute) / 60.0
	
	# Update environment based on time
	update_environment(delta)

func update_environment(delta):
	# Determine time of day phase
	# 6-8: Sunrise
	# 8-18: Day
	# 18-20: Sunset
	# 20-6: Night
	
	var env = world_environment.environment
	var sky_material = env.sky.sky_material
	
	# Sunrise transition (6-8)
	if current_time >= 6.0 and current_time < 8.0:
		var t = inverse_lerp(6.0, 8.0, current_time)
		transition_environment(sunset_params, day_params, t)
		transition_skybox(sunset_sky, day_sky, t)
		update_sun_position(t * 0.25)  # 0.0 to 0.25
		
	# Day (8-18)
	elif current_time >= 8.0 and current_time < 18.0:
		var t = inverse_lerp(8.0, 18.0, current_time)
		set_environment_params(day_params)
		sky_material.panorama = day_sky
		update_sun_position(0.25 + t * 0.5)  # 0.25 to 0.75
		
	# Sunset transition (18-20)
	elif current_time >= 18.0 and current_time < 20.0:
		var t = inverse_lerp(18.0, 20.0, current_time)
		transition_environment(day_params, sunset_params, t)
		transition_skybox(day_sky, sunset_sky, t)
		update_sun_position(0.75 + t * 0.125)  # 0.75 to 0.875
		
	# Night (20-6)
	else:
		var t = 0.0
		if current_time >= 20.0:
			t = inverse_lerp(20.0, 24.0, current_time) * 0.5
		else:
			t = 0.5 + inverse_lerp(0.0, 6.0, current_time) * 0.5
			
		transition_environment(sunset_params, night_params, min(1.0, inverse_lerp(20.0, 22.0, current_time if current_time >= 20.0 else current_time + 24.0)))
		transition_skybox(sunset_sky, night_sky, min(1.0, inverse_lerp(20.0, 22.0, current_time if current_time >= 20.0 else current_time + 24.0)))
		update_sun_position(0.875 + t * 0.125)  # 0.875 to 1.0, then 0.0 to 0.125

func transition_environment(from_params, to_params, t):
	var env = world_environment.environment
	
	# Interpolate fog parameters
	env.volumetric_fog_density = lerp(from_params.fog_density, to_params.fog_density, t)
	env.volumetric_fog_albedo = from_params.fog_albedo.lerp(to_params.fog_albedo, t)
	env.volumetric_fog_emission = from_params.fog_emission.lerp(to_params.fog_emission, t)
	
	# Interpolate light parameters
	directional_light.light_energy = lerp(from_params.light_energy, to_params.light_energy, t)
	
	# Interpolate environment parameters
	env.tonemap_exposure = lerp(from_params.tonemap_exposure, to_params.tonemap_exposure, t)
	env.adjustment_brightness = lerp(from_params.adjustment_brightness, to_params.adjustment_brightness, t)
	env.adjustment_contrast = lerp(from_params.adjustment_contrast, to_params.adjustment_contrast, t)
	env.adjustment_saturation = lerp(from_params.adjustment_saturation, to_params.adjustment_saturation, t)
	
	# Update night lights
	var night_intensity = inverse_lerp(18.0, 20.0, current_time if current_time >= 18.0 else 24.0)
	if current_time >= 6.0 and current_time < 8.0:
		night_intensity = 1.0 - inverse_lerp(6.0, 8.0, current_time)
	elif current_time >= 8.0 and current_time < 18.0:
		night_intensity = 0.0
	elif current_time >= 20.0 or current_time < 6.0:
		night_intensity = 1.0
		
	for light in omni_lights:
		light.light_energy = lerp(0.0, 2.0, night_intensity)

func transition_skybox(from_sky, to_sky, t):
	# This is a simplified approach - for a true blend between skyboxes,
	# you would need a custom shader that blends between two textures
	var env = world_environment.environment
	var sky_material = env.sky.sky_material
	
	if t < 0.5:
		sky_material.panorama = from_sky
	else:
		sky_material.panorama = to_sky

func update_sun_position(t):
	# t goes from 0.0 to 1.0 representing a full day cycle
	# Convert to radians (0 to 2π)
	var angle = t * 2.0 * PI
	
	# Calculate sun direction
	var x = sin(angle)
	var y = cos(angle)
	
	# Update directional light rotation
	directional_light.rotation.x = -angle - PI/2
	
	# Adjust light color based on time of day
	if current_time >= 6.0 and current_time < 8.0:
		# Sunrise - warm light
		directional_light.light_color = Color(1.0, 0.9, 0.7)
	elif current_time >= 8.0 and current_time < 18.0:
		# Day - neutral light
		directional_light.light_color = Color(1.0, 1.0, 1.0)
	elif current_time >= 18.0 and current_time < 20.0:
		# Sunset - warm light
		directional_light.light_color = Color(1.0, 0.8, 0.6)
	else:
		# Night - blue-ish moonlight
		directional_light.light_color = Color(0.6, 0.7, 1.0)

func set_environment_params(params):
	var env = world_environment.environment
	
	env.volumetric_fog_density = params.fog_density
	env.volumetric_fog_albedo = params.fog_albedo
	env.volumetric_fog_emission = params.fog_emission
	
	directional_light.light_energy = params.light_energy
	
	env.tonemap_exposure = params.tonemap_exposure
	env.adjustment_brightness = params.adjustment_brightness
	env.adjustment_contrast = params.adjustment_contrast
	env.adjustment_saturation = params.adjustment_saturation

# Optional: Public methods to control time
func set_time(hours: float):
	current_time = clamp(hours, 0.0, 24.0)
	update_environment(0)

func get_time() -> float:
	return current_time

func get_time_string() -> String:
	var hours = floor(current_time)
	var minutes = floor((current_time - hours) * 60)
	return "%02d:%02d" % [hours, minutes] 
