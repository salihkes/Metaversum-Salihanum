extends StaticBody3D
class_name Planet

# Planet properties
@export var planet_name: String = "Unnamed Planet"
@export var gravity_strength: float = 9.8
@export var gravity_radius: float = 200.0  # Maximum distance where gravity affects objects
@export var surface_radius: float = 128.0  # Actual size of the planet
@export var atmosphere_color: Color = Color.CYAN
@export var planet_material: Material

# Visual components
var mesh_instance: MeshInstance3D
var collision_shape: CollisionShape3D
var atmosphere_effect: MeshInstance3D

func _ready():
	# Setup the planet mesh and collision
	setup_planet_mesh()
	setup_collision()
	setup_atmosphere()

func setup_planet_mesh():
	# Create or get existing mesh instance
	if has_node("MeshInstance3D"):
		mesh_instance = $MeshInstance3D
	else:
		mesh_instance = MeshInstance3D.new()
		add_child(mesh_instance)
	
	# Create sphere mesh
	var sphere_mesh = SphereMesh.new()
	sphere_mesh.radius = surface_radius
	sphere_mesh.height = surface_radius * 2
	mesh_instance.mesh = sphere_mesh
	
	# Apply material if provided
	if planet_material:
		mesh_instance.material_override = planet_material

func setup_collision():
	# Create or get existing collision shape
	if has_node("CollisionShape3D"):
		collision_shape = $CollisionShape3D
	else:
		collision_shape = CollisionShape3D.new()
		add_child(collision_shape)
	
	# Create sphere collision shape
	var sphere_shape = SphereShape3D.new()
	sphere_shape.radius = surface_radius
	collision_shape.shape = sphere_shape

func setup_atmosphere():
	# Create atmosphere visual effect
	atmosphere_effect = MeshInstance3D.new()
	atmosphere_effect.name = "Atmosphere"
	add_child(atmosphere_effect)
	
	var atmosphere_mesh = SphereMesh.new()
	atmosphere_mesh.radius = surface_radius * 1.1
	atmosphere_mesh.height = surface_radius * 2.2
	atmosphere_effect.mesh = atmosphere_mesh
	
	# Create atmosphere material
	var atmosphere_material = StandardMaterial3D.new()
	atmosphere_material.albedo_color = atmosphere_color
	atmosphere_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	atmosphere_material.albedo_color.a = 0.3
	atmosphere_material.emission_enabled = true
	atmosphere_material.emission = atmosphere_color * 0.5
	atmosphere_material.no_depth_test = true
	atmosphere_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	atmosphere_effect.material_override = atmosphere_material

# Calculate gravity force for a given position
func get_gravity_force(target_position: Vector3) -> Vector3:
	var distance_to_planet = global_position.distance_to(target_position)
	
	# Return zero gravity if outside gravity radius
	if distance_to_planet > gravity_radius:
		return Vector3.ZERO
	
	# Calculate gravity direction (towards planet center)
	var gravity_direction = (global_position - target_position).normalized()
	
	# Calculate gravity strength based on distance (inverse square law)
	var gravity_falloff = 1.0 - (distance_to_planet / gravity_radius)
	gravity_falloff = max(gravity_falloff, 0.0)
	
	# Apply stronger gravity closer to surface
	var surface_distance = max(distance_to_planet - surface_radius, 0.0)
	var surface_falloff = 1.0 - (surface_distance / (gravity_radius - surface_radius))
	surface_falloff = max(surface_falloff, 0.0)
	
	var final_strength = gravity_strength * gravity_falloff * surface_falloff
	
	return gravity_direction * final_strength

# Check if a position is on the planet's surface
func is_on_surface(target_position: Vector3) -> bool:
	var distance = global_position.distance_to(target_position)
	return distance <= (surface_radius + 5.0)  # Small tolerance for surface detection

# Get the surface normal at a given position
func get_surface_normal(target_position: Vector3) -> Vector3:
	return (target_position - global_position).normalized() 
