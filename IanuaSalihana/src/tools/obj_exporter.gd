extends Node

## OBJ Exporter - Exports the workspace scene to OBJ format with materials and textures
## Press Ctrl+E to export

var export_folder := "user://exports/"
var current_vertex_offset := 1
var current_normal_offset := 1
var current_uv_offset := 1

# Texture export tracking for optimization
var exported_textures := {}  # Maps texture resource to exported filename

func _ready():
	# Create exports directory if it doesn't exist
	var dir = DirAccess.open("user://")
	if dir:
		if not dir.dir_exists("exports"):
			dir.make_dir("exports")

func _input(event):
	if event is InputEventKey and event.pressed:
		# Ctrl+E to export
		if event.keycode == KEY_E and event.ctrl_pressed:
			export_scene()

func export_scene():
	print("Starting OBJ export...")
	
	# Get timestamp for unique filename
	var time = Time.get_datetime_dict_from_system()
	var timestamp = "%04d%02d%02d_%02d%02d%02d" % [time.year, time.month, time.day, time.hour, time.minute, time.second]
	
	var obj_filename = "workspace_" + timestamp + ".obj"
	var mtl_filename = "workspace_" + timestamp + ".mtl"
	var obj_path = export_folder + obj_filename
	var mtl_path = export_folder + mtl_filename
	
	# Reset offsets
	current_vertex_offset = 1
	current_normal_offset = 1
	current_uv_offset = 1
	
	# Clear texture cache for new export
	exported_textures.clear()
	
	# Open files
	var obj_file = FileAccess.open(obj_path, FileAccess.WRITE)
	var mtl_file = FileAccess.open(mtl_path, FileAccess.WRITE)
	
	if not obj_file or not mtl_file:
		print("ERROR: Could not create export files!")
		return
	
	# Write OBJ header
	obj_file.store_line("# Exported from Metaversum-Salihanum")
	obj_file.store_line("# " + timestamp)
	obj_file.store_line("mtllib " + mtl_filename)
	obj_file.store_line("")
	
	# Write MTL header
	mtl_file.store_line("# Material Library")
	mtl_file.store_line("# " + timestamp)
	mtl_file.store_line("")
	
	# Write default material
	mtl_file.store_line("newmtl material_default")
	mtl_file.store_line("Ka 0.8 0.8 0.8")
	mtl_file.store_line("Kd 0.8 0.8 0.8")
	mtl_file.store_line("Ks 0.5 0.5 0.5")
	mtl_file.store_line("Ns 50.0")
	mtl_file.store_line("")
	
	# Collect all mesh instances
	var workspace = get_tree().current_scene
	var mesh_instances = []
	_collect_mesh_instances(workspace, mesh_instances)
	
	print("Found %d mesh instances to export" % mesh_instances.size())
	
	# Track materials
	var materials_exported = {}
	var material_counter = 0
	
	# Export each mesh instance
	for mesh_instance in mesh_instances:
		if mesh_instance is MeshInstance3D:
			var mesh = mesh_instance.mesh
			if mesh:
				_export_mesh_instance(mesh_instance, obj_file, mtl_file, materials_exported, material_counter)
	
	obj_file.close()
	mtl_file.close()
	
	var real_path = ProjectSettings.globalize_path(obj_path)
	print("\n========================================")
	print("EXPORT COMPLETE!")
	print("========================================")
	print("OBJ file: " + real_path)
	print("MTL file: " + ProjectSettings.globalize_path(mtl_path))
	print("Total meshes exported: %d" % mesh_instances.size())
	print("Total materials exported: %d" % materials_exported.size())
	print("Total unique textures exported: %d" % exported_textures.size())
	print("\nMaterial Summary:")
	for mat in materials_exported:
		var mat_name = materials_exported[mat]
		var color_str = "N/A"
		if mat is BaseMaterial3D:
			color_str = "RGB(%.0f, %.0f, %.0f)" % [mat.albedo_color.r * 255, mat.albedo_color.g * 255, mat.albedo_color.b * 255]
		print("  %s: %s" % [mat_name, color_str])
	print("========================================\n")
	
	# Show notification in game
	_show_export_notification(real_path)

func _collect_mesh_instances(node: Node, mesh_instances: Array):
	"""Recursively collect all MeshInstance3D nodes"""
	if node is MeshInstance3D:
		# Skip UI elements and certain nodes
		if not _should_skip_node(node):
			mesh_instances.append(node)
	
	for child in node.get_children():
		_collect_mesh_instances(child, mesh_instances)

func _should_skip_node(node: Node) -> bool:
	"""Determine if a node should be skipped during export"""
	# Skip nodes that are part of UI or non-exportable elements
	var path = str(node.get_path())
	
	# Skip UI, chat bubbles, and cameras
	if "UI" in path or "ChatBubble" in path or "Camera" in path:
		return true
	
	# Skip VR controllers and XR-related meshes
	if "XROrigin3D" in path or "XRController" in path or "LeftHand" in path or "RightHand" in path:
		return true
	
	# Skip player character body parts (optional - comment out if you want to export the player)
	# if "humanoid/CharacterModel" in path:
	# 	return true
	
	# Skip if node is hidden
	if node.has_method("is_visible") and not node.is_visible():
		return true
	
	return false

func _export_mesh_instance(mesh_instance: MeshInstance3D, obj_file: FileAccess, mtl_file: FileAccess, materials_exported: Dictionary, material_counter: int):
	"""Export a single mesh instance to OBJ format"""
	var mesh = mesh_instance.mesh
	var global_transform = mesh_instance.global_transform
	
	# Get node name for object group
	var object_name = mesh_instance.name.replace(" ", "_")
	var node_path = str(mesh_instance.get_path())
	print("\n=== Exporting mesh: %s ===" % object_name)
	print("  Path: %s" % node_path)
	print("  Mesh type: %s" % mesh.get_class())
	print("  Has material_override: %s" % str(mesh_instance.material_override != null))
	
	obj_file.store_line("o " + object_name)
	obj_file.store_line("g " + object_name)
	
	# Get mesh data
	if mesh is ArrayMesh or mesh is PrimitiveMesh:
		var surface_count = mesh.get_surface_count() if mesh is ArrayMesh else 1
		print("  Surface count: %d" % surface_count)
		
		for surface_idx in range(surface_count):
			var arrays
			
			if mesh is ArrayMesh:
				arrays = mesh.surface_get_arrays(surface_idx)
			else:
				# For PrimitiveMesh, get the arrays
				var temp_mesh = mesh as PrimitiveMesh
				arrays = temp_mesh.get_mesh_arrays()
			
			if arrays.size() == 0:
				continue
			
			var vertices = arrays[Mesh.ARRAY_VERTEX] if arrays[Mesh.ARRAY_VERTEX] else []
			var normals = arrays[Mesh.ARRAY_NORMAL] if arrays[Mesh.ARRAY_NORMAL] else []
			var uvs = arrays[Mesh.ARRAY_TEX_UV] if arrays[Mesh.ARRAY_TEX_UV] else []
			var indices = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] else []
			
			if vertices.size() == 0:
				continue
			
			# Write vertices
			for vertex in vertices:
				var v = global_transform * vertex
				obj_file.store_line("v %.6f %.6f %.6f" % [v.x, v.y, v.z])
			
			# Write normals
			if normals.size() > 0:
				var normal_transform = global_transform.basis
				for normal in normals:
					var n = (normal_transform * normal).normalized()
					obj_file.store_line("vn %.6f %.6f %.6f" % [n.x, n.y, n.z])
			
			# Write UVs
			if uvs.size() > 0:
				for uv in uvs:
					obj_file.store_line("vt %.6f %.6f" % [uv.x, 1.0 - uv.y])  # Flip V coordinate
			
			# Get material - check in order of precedence
			var material = null
			print("  Surface %d:" % surface_idx)
			
			# 1. Check surface override on mesh instance (highest priority)
			material = mesh_instance.get_surface_override_material(surface_idx)
			if material:
				print("    ✓ Found surface override material")
				print("      Type: %s" % material.get_class())
				if material is BaseMaterial3D:
					print("      Color: %s" % str(material.albedo_color))
			
			# 2. Check material override on the mesh instance (applies to all surfaces)
			if not material and mesh_instance.material_override:
				material = mesh_instance.material_override
				print("    ✓ Found material override on mesh instance")
				print("      Type: %s" % material.get_class())
				if material is BaseMaterial3D:
					print("      Color: %s" % str(material.albedo_color))
			
			# 3. Check material on the mesh surface itself
			if not material and mesh is ArrayMesh:
				material = mesh.surface_get_material(surface_idx)
				if material:
					print("    ✓ Found material on mesh surface")
					print("      Type: %s" % material.get_class())
					if material is BaseMaterial3D:
						print("      Color: %s" % str(material.albedo_color))
			
			if not material:
				print("    ✗ No material found!")
			
			# Export material if not already exported
			var material_name = "material_default"
			if material:
				if not materials_exported.has(material):
					material_name = "material_%d" % materials_exported.size()
					materials_exported[material] = material_name
					_export_material(material, material_name, mtl_file)
					print("    → Exported as: %s" % material_name)
				else:
					material_name = materials_exported[material]
					print("    → Reusing existing: %s" % material_name)
			else:
				# Create a default material if none found
				print("Warning: No material found for %s surface %d, using default" % [object_name, surface_idx])
			
			obj_file.store_line("usemtl " + material_name)
			
			# Write faces
			if indices.size() > 0:
				# Indexed mesh
				for i in range(0, indices.size(), 3):
					if i + 2 < indices.size():
						var v1 = indices[i] + current_vertex_offset
						var v2 = indices[i + 1] + current_vertex_offset
						var v3 = indices[i + 2] + current_vertex_offset
						
						if uvs.size() > 0 and normals.size() > 0:
							obj_file.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [
								v1, v1, v1,
								v2, v2, v2,
								v3, v3, v3
							])
						elif uvs.size() > 0:
							obj_file.store_line("f %d/%d %d/%d %d/%d" % [
								v1, v1, v2, v2, v3, v3
							])
						elif normals.size() > 0:
							obj_file.store_line("f %d//%d %d//%d %d//%d" % [
								v1, v1, v2, v2, v3, v3
							])
						else:
							obj_file.store_line("f %d %d %d" % [v1, v2, v3])
			else:
				# Non-indexed mesh - create faces from vertex sequence
				for i in range(0, vertices.size(), 3):
					if i + 2 < vertices.size():
						var v1 = i + current_vertex_offset
						var v2 = i + 1 + current_vertex_offset
						var v3 = i + 2 + current_vertex_offset
						
						if uvs.size() > 0 and normals.size() > 0:
							obj_file.store_line("f %d/%d/%d %d/%d/%d %d/%d/%d" % [
								v1, v1, v1,
								v2, v2, v2,
								v3, v3, v3
							])
						elif uvs.size() > 0:
							obj_file.store_line("f %d/%d %d/%d %d/%d" % [
								v1, v1, v2, v2, v3, v3
							])
						elif normals.size() > 0:
							obj_file.store_line("f %d//%d %d//%d %d//%d" % [
								v1, v1, v2, v2, v3, v3
							])
						else:
							obj_file.store_line("f %d %d %d" % [v1, v2, v3])
			
			# Update offsets
			current_vertex_offset += vertices.size()
			current_normal_offset += normals.size()
			current_uv_offset += uvs.size()
	
	obj_file.store_line("")

func _export_material(material: Material, material_name: String, mtl_file: FileAccess):
	"""Export material to MTL format"""
	mtl_file.store_line("newmtl " + material_name)
	
	if material is BaseMaterial3D:
		var base_mat = material as BaseMaterial3D
		
		# Albedo color - this works for both StandardMaterial3D and BaseMaterial3D
		var albedo = base_mat.albedo_color
		mtl_file.store_line("Ka %.6f %.6f %.6f" % [albedo.r, albedo.g, albedo.b])
		mtl_file.store_line("Kd %.6f %.6f %.6f" % [albedo.r, albedo.g, albedo.b])
		
		# Specular
		var metallic = base_mat.metallic
		var specular = base_mat.metallic_specular
		mtl_file.store_line("Ks %.6f %.6f %.6f" % [specular, specular, specular])
		
		# Roughness to shininess conversion
		var roughness = base_mat.roughness
		var shininess = (1.0 - roughness) * 1000.0  # Convert roughness to shininess (0-1000)
		mtl_file.store_line("Ns %.6f" % shininess)
		
		# Transparency
		if albedo.a < 1.0:
			mtl_file.store_line("d %.6f" % albedo.a)
			mtl_file.store_line("Tr %.6f" % (1.0 - albedo.a))
		
		# Handle transparency mode
		var transparency = base_mat.transparency
		if transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
			if albedo.a < 1.0:
				mtl_file.store_line("# Transparency enabled")
		
		# Texture
		var texture = base_mat.albedo_texture
		if texture:
			print("      Albedo texture:")
			var texture_path = _export_texture(texture, material_name)
			if texture_path != "":
				mtl_file.store_line("map_Kd " + texture_path)
		
		# Normal map
		var normal_texture = base_mat.normal_texture
		if normal_texture:
			print("      Normal texture:")
			var texture_path = _export_texture(normal_texture, material_name + "_normal")
			if texture_path != "":
				mtl_file.store_line("map_Bump " + texture_path)
		
		# Roughness map
		var roughness_texture = base_mat.roughness_texture
		if roughness_texture:
			print("      Roughness texture:")
			var texture_path = _export_texture(roughness_texture, material_name + "_roughness")
			if texture_path != "":
				mtl_file.store_line("map_Ns " + texture_path)
		
		# Metallic map
		var metallic_texture = base_mat.metallic_texture
		if metallic_texture:
			print("      Metallic texture:")
			var texture_path = _export_texture(metallic_texture, material_name + "_metallic")
			if texture_path != "":
				mtl_file.store_line("map_Pm " + texture_path)
	
	elif material is ShaderMaterial:
		# Try to extract color from shader parameters
		var shader_mat = material as ShaderMaterial
		var albedo_color = Color.WHITE
		
		# Try common shader parameter names for color
		var color_params = ["albedo", "color", "albedo_color", "base_color", "diffuse"]
		for param_name in color_params:
			var param_value = shader_mat.get_shader_parameter(param_name)
			if param_value is Color:
				albedo_color = param_value
				break
		
		mtl_file.store_line("Ka %.6f %.6f %.6f" % [albedo_color.r, albedo_color.g, albedo_color.b])
		mtl_file.store_line("Kd %.6f %.6f %.6f" % [albedo_color.r, albedo_color.g, albedo_color.b])
		mtl_file.store_line("Ks 0.5 0.5 0.5")
		mtl_file.store_line("Ns 50.0")
		
		# Try to find texture in shader parameters
		var texture_params = ["texture_albedo", "albedo_texture", "texture", "diffuse_texture"]
		for param_name in texture_params:
			var param_value = shader_mat.get_shader_parameter(param_name)
			if param_value is Texture2D:
				print("      Shader texture:")
				var texture_path = _export_texture(param_value, material_name)
				if texture_path != "":
					mtl_file.store_line("map_Kd " + texture_path)
				break
	
	else:
		# Default material values
		mtl_file.store_line("Ka 0.8 0.8 0.8")
		mtl_file.store_line("Kd 0.8 0.8 0.8")
		mtl_file.store_line("Ks 0.5 0.5 0.5")
		mtl_file.store_line("Ns 50.0")
	
	mtl_file.store_line("")

func _export_texture(texture: Texture2D, base_name: String) -> String:
	"""Export texture to file and return filename (with deduplication)"""
	if not texture:
		return ""
	
	# Check if we've already exported this texture
	if exported_textures.has(texture):
		var cached_filename = exported_textures[texture]
		print("      ↳ Reusing existing texture: %s" % cached_filename)
		return cached_filename
	
	# Try to get the image from the texture
	var image: Image = null
	
	if texture.has_method("get_image"):
		image = texture.get_image()
	elif texture is ImageTexture:
		image = texture.get_image()
	
	if not image:
		return ""
	
	# Generate a better filename based on the original texture resource path
	var texture_filename: String
	
	if texture.resource_path != "" and not texture.resource_path.begins_with("local://"):
		# Extract the original filename from the resource path
		var original_path = texture.resource_path
		var original_filename = original_path.get_file()  # Gets "texture.png" from "res://path/to/texture.png"
		
		# Clean up the filename
		original_filename = original_filename.replace(" ", "_")
		original_filename = original_filename.replace("(", "")
		original_filename = original_filename.replace(")", "")
		
		# Use the original filename (already has extension)
		texture_filename = original_filename
	else:
		# Fallback to base_name if no resource path
		texture_filename = base_name + ".png"
	
	var texture_path = export_folder + texture_filename
	
	# Save the image
	var err = image.save_png(ProjectSettings.globalize_path(texture_path))
	if err == OK:
		print("      ↳ Exported new texture: %s (from %s)" % [texture_filename, texture.resource_path if texture.resource_path != "" else "runtime"])
		# Cache this texture for future reuse
		exported_textures[texture] = texture_filename
		return texture_filename
	else:
		print("      ↳ Failed to export texture: %s" % texture_filename)
		return ""

func _show_export_notification(path: String):
	"""Show a notification in the game that export is complete"""
	print("\n========================================")
	print("EXPORT COMPLETE!")
	print("File saved to: " + path)
	print("========================================\n")
	
	# Try to find a label or create a temporary notification
	# This is optional - just for user feedback
	var workspace = get_tree().current_scene
	var ui = workspace.get_node_or_null("UI")
	if ui:
		var notification = Label.new()
		notification.text = "Scene exported to:\n" + path
		notification.position = Vector2(400, 300)
		notification.add_theme_color_override("font_color", Color.GREEN)
		notification.add_theme_font_size_override("font_size", 20)
		notification.add_theme_color_override("font_outline_color", Color.BLACK)
		notification.add_theme_constant_override("outline_size", 3)
		ui.add_child(notification)
		
		# Remove after 5 seconds
		await get_tree().create_timer(5.0).timeout
		notification.queue_free()
