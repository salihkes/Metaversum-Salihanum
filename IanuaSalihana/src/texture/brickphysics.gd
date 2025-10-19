extends Node3D

@onready var stud_mesh = $MATERIAL

# Part properties
@export var can_collide: bool = true:
	set(value):
		can_collide = value
		update_collision()

@export var locked: bool = false

func _ready():
	update_uv_scale()
	update_collision()
	# Watch for transform changes
	set_notify_transform(true)

func _notification(what):
	if what == NOTIFICATION_TRANSFORM_CHANGED:
		# Transform (including scale) has changed
		update_uv_scale()

func update_uv_scale():
	if not stud_mesh:
		return
	
	# Get the current scale (only X and Z for horizontal surface mapping, ignore Y height)
	var current_scale = scale
	
	# Update UV scale to match the brick's scale
	# For each surface in the mesh
	for i in range(stud_mesh.get_surface_override_material_count()):
		var mat = stud_mesh.get_surface_override_material(i)
		if mat:
			# Create a copy if it's shared to avoid affecting other instances
			if not mat.resource_local_to_scene:
				mat = mat.duplicate()
				stud_mesh.set_surface_override_material(i, mat)
			
			# Set UV1 scale to match the brick's scale (X and Z only, Y stays at 1 (EDIT: REVERTED)
			if mat is StandardMaterial3D:
				mat.uv1_scale = Vector3(current_scale.x, current_scale.z, current_scale.y)
	
	# Also check active material if no override
	if stud_mesh.mesh:
		for i in range(stud_mesh.mesh.get_surface_count()):
			if stud_mesh.get_surface_override_material(i) == null:
				var mat = stud_mesh.mesh.surface_get_material(i)
				if mat:
					# Create override material from the mesh's material
					var override_mat = mat.duplicate()
					stud_mesh.set_surface_override_material(i, override_mat)
					
					if override_mat is StandardMaterial3D:
						override_mat.uv1_scale = Vector3(current_scale.x, current_scale.z, current_scale.y)

func update_collision():
	"""Update collision based on can_collide property"""
	if not stud_mesh:
		return
	
	# Find the StaticBody3D child
	var static_body = stud_mesh.get_node_or_null("StaticBody3D")
	if static_body:
		# Enable/disable collision by setting the collision layer and mask
		if can_collide:
			static_body.collision_layer = 1
			static_body.collision_mask = 1
		else:
			static_body.collision_layer = 0
			static_body.collision_mask = 0
