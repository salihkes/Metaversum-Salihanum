@tool
class_name ProvinceMap
extends MeshInstance3D
## GPU-accelerated province map rendered on a 3D PlaneMesh or SphereMesh.
##
## Each province can have an **owner** and, optionally, an **occupier**.
## Colours come from the owner definitions — no manual colour painting.
## Occupation is rendered as diagonal stripes (occupier base + owner stripes)
## via a dual-lookup-texture spatial shader.
##
## Province IDs are deterministic: same image → same left-to-right,
## top-to-bottom scan → same IDs every time.  Save files key on the
## original map colour (hex) so they are independent of scan order.
##
## **@tool**: In the editor the node shows a textured preview plane at the
## correct world size so you can position it inside buildings, etc.

# ── Exports ──────────────────────────────────────────────────────────────────

## The province source image (unique colour per province).
@export var province_texture: Texture2D:
	set(v):
		province_texture = v
		if Engine.is_editor_hint():
			_update_editor_preview()

## Optional JSON file to load at startup.
@export_file("*.json") var province_data_path: String = ""

@export var show_borders: bool = true:
	set(v):
		show_borders = v
		_set_shader_param("show_borders", v)

@export var border_color: Color = Color(0, 0, 0, 0.6):
	set(v):
		border_color = v
		_set_shader_param("border_color", v)

## Default colour for provinces that have no owner.
@export var default_province_color: Color = Color(0.76, 0.78, 0.8)

## Width of the occupation stripe in map-pixels.
@export var stripe_width: float = 8.0:
	set(v):
		stripe_width = v
		_set_shader_param("stripe_width", v)

## Scale multiplier for the 3D plane (height in world units).
@export var map_world_height: float = 10.0:
	set(v):
		map_world_height = v
		if Engine.is_editor_hint():
			_update_editor_preview()

## When true, render on a SphereMesh instead of a PlaneMesh (for planetary maps).
@export var sphere_mode: bool = false

## Radius of the sphere in world units (only used when sphere_mode = true).
@export var sphere_radius: float = 0.5

## Fraction of V-space to blank out at each pole (letterbox ocean).
@export var polar_cutoff: float = 0.12

# ── Signals ──────────────────────────────────────────────────────────────────

signal province_clicked(province_id: int)
signal province_hovered(province_id: int)
signal owners_changed()          ## Emitted when the owner list changes.
signal data_changed()            ## Emitted when any province data changes.

# ── Internal: index map ──────────────────────────────────────────────────────

var _province_image: Image
var _index_image: Image
var _index_texture: ImageTexture

# ── Internal: dual lookup textures ───────────────────────────────────────────

var _lookup_image: Image           # controller colour (occupier or owner)
var _lookup_texture: ImageTexture
var _owner_lookup_image: Image     # always the sovereign owner colour
var _owner_lookup_texture: ImageTexture

# ── Province identity ────────────────────────────────────────────────────────

var _color_to_id: Dictionary = {}       # packed-RGB-int → province ID
var _id_to_color: Dictionary = {}       # province ID → original Color
var _id_to_name: Dictionary = {}        # province ID → custom display name

# ── Owner definitions ────────────────────────────────────────────────────────

## { owner_id: String → { "name": String, "color": Color } }
var _owners: Dictionary = {}
var _next_owner_uid: int = 1

# ── Province ownership state ─────────────────────────────────────────────────

var _province_owner: Dictionary = {}    # province_id → owner_id
var _province_occupier: Dictionary = {} # province_id → owner_id  (only when occupied)

# ── 3D geometry ──────────────────────────────────────────────────────────────

## World-space size of the PlaneMesh (Vector2: x width, y depth/z).
## Set after _build(); useful for hit-to-UV conversion in external scripts.
var plane_size: Vector2 = Vector2.ZERO

# ── Misc ─────────────────────────────────────────────────────────────────────

var _province_count: int = 0
var _hovered_id: int = -1
var _selected_id: int = -1
var _is_built: bool = false


# ══════════════════════════════════════════════════════════════════════════════
#  LIFECYCLE
# ══════════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	if Engine.is_editor_hint():
		_update_editor_preview()
		return
	_build()


# ══════════════════════════════════════════════════════════════════════════════
#  EDITOR PREVIEW  (only runs in the Godot editor)
# ══════════════════════════════════════════════════════════════════════════════

## Shows a textured PlaneMesh at the correct world size so you can see
## the map footprint, move it around, and verify it fits your building.
func _update_editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	if not province_texture:
		mesh = null
		material_override = null
		return

	var mat := StandardMaterial3D.new()
	mat.albedo_texture = province_texture
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	if sphere_mode:
		if not mesh is SphereMesh:
			mesh = SphereMesh.new()
		(mesh as SphereMesh).radius = sphere_radius
		(mesh as SphereMesh).height = sphere_radius * 2.0
		(mesh as SphereMesh).radial_segments = 64
		(mesh as SphereMesh).rings = 32
	else:
		var img := province_texture.get_image()
		var aspect := float(img.get_width()) / float(img.get_height())
		plane_size = Vector2(aspect * map_world_height, map_world_height)
		if not mesh is PlaneMesh:
			mesh = PlaneMesh.new()
		(mesh as PlaneMesh).size = plane_size

	material_override = mat


# ══════════════════════════════════════════════════════════════════════════════
#  BUILD
# ══════════════════════════════════════════════════════════════════════════════

func _build() -> void:
	if not province_texture:
		push_error("ProvinceMap: Assign a province_texture!")
		return

	var start_time := Time.get_ticks_msec()

	_province_image = province_texture.get_image()
	_province_image.decompress()
	_province_image.convert(Image.FORMAT_RGB8)

	var width := _province_image.get_width()
	var height := _province_image.get_height()
	var src_data := _province_image.get_data()
	var pixel_count := width * height

	# ── Scan: discover colours & build index map ──
	_color_to_id.clear()
	_id_to_color.clear()
	_province_count = 0

	var index_data := PackedByteArray()
	index_data.resize(pixel_count * 3)

	for i in range(pixel_count):
		var off := i * 3
		var r: int = src_data[off]
		var g: int = src_data[off + 1]
		var b: int = src_data[off + 2]
		var key: int = r | (g << 8) | (b << 16)

		var id: int
		if _color_to_id.has(key):
			id = _color_to_id[key]
		else:
			id = _province_count
			_color_to_id[key] = id
			_id_to_color[id] = Color8(r, g, b)
			_province_count += 1

		index_data[off]     = id % 256
		index_data[off + 1] = (id / 256) % 256
		index_data[off + 2] = 0

	_index_image = Image.create_from_data(width, height, false, Image.FORMAT_RGB8, index_data)
	_index_texture = ImageTexture.create_from_image(_index_image)

	# ── Create dual lookup textures (256×256 each) ──
	_lookup_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	_lookup_image.fill(default_province_color)
	_lookup_texture = ImageTexture.create_from_image(_lookup_image)

	_owner_lookup_image = Image.create(256, 256, false, Image.FORMAT_RGBA8)
	_owner_lookup_image.fill(default_province_color)
	_owner_lookup_texture = ImageTexture.create_from_image(_owner_lookup_image)

	# ── Load initial data ──
	if not province_data_path.is_empty():
		_apply_file(province_data_path)

	# ── Create 3D mesh (plane or sphere) ──
	if sphere_mode:
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = sphere_radius
		sphere_mesh.height = sphere_radius * 2.0
		sphere_mesh.radial_segments = 64
		sphere_mesh.rings = 32
		self.mesh = sphere_mesh
		# No self.scale — the mesh itself is at the correct size.
	else:
		var aspect := float(width) / float(height)
		plane_size = Vector2(aspect * map_world_height, map_world_height)
		var plane_mesh := PlaneMesh.new()
		plane_mesh.size = plane_size
		plane_mesh.subdivide_width = 0
		plane_mesh.subdivide_depth = 0
		self.mesh = plane_mesh

	# ── Wire spatial shader ──
	var shader := preload("res://src/paintablemap/shaders/province_map.gdshader")
	var mat := ShaderMaterial.new()
	mat.shader = shader
	mat.set_shader_parameter("index_map",      _index_texture)
	mat.set_shader_parameter("color_lookup",   _lookup_texture)
	mat.set_shader_parameter("owner_lookup",   _owner_lookup_texture)
	mat.set_shader_parameter("map_size",       Vector2(width, height))
	mat.set_shader_parameter("show_borders",   show_borders)
	mat.set_shader_parameter("border_color",   border_color)
	mat.set_shader_parameter("stripe_width",   stripe_width)
	mat.set_shader_parameter("hover_id",       Vector2(-1, -1))
	mat.set_shader_parameter("selected_id",    Vector2(-1, -1))
	mat.set_shader_parameter("sphere_mode",    sphere_mode)
	mat.set_shader_parameter("polar_cutoff",   polar_cutoff)
	self.material_override = mat

	# ── Create collision body for raycasting ──
	var body := StaticBody3D.new()
	body.name = "MapCollider"
	var col := CollisionShape3D.new()
	if sphere_mode:
		var sphere_shape := SphereShape3D.new()
		sphere_shape.radius = sphere_radius
		col.shape = sphere_shape
	else:
		var box := BoxShape3D.new()
		box.size = Vector3(plane_size.x, 0.01, plane_size.y)
		col.shape = box
	body.add_child(col)
	add_child(body)

	_is_built = true
	var elapsed := Time.get_ticks_msec() - start_time
	if sphere_mode:
		print("ProvinceMap: %d provinces in %d ms  (%d×%d)  sphere r=%.0f" % [
			_province_count, elapsed, width, height, sphere_radius])
	else:
		print("ProvinceMap: %d provinces in %d ms  (%d×%d)  plane=%.1f×%.1f" % [
			_province_count, elapsed, width, height, plane_size.x, plane_size.y])


# ══════════════════════════════════════════════════════════════════════════════
#  OWNER MANAGEMENT
# ══════════════════════════════════════════════════════════════════════════════

## Create a new owner.  Returns the generated ID.
func add_owner(owner_name: String, color: Color) -> String:
	var id := "owner_%d" % _next_owner_uid
	_next_owner_uid += 1
	_owners[id] = { "name": owner_name, "color": color }
	owners_changed.emit()
	return id


## Register (or update) an owner with a specific ID.  Use this when the
## server assigns a player identity that must match exactly.
func register_owner(owner_id: String, owner_name: String, color: Color) -> void:
	_owners[owner_id] = { "name": owner_name, "color": color }
	_flush_lookups()
	owners_changed.emit()


## Remove an owner — all their provinces become unowned and unoccupied.
func remove_owner(owner_id: String) -> void:
	if not _owners.has(owner_id):
		return
	_owners.erase(owner_id)
	for pid in _province_owner.keys():
		if _province_owner[pid] == owner_id:
			_province_owner.erase(pid)
			_province_occupier.erase(pid)
			_refresh_province(pid)
	for pid in _province_occupier.keys():
		if _province_occupier[pid] == owner_id:
			_province_occupier.erase(pid)
			_refresh_province(pid)
	_flush_lookups()
	owners_changed.emit()
	data_changed.emit()


## Update an owner's name and/or colour.  All their provinces refresh.
func update_owner(owner_id: String, owner_name: String, color: Color) -> void:
	if not _owners.has(owner_id):
		return
	_owners[owner_id] = { "name": owner_name, "color": color }
	for pid in _province_owner:
		if _province_owner[pid] == owner_id or _province_occupier.get(pid, "") == owner_id:
			_refresh_province(pid)
	_flush_lookups()
	owners_changed.emit()
	data_changed.emit()


func get_owner_data(owner_id: String) -> Dictionary:
	return _owners.get(owner_id, {})

func get_all_owners() -> Dictionary:
	return _owners

func get_owner_ids() -> Array:
	return _owners.keys()


# ══════════════════════════════════════════════════════════════════════════════
#  PROVINCE OWNERSHIP / OCCUPATION
# ══════════════════════════════════════════════════════════════════════════════

## Assign an owner (clears any existing occupier).
func set_province_owner(pid: int, owner_id: String) -> void:
	if pid < 0 or pid >= _province_count:
		return
	if not _owners.has(owner_id):
		return
	_province_owner[pid] = owner_id
	_province_occupier.erase(pid)
	_refresh_province(pid)
	_flush_lookups()
	data_changed.emit()


## Remove ownership entirely (also clears occupier).
func clear_province_owner(pid: int) -> void:
	if pid < 0 or pid >= _province_count:
		return
	_province_owner.erase(pid)
	_province_occupier.erase(pid)
	_refresh_province(pid)
	_flush_lookups()
	data_changed.emit()


## Set an occupier.  Province must already have a *different* owner.
func set_province_occupier(pid: int, occupier_id: String) -> void:
	if pid < 0 or pid >= _province_count:
		return
	if not _province_owner.has(pid):
		push_warning("ProvinceMap: can't occupy province %d — no owner" % pid)
		return
	if not _owners.has(occupier_id):
		return
	if occupier_id == _province_owner[pid]:
		clear_province_occupier(pid)
		return
	_province_occupier[pid] = occupier_id
	_refresh_province(pid)
	_flush_lookups()
	data_changed.emit()


## Clear occupation (province reverts to owner colour).
func clear_province_occupier(pid: int) -> void:
	if not _province_occupier.has(pid):
		return
	_province_occupier.erase(pid)
	_refresh_province(pid)
	_flush_lookups()
	data_changed.emit()


## Peace treaty: every occupied province → owner becomes the occupier.
func apply_treaty() -> int:
	var count := _province_occupier.size()
	for pid in _province_occupier.keys():
		_province_owner[pid] = _province_occupier[pid]
	_province_occupier.clear()
	for pid in _province_owner:
		_refresh_province(pid)
	_flush_lookups()
	data_changed.emit()
	return count


## Reset a province to unowned, unnamed, unoccupied.
func reset_province(pid: int) -> void:
	if pid < 0 or pid >= _province_count:
		return
	_province_owner.erase(pid)
	_province_occupier.erase(pid)
	_id_to_name.erase(pid)
	_refresh_province(pid)
	_flush_lookups()
	data_changed.emit()


# ══════════════════════════════════════════════════════════════════════════════
#  PROVINCE NAME
# ══════════════════════════════════════════════════════════════════════════════

func set_province_name(pid: int, pname: String) -> void:
	if pid < 0 or pid >= _province_count:
		return
	if pname.is_empty():
		_id_to_name.erase(pid)
	else:
		_id_to_name[pid] = pname
	data_changed.emit()


# ══════════════════════════════════════════════════════════════════════════════
#  QUERY HELPERS
# ══════════════════════════════════════════════════════════════════════════════

## Get province ID from normalised UV coordinates (0-1).
## This is the primary method for 3D interaction — the caller converts a
## 3D raycast hit point to UV and passes it here.
func get_province_at_uv(uv: Vector2) -> int:
	if not _is_built:
		return -1
	# In sphere mode, polar regions are ocean — no provinces.
	if sphere_mode and (uv.y < polar_cutoff or uv.y > 1.0 - polar_cutoff):
		return -1
	# In sphere mode, remap V so the full texture is squeezed into the
	# non-polar band (matching the shader's remap).
	var sample_uv := uv
	if sphere_mode:
		var band := 1.0 - 2.0 * polar_cutoff
		sample_uv.y = (uv.y - polar_cutoff) / band
	var px := int(sample_uv.x * _province_image.get_width())
	var py := int(sample_uv.y * _province_image.get_height())
	if px < 0 or py < 0 or px >= _province_image.get_width() or py >= _province_image.get_height():
		return -1
	var c := _index_image.get_pixel(px, py)
	return int(round(c.r * 255.0)) + int(round(c.g * 255.0)) * 256


## Original map colour (the unique RGB in Provinces.png).
func get_province_map_color(pid: int) -> Color:
	return _id_to_color.get(pid, Color.BLACK)

func get_province_name(pid: int) -> String:
	return _id_to_name.get(pid, "Province #%d" % pid)

func get_province_owner(pid: int) -> String:
	return _province_owner.get(pid, "")

func get_province_occupier(pid: int) -> String:
	return _province_occupier.get(pid, "")

func is_province_modified(pid: int) -> bool:
	return _id_to_name.has(pid) or _province_owner.has(pid)

func get_province_count() -> int:
	return _province_count

func get_occupied_count() -> int:
	return _province_occupier.size()

func get_modified_count() -> int:
	var s := {}
	for id in _id_to_name:
		s[id] = true
	for id in _province_owner:
		s[id] = true
	return s.size()


# ══════════════════════════════════════════════════════════════════════════════
#  HOVER / SELECTION  (called by the 3D main script)
# ══════════════════════════════════════════════════════════════════════════════

## Set the hovered province (shader highlight).  Pass -1 to clear.
func set_hovered_province(pid: int) -> void:
	if pid == _hovered_id:
		return
	_hovered_id = pid
	_set_shader_param("hover_id", _id_to_shader_vec(pid))
	province_hovered.emit(pid)


## Set the selected province (shader highlight).  Pass -1 to clear.
func set_selected_province(pid: int) -> void:
	_selected_id = pid
	_set_shader_param("selected_id", _id_to_shader_vec(pid))


# ══════════════════════════════════════════════════════════════════════════════
#  SAVE / LOAD
# ══════════════════════════════════════════════════════════════════════════════

func save_to_file(path: String) -> void:
	var data := serialize_state()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if not file:
		push_error("ProvinceMap: can't write to %s" % path)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	print("ProvinceMap: saved → %s  (%d owners, %d provinces)" % [
		path, data["owners"].size(), data["provinces"].size()])


func load_from_file(path: String) -> void:
	_owners.clear()
	_next_owner_uid = 1
	_province_owner.clear()
	_province_occupier.clear()
	_id_to_name.clear()
	_lookup_image.fill(default_province_color)
	_owner_lookup_image.fill(default_province_color)

	_apply_file(path)

	_selected_id = -1
	_set_shader_param("selected_id", Vector2(-1, -1))
	owners_changed.emit()
	data_changed.emit()
	print("ProvinceMap: loaded ← %s  (%d owners)" % [path, _owners.size()])


# ══════════════════════════════════════════════════════════════════════════════
#  NETWORK SERIALIZATION
# ══════════════════════════════════════════════════════════════════════════════

## Serialize the current map state to a Dictionary (same format as the JSON
## save file).  Used by the network layer to replicate state.
func serialize_state() -> Dictionary:
	var owners_arr := []
	for oid in _owners:
		var o: Dictionary = _owners[oid]
		owners_arr.append({
			"id": oid,
			"name": o["name"],
			"color": (o["color"] as Color).to_html(false),
		})

	var prov_arr := []
	var written_pids := {}
	for pid in _province_owner:
		written_pids[pid] = true
	for pid in _id_to_name:
		written_pids[pid] = true
	for pid: int in written_pids:
		var entry := {}
		entry["map_color"] = get_province_map_color(pid).to_html(false)
		if _id_to_name.has(pid):
			entry["name"] = _id_to_name[pid]
		if _province_owner.has(pid):
			entry["owner"] = _province_owner[pid]
		if _province_occupier.has(pid):
			entry["occupier"] = _province_occupier[pid]
		prov_arr.append(entry)

	return { "owners": owners_arr, "provinces": prov_arr }


## Apply a full state Dictionary received from the network.
## Replaces all owners, provinces, names, and occupation data.
func apply_state(data: Dictionary) -> void:
	_owners.clear()
	_next_owner_uid = 1
	_province_owner.clear()
	_province_occupier.clear()
	_id_to_name.clear()

	if _is_built:
		_lookup_image.fill(default_province_color)
		_owner_lookup_image.fill(default_province_color)

	_apply_data(data)

	_selected_id = -1
	if _is_built:
		_set_shader_param("selected_id", Vector2(-1, -1))
	owners_changed.emit()
	data_changed.emit()
	print("ProvinceMap: applied network state (%d owners)" % [_owners.size()])


# ══════════════════════════════════════════════════════════════════════════════
#  PRIVATE
# ══════════════════════════════════════════════════════════════════════════════

func _apply_file(path: String) -> void:
	if not FileAccess.file_exists(path):
		push_warning("ProvinceMap: file not found — %s" % path)
		return
	var file := FileAccess.open(path, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		push_error("ProvinceMap: JSON error — %s" % json.get_error_message())
		return
	_apply_data(json.data)


## Apply a parsed JSON dictionary to the map.
## Shared by _apply_file() and apply_state().
func _apply_data(data: Dictionary) -> void:
	if data.has("owners"):
		for entry: Dictionary in data["owners"]:
			var oid: String = entry.get("id", "")
			var oname: String = entry.get("name", "")
			var chex: String = entry.get("color", "")
			if oid.is_empty() or oname.is_empty() or chex.is_empty():
				continue
			_owners[oid] = { "name": oname, "color": Color.html(chex) }
			if oid.begins_with("owner_"):
				var num := oid.get_slice("_", 1).to_int()
				if num >= _next_owner_uid:
					_next_owner_uid = num + 1

	if data.has("provinces"):
		for entry: Dictionary in data["provinces"]:
			var map_hex: String = entry.get("map_color", "")
			if map_hex.is_empty():
				continue
			var src := Color.html(map_hex)
			var key: int = _color_key(src)
			if not _color_to_id.has(key):
				continue
			var pid: int = _color_to_id[key]

			var pname: String = entry.get("name", "")
			if not pname.is_empty():
				_id_to_name[pid] = pname

			var owner_id: String = entry.get("owner", "")
			if not owner_id.is_empty() and _owners.has(owner_id):
				_province_owner[pid] = owner_id

			var occ_id: String = entry.get("occupier", "")
			if not occ_id.is_empty() and _owners.has(occ_id):
				_province_occupier[pid] = occ_id

			_refresh_province(pid)

	_flush_lookups()


func _refresh_province(pid: int) -> void:
	var owner_id: String = _province_owner.get(pid, "")
	var occ_id: String   = _province_occupier.get(pid, "")

	if owner_id.is_empty() or not _owners.has(owner_id):
		_set_ctrl_pixel(pid, default_province_color)
		_set_owner_pixel(pid, default_province_color)
		return

	var owner_col: Color = _owners[owner_id]["color"]
	_set_owner_pixel(pid, owner_col)

	if not occ_id.is_empty() and _owners.has(occ_id) and occ_id != owner_id:
		_set_ctrl_pixel(pid, _owners[occ_id]["color"])
	else:
		_set_ctrl_pixel(pid, owner_col)


func _flush_lookups() -> void:
	_lookup_texture.update(_lookup_image)
	_owner_lookup_texture.update(_owner_lookup_image)


func _set_ctrl_pixel(pid: int, color: Color) -> void:
	_lookup_image.set_pixel(pid % 256, (pid / 256) % 256, color)

func _set_owner_pixel(pid: int, color: Color) -> void:
	_owner_lookup_image.set_pixel(pid % 256, (pid / 256) % 256, color)

func _color_key(c: Color) -> int:
	return int(c.r * 255.0) | (int(c.g * 255.0) << 8) | (int(c.b * 255.0) << 16)

func _id_to_shader_vec(id: int) -> Vector2:
	if id < 0:
		return Vector2(-1.0, -1.0)
	return Vector2(float(id % 256) / 255.0, float((id / 256) % 256) / 255.0)

func _set_shader_param(param: StringName, value: Variant) -> void:
	if material_override is ShaderMaterial:
		(material_override as ShaderMaterial).set_shader_parameter(param, value)
