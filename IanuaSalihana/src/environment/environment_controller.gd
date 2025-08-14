extends Node

# Skybox textures
@export var day_sky: Texture2D
@export var sunset_sky: Texture2D 
@export var night_sky: Texture2D

# Day/night cycle settings
@export var use_system_time: bool = true
@export var cycle_duration_minutes: float = 24.0
@export var start_time_hours: float = 16.7
@export var time_scale: float = 60.0  # 1 minute real time = 60 minutes game time

# Graphics quality settings
@export var use_simplified_graphics: bool = false
@export var auto_detect_low_end: bool = true

# Environment references
@onready var world_environment: WorldEnvironment = $"../WorldEnvironment"
@onready var directional_light: DirectionalLight3D = $"../DirectionalLight3D"
@onready var omni_lights = get_tree().get_nodes_in_group("night_lights")
@onready var interior_lights = get_tree().get_nodes_in_group("interior_lights")

# Time tracking
var current_time: float = 0.0  # in hours
var transition_duration: float = 0.5  # in hours
var day_started: bool = false

# High-quality environment parameter presets
var day_params = {
	"fog_density": 0.01,
	"fog_albedo": Color(0.6, 0.65, 0.7, 1),
	"fog_emission": Color(0.1, 0.1, 0.1, 1),
	"light_energy": 1.0,
	"tonemap_exposure": 1.1,
	"ambient_light_energy": 0.4,  # Increased for better interior lighting
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
	"ambient_light_energy": 0.2,  # Increased for better interior visibility
	"adjustment_brightness": 1.0,  # Slightly brighter for interior spaces
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

# Simplified/low-end environment parameter presets
var day_params_simple = {
	"fog_density": 0.0,
	"fog_albedo": Color(0.6, 0.65, 0.7, 1),
	"fog_emission": Color(0.0, 0.0, 0.0, 1),
	"light_energy": 1.0,
	"tonemap_exposure": 1.0,
	"ambient_light_energy": 0.5,  # Increased for better interior lighting in simplified mode
	"adjustment_brightness": 1.1,  # Brighter for better visibility
	"adjustment_contrast": 1.0,
	"adjustment_saturation": 1.0
}

var night_params_simple = {
	"fog_density": 0.0,
	"fog_albedo": Color(0.1, 0.12, 0.2, 1),
	"fog_emission": Color(0.0, 0.0, 0.0, 1),
	"light_energy": 0.4,
	"tonemap_exposure": 1.0,
	"ambient_light_energy": 0.25,  # Increased for better interior visibility
	"adjustment_brightness": 0.9,  # Less dark for interior spaces
	"adjustment_contrast": 1.0,
	"adjustment_saturation": 0.8
}

var sunset_params_simple = {
	"fog_density": 0.0,
	"fog_albedo": Color(0.7, 0.5, 0.4, 1),
	"fog_emission": Color(0.0, 0.0, 0.0, 1),
	"light_energy": 0.9,
	"tonemap_exposure": 1.0,
	"ambient_light_energy": 0.5,
	"adjustment_brightness": 1.0,
	"adjustment_contrast": 1.0,
	"adjustment_saturation": 1.0
}

func _ready():
	print("=== ENVIRONMENT CONTROLLER INITIALIZATION ===")
	print("Initial use_simplified_graphics: ", use_simplified_graphics)
	print("Auto detect low end: ", auto_detect_low_end)
	
	# Auto-detect low-end devices if enabled AND no manual override
	if auto_detect_low_end and not use_simplified_graphics:
		print("Running auto-detection...")
		detect_and_set_graphics_quality()
	else:
		print("Skipping auto-detection - manual setting or disabled")
	
	print("Final use_simplified_graphics: ", use_simplified_graphics)
	
	# Apply graphics quality settings
	apply_graphics_quality_settings()
	
	# Initialize time based on system time if enabled
	if use_system_time:
		var datetime = Time.get_datetime_dict_from_system()
		current_time = float(datetime.hour) + float(datetime.minute) / 60.0
	else:
		current_time = start_time_hours
	
	# Initial update
	update_environment(0)
	print("=== INITIALIZATION COMPLETE ===")

func detect_and_set_graphics_quality():
	# Simple device detection based on platform and available memory
	var platform = OS.get_name()
	var original_setting = use_simplified_graphics
	
	print("Platform detected: ", platform)
	
	# Consider mobile devices and low-spec platforms as low-end
	if platform in ["Android", "iOS"]:
		use_simplified_graphics = true
		print("Mobile platform detected - enabling simplified graphics")
	elif platform == "Web":
		use_simplified_graphics = true
		print("Web platform detected - enabling simplified graphics")
	else:
		# For desktop, could add additional checks like available RAM, GPU info, etc.
		# For now, default to high quality on desktop
		print("Desktop platform detected - keeping current setting")
		# Don't change the setting on desktop
	
	if original_setting != use_simplified_graphics:
		print("Graphics setting changed by auto-detection: ", original_setting, " -> ", use_simplified_graphics)

func apply_graphics_quality_settings():
	var env = world_environment.environment
	
	if use_simplified_graphics:
		print("=== APPLYING SIMPLIFIED GRAPHICS SETTINGS ===")
		# Disable intensive effects
		env.ssao_enabled = false
		env.ssil_enabled = false
		env.sdfgi_enabled = false
		env.glow_enabled = false
		env.volumetric_fog_enabled = false
		
		# More aggressive simplifications
		env.ssr_enabled = false  # Disable screen-space reflections
		env.ssao_enabled = false
		env.ssil_enabled = false
		
		# Disable/reduce additional expensive features
		env.fog_enabled = false  # Disable regular fog too
		
		# Reduce shadow quality on the directional light
		if directional_light:
			directional_light.shadow_enabled = true  # Keep shadows but reduce quality
			directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			directional_light.directional_shadow_max_distance = 50.0  # Reduced from default
		
		# Simplify other settings
		env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		env.adjustment_enabled = true
		
		# Set render scale for additional performance (if supported)
		var viewport = get_viewport()
		if viewport:
			viewport.scaling_3d_scale = 0.8  # 80% render scale
			print("- Render scale set to: 0.8")
		
		# Print current state for verification
		print("- SSAO enabled: ", env.ssao_enabled)
		print("- SSIL enabled: ", env.ssil_enabled) 
		print("- SDFGI enabled: ", env.sdfgi_enabled)
		print("- Glow enabled: ", env.glow_enabled)
		print("- Volumetric fog enabled: ", env.volumetric_fog_enabled)
		print("- SSR enabled: ", env.ssr_enabled)
		print("- Regular fog enabled: ", env.fog_enabled)
		print("- Tonemap mode: ", env.tonemap_mode)
		if directional_light:
			print("- Shadow max distance: ", directional_light.directional_shadow_max_distance)
		print("=== SIMPLIFIED GRAPHICS APPLIED ===")
	else:
		print("=== APPLYING HIGH-QUALITY GRAPHICS SETTINGS ===")
		# Enable intensive effects
		env.ssao_enabled = true
		env.ssao_radius = 1.5
		env.ssao_detail = 1.0
		env.ssao_horizon = 0.2
		
		env.ssil_enabled = true
		env.ssil_intensity = 2.0
		env.ssil_sharpness = 0.8
		
		env.sdfgi_enabled = true
		env.sdfgi_use_occlusion = true
		env.sdfgi_energy = 1.2
		
		env.glow_enabled = true
		env.glow_normalized = true
		env.glow_bloom = 0.3
		env.glow_blend_mode = 1
		
		env.volumetric_fog_enabled = true
		env.volumetric_fog_length = 128.0
		
		# Enable screen-space reflections if available
		env.ssr_enabled = true
		
		# Restore shadow quality
		if directional_light:
			directional_light.shadow_enabled = true
			directional_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
			directional_light.directional_shadow_max_distance = 200.0  # Default/high quality
		
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.adjustment_enabled = true
		
		# Restore full render scale
		var viewport = get_viewport()
		if viewport:
			viewport.scaling_3d_scale = 1.0  # 100% render scale
			print("- Render scale set to: 1.0")
		
		# Print current state for verification
		print("- SSAO enabled: ", env.ssao_enabled)
		print("- SSIL enabled: ", env.ssil_enabled)
		print("- SDFGI enabled: ", env.sdfgi_enabled) 
		print("- Glow enabled: ", env.glow_enabled)
		print("- Volumetric fog enabled: ", env.volumetric_fog_enabled)
		print("- SSR enabled: ", env.ssr_enabled)
		print("- Regular fog enabled: ", env.fog_enabled)
		print("- Tonemap mode: ", env.tonemap_mode)
		if directional_light:
			print("- Shadow max distance: ", directional_light.directional_shadow_max_distance)
		print("=== HIGH-QUALITY GRAPHICS APPLIED ===")

func get_current_params():
	# Return the appropriate parameter set based on graphics quality
	if use_simplified_graphics:
		return {
			"day": day_params_simple,
			"night": night_params_simple,
			"sunset": sunset_params_simple
		}
	else:
		return {
			"day": day_params,
			"night": night_params,
			"sunset": sunset_params
		}

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
	var params = get_current_params()
	
	# Sunrise transition (6-8)
	if current_time >= 6.0 and current_time < 8.0:
		var t = inverse_lerp(6.0, 8.0, current_time)
		transition_environment(params.sunset, params.day, t)
		transition_skybox(sunset_sky, day_sky, t)
		update_sun_position(t * 0.25)  # 0.0 to 0.25
		
	# Day (8-18)
	elif current_time >= 8.0 and current_time < 18.0:
		var t = inverse_lerp(8.0, 18.0, current_time)
		set_environment_params(params.day)
		sky_material.panorama = day_sky
		update_sun_position(0.25 + t * 0.5)  # 0.25 to 0.75
		
	# Sunset transition (18-20)
	elif current_time >= 18.0 and current_time < 20.0:
		var t = inverse_lerp(18.0, 20.0, current_time)
		transition_environment(params.day, params.sunset, t)
		transition_skybox(day_sky, sunset_sky, t)
		update_sun_position(0.75 + t * 0.125)  # 0.75 to 0.875
		
	# Night (20-6)
	else:
		var t = 0.0
		if current_time >= 20.0:
			t = inverse_lerp(20.0, 24.0, current_time) * 0.5
		else:
			t = 0.5 + inverse_lerp(0.0, 6.0, current_time) * 0.5
			
		transition_environment(params.sunset, params.night, min(1.0, inverse_lerp(20.0, 22.0, current_time if current_time >= 20.0 else current_time + 24.0)))
		transition_skybox(sunset_sky, night_sky, min(1.0, inverse_lerp(20.0, 22.0, current_time if current_time >= 20.0 else current_time + 24.0)))
		update_sun_position(0.875 + t * 0.125)  # 0.875 to 1.0, then 0.0 to 0.125

func transition_environment(from_params, to_params, t):
	var env = world_environment.environment
	
	# Interpolate fog parameters (only if volumetric fog is enabled)
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = lerp(from_params.fog_density, to_params.fog_density, t)
		env.volumetric_fog_albedo = from_params.fog_albedo.lerp(to_params.fog_albedo, t)
		env.volumetric_fog_emission = from_params.fog_emission.lerp(to_params.fog_emission, t)
	
	# Interpolate light parameters
	directional_light.light_energy = lerp(from_params.light_energy, to_params.light_energy, t)
	
	# Interpolate environment parameters
	env.ambient_light_energy = lerp(from_params.ambient_light_energy, to_params.ambient_light_energy, t)
	env.tonemap_exposure = lerp(from_params.tonemap_exposure, to_params.tonemap_exposure, t)
	env.adjustment_brightness = lerp(from_params.adjustment_brightness, to_params.adjustment_brightness, t)
	env.adjustment_contrast = lerp(from_params.adjustment_contrast, to_params.adjustment_contrast, t)
	env.adjustment_saturation = lerp(from_params.adjustment_saturation, to_params.adjustment_saturation, t)
	
	# Update night lights (reduce intensity for simplified graphics)
	var base_intensity = 10.0 if not use_simplified_graphics else 5.0
	var night_intensity = inverse_lerp(18.0, 20.0, current_time if current_time >= 18.0 else 24.0)
	if current_time >= 6.0 and current_time < 8.0:
		night_intensity = 1.0 - inverse_lerp(6.0, 8.0, current_time)
	elif current_time >= 8.0 and current_time < 18.0:
		night_intensity = 0.0
	elif current_time >= 20.0 or current_time < 6.0:
		night_intensity = 1.0
		
	for light in omni_lights:
		light.light_energy = lerp(0.0, base_intensity, night_intensity)
	
	# Update interior lights - they should always provide some illumination
	# but be more intense during night and darker times
	var interior_base_intensity = 3.0 if not use_simplified_graphics else 2.0
	var interior_intensity = 0.4  # Base intensity for interior lights
	
	# Increase interior light intensity during darker times
	if current_time >= 6.0 and current_time < 8.0:
		# Morning - moderate interior lighting
		interior_intensity = 0.5 + (1.0 - inverse_lerp(6.0, 8.0, current_time)) * 0.3
	elif current_time >= 8.0 and current_time < 16.0:
		# Day - reduced interior lighting
		interior_intensity = 0.4
	elif current_time >= 16.0 and current_time < 20.0:
		# Evening - increasing interior lighting
		interior_intensity = 0.4 + inverse_lerp(16.0, 20.0, current_time) * 0.5
	elif current_time >= 20.0 or current_time < 6.0:
		# Night - full interior lighting
		interior_intensity = 0.9
	
	for light in interior_lights:
		if light != null:
			light.light_energy = interior_base_intensity * interior_intensity

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
	# Fixed calculation: sun should be above horizon during day (6-18h)
	# At t=0.25 (morning), sun should be low in east
	# At t=0.5 (noon), sun should be high overhead
	# At t=0.75 (evening), sun should be low in west
	directional_light.rotation.x = angle - PI/2
	
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
	
	# Only set fog parameters if volumetric fog is enabled
	if env.volumetric_fog_enabled:
		env.volumetric_fog_density = params.fog_density
		env.volumetric_fog_albedo = params.fog_albedo
		env.volumetric_fog_emission = params.fog_emission
	
	directional_light.light_energy = params.light_energy
	
	# Set ambient light energy
	env.ambient_light_energy = params.ambient_light_energy
	
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

# Graphics quality control methods
func set_graphics_quality(simplified: bool):
	print("Setting graphics quality to: ", "SIMPLIFIED" if simplified else "HIGH-QUALITY")
	use_simplified_graphics = simplified
	apply_graphics_quality_settings()
	update_environment(0)  # Force update with new settings
	
	# Additional verification
	verify_graphics_settings()

func toggle_graphics_quality():
	print("Toggling graphics quality from: ", "SIMPLIFIED" if use_simplified_graphics else "HIGH-QUALITY")
	set_graphics_quality(not use_simplified_graphics)

func is_using_simplified_graphics() -> bool:
	return use_simplified_graphics

func verify_graphics_settings():
	var env = world_environment.environment
	print("=== GRAPHICS SETTINGS VERIFICATION ===")
	print("Current simplified mode: ", use_simplified_graphics)
	print("SSAO enabled: ", env.ssao_enabled)
	print("SSIL enabled: ", env.ssil_enabled)
	print("SDFGI enabled: ", env.sdfgi_enabled)
	print("Glow enabled: ", env.glow_enabled)
	print("Volumetric fog enabled: ", env.volumetric_fog_enabled)
	print("SSR enabled: ", env.ssr_enabled)
	print("Tonemap mode: ", env.tonemap_mode)
	print("=== VERIFICATION COMPLETE ===")

# Method to get detailed performance info
func get_graphics_info() -> Dictionary:
	var env = world_environment.environment
	return {
		"simplified_mode": use_simplified_graphics,
		"ssao_enabled": env.ssao_enabled,
		"ssil_enabled": env.ssil_enabled,
		"sdfgi_enabled": env.sdfgi_enabled,
		"glow_enabled": env.glow_enabled,
		"volumetric_fog_enabled": env.volumetric_fog_enabled,
		"ssr_enabled": env.ssr_enabled,
		"tonemap_mode": env.tonemap_mode
	} 
