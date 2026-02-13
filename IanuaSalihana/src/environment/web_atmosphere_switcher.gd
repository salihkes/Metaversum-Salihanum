extends Node
## Automatically swaps atmosphere and cloud shaders to web-safe versions
## when running on an HTML5 / Web build.
##
## The "Extremely Fast Atmosphere" addon and the volumetric cloud shader both
## rely on DEPTH_TEXTURE (hint_depth_texture) which is unavailable or broken
## on WebGL.  The web-safe alternatives replace the depth-buffer read with
## analytical ray-sphere intersection against the planet surface, producing
## a visually equivalent result without depth texture dependency.
##
## Add this node as a child of the workspace scene, and assign the Atmosphere
## and VolumetricClouds nodes via the inspector (or hard-code the paths).

const _web_atmo_shader = preload("res://src/environment/atmosphere_web.gdshader")
const _web_cloud_shader = preload("res://src/environment/volumetric_clouds_web.gdshader")

## Reference to the Atmosphere MeshInstance3D node.
@export var atmosphere_node: MeshInstance3D

## Reference to the VolumetricClouds MeshInstance3D node.
@export var cloud_node: MeshInstance3D

## Planet mesh radius in workspace-local units used for cloud occlusion.
## Must be <= the actual planet sphere mesh radius so the camera is always
## outside the occlusion sphere.  0 = auto-detect from ProvinceMap node.
@export var planet_mesh_radius: float = 0.0

## Reduce cloud ray-march quality on web for better frame rate.
@export var web_cloud_march_steps: int = 12
@export var web_cloud_light_steps: int = 2


func _ready() -> void:
	if OS.has_feature("web"):
		print("[WebAtmosphereSwitcher] Web platform detected — switching to web-safe shaders.")
		_switch_to_web_shaders()
	else:
		print("[WebAtmosphereSwitcher] Native platform — keeping original shaders.")


func _switch_to_web_shaders() -> void:
	_switch_atmosphere()
	_switch_clouds()


func _switch_atmosphere() -> void:
	if not atmosphere_node:
		push_warning("[WebAtmosphereSwitcher] No atmosphere_node assigned — skipping atmosphere shader swap.")
		return

	var mat := atmosphere_node.material_override as ShaderMaterial
	if not mat:
		push_warning("[WebAtmosphereSwitcher] Atmosphere has no ShaderMaterial — skipping.")
		return

	# Swap the shader program; all uniform values in the material stay intact
	# because both shaders share the same uniform interface.
	mat.shader = _web_atmo_shader
	print("[WebAtmosphereSwitcher] Atmosphere shader swapped to web version.")


func _switch_clouds() -> void:
	if not cloud_node:
		push_warning("[WebAtmosphereSwitcher] No cloud_node assigned — skipping cloud shader swap.")
		return

	var mat := cloud_node.material_override as ShaderMaterial
	if not mat:
		push_warning("[WebAtmosphereSwitcher] Clouds have no ShaderMaterial — skipping.")
		return

	# Swap the shader program
	mat.shader = _web_cloud_shader

	# Feed the planet surface radius to the web shader for analytical occlusion.
	# This MUST be <= the actual planet mesh radius so the camera (which sits
	# on the mesh surface) is always OUTSIDE the occlusion sphere.
	var radius := planet_mesh_radius
	if radius <= 0.0:
		# Auto-detect: try to read the ProvinceMap mesh scale
		var province_map = get_node_or_null("../Planet/Main/ProvinceMap")
		if province_map and province_map is MeshInstance3D:
			# SphereMesh default radius is 0.5; actual radius = scale * 0.5
			radius = province_map.transform.basis.get_scale().x * 0.5
			print("[WebAtmosphereSwitcher] Auto-detected planet mesh radius: %.1f" % radius)
		elif "planet_radius" in cloud_node:
			# Fallback: use the script's planet_radius with a safety margin
			radius = cloud_node.planet_radius * 0.96
			print("[WebAtmosphereSwitcher] Using planet_radius fallback: %.1f" % radius)
		else:
			var inner_r = mat.get_shader_parameter("cloud_inner_radius")
			if inner_r != null:
				radius = inner_r - 14.0
	mat.set_shader_parameter("planet_surface_radius", radius)

	# Lower quality for web performance
	mat.set_shader_parameter("march_steps", web_cloud_march_steps)
	mat.set_shader_parameter("light_steps", web_cloud_light_steps)

	print("[WebAtmosphereSwitcher] Cloud shader swapped to web version (march=%d, light=%d)." % [web_cloud_march_steps, web_cloud_light_steps])
