extends Node
## Dynamic PCK Package Manager for Metaversum-Salihanum (Godot 4).
##
## On connect, the server sends a manifest listing available .pck packages
## with version strings. This manager compares each entry against a locally
## cached manifest (user://pck_manifest.json). If a package is missing or
## its version differs, only that package is re-downloaded via HTTP.
##
## While downloading, a loading overlay is displayed matching the project's
## Loading.tscn style (semi-transparent panel, Tahoma Bold, progress bar).
##
## After all downloads finish, each .pck is loaded with
## ProjectSettings.load_resource_pack() so its resources become available
## at their original res:// paths.

# ── Signals ──────────────────────────────────────────────────────────────────

## Emitted when all packages are verified/downloaded and loaded.
signal all_packs_loaded

## Emitted after a single package finishes downloading and is loaded.
signal pack_downloaded(pack_name: String)

## Emitted when a download or load fails for a package.
signal pack_load_failed(pack_name: String, error: String)

## Emitted while a package is being downloaded (0.0 – 1.0).
signal download_progress(pack_name: String, percent: float)

# ── Constants / paths ────────────────────────────────────────────────────────

const LOCAL_MANIFEST_PATH = "user://pck_manifest.json"
const PCK_DIR = "user://pck_packages/"

# ── State ────────────────────────────────────────────────────────────────────

var _local_manifest: Dictionary = {}     # Mirrors structure of server manifest
var _server_manifest: Dictionary = {}    # Last manifest received from server
var _download_queue: Array = []          # Packs waiting to be downloaded
var _is_downloading: bool = false        # True while an HTTPRequest is active
var _download_base_url: String = ""      # e.g. "https://domain:8080/pck/"
var _current_http: HTTPRequest = null    # Active HTTPRequest node (for progress)
var _current_pack_name: String = ""      # Name of the pack currently downloading
var _loaded_packs: Dictionary = {}       # pack_name -> true (already loaded this session)

# Download tracking for the loading screen
var _total_to_download: int = 0          # Total packages that needed downloading
var _downloaded_count: int = 0           # How many have finished so far

# ── Loading screen nodes ─────────────────────────────────────────────────────

var _loading_overlay: CanvasLayer = null
var _loading_panel: ColorRect = null
var _loading_label: Label = null
var _progress_bar: ProgressBar = null

# ── Lifecycle ────────────────────────────────────────────────────────────────

func _ready():
	_ensure_pck_directory()
	_load_local_manifest()
	print("[PCK Manager] Ready. Local manifest has ",
		  _local_manifest.get("packages", {}).size(), " cached package(s)")

func _process(_delta):
	# Report download progress and update loading screen
	if _current_http and is_instance_valid(_current_http) and _current_pack_name != "":
		var body_size = _current_http.get_body_size()
		var downloaded_bytes = _current_http.get_downloaded_bytes()
		if body_size > 0:
			var pct = float(downloaded_bytes) / float(body_size)
			download_progress.emit(_current_pack_name, pct)
			_update_loading_screen(pct, downloaded_bytes, body_size)

# ── Directory / manifest helpers ─────────────────────────────────────────────

func _ensure_pck_directory():
	var dir = DirAccess.open("user://")
	if dir and not dir.dir_exists("pck_packages"):
		dir.make_dir("pck_packages")

func _load_local_manifest():
	if FileAccess.file_exists(LOCAL_MANIFEST_PATH):
		var file = FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.READ)
		if file:
			var json = JSON.new()
			if json.parse(file.get_as_text()) == OK:
				_local_manifest = json.data
			file.close()

	# Ensure structure
	if not _local_manifest.has("packages"):
		_local_manifest = {"packages": {}}

func _save_local_manifest():
	var file = FileAccess.open(LOCAL_MANIFEST_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(_local_manifest, "\t"))
		file.close()

# ── Loading screen UI ────────────────────────────────────────────────────────
# Faithfully recreates res://src/scenes/Loading.tscn:
#   - No background dimmer – panel floats directly over the game
#   - ColorRect: Color(0.502, 0.502, 0.502, 0.502) – 50% gray, 50% alpha
#   - Offsets: left +202, top +294, right -202, bottom -294
#   - Label: Tahoma Bold, size 24, centered, word-wrap
#   - Progress bar inside the panel, styled to match the gray theme

func _show_loading_screen():
	if _loading_overlay != null:
		return  # Already showing

	# CanvasLayer on top of everything
	_loading_overlay = CanvasLayer.new()
	_loading_overlay.layer = 100
	add_child(_loading_overlay)

	# No dimmer – matching Loading.tscn which has no background overlay

	# Centered semi-transparent panel – exact Loading.tscn values
	_loading_panel = ColorRect.new()
	_loading_panel.anchor_left = 0.0
	_loading_panel.anchor_top = 0.0
	_loading_panel.anchor_right = 1.0
	_loading_panel.anchor_bottom = 1.0
	_loading_panel.offset_left = 202.0
	_loading_panel.offset_top = 294.0
	_loading_panel.offset_right = -202.0
	_loading_panel.offset_bottom = -294.0
	_loading_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_loading_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	# Exact Loading.tscn color: Color(0.502, 0.502, 0.502, 0.502)
	_loading_panel.color = Color(0.502, 0.502, 0.502, 0.502)
	_loading_overlay.add_child(_loading_panel)

	# VBox fills the panel to stack label + bar vertically
	var vbox = VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_FULL_RECT)
	vbox.offset_left = 16.0
	vbox.offset_top = 12.0
	vbox.offset_right = -16.0
	vbox.offset_bottom = -12.0
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 8)
	_loading_panel.add_child(vbox)

	# Main status label – matches Loading.tscn layout exactly
	_loading_label = Label.new()
	_loading_label.text = "Loaded: 0 Downloaded: 0\n\nDownloading..."
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_loading_label.add_theme_font_size_override("font_size", 18)
	_loading_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_try_set_bold_font(_loading_label)
	vbox.add_child(_loading_label)

	# Progress bar – inside the panel, gray theme
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 14)
	_progress_bar.value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.show_percentage = false

	var bar_bg = StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.35, 0.35, 0.35, 0.6)
	bar_bg.corner_radius_top_left = 3
	bar_bg.corner_radius_top_right = 3
	bar_bg.corner_radius_bottom_left = 3
	bar_bg.corner_radius_bottom_right = 3
	_progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill = StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.75, 0.75, 0.75, 0.8)
	bar_fill.corner_radius_top_left = 3
	bar_fill.corner_radius_top_right = 3
	bar_fill.corner_radius_bottom_left = 3
	bar_fill.corner_radius_bottom_right = 3
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)
	vbox.add_child(_progress_bar)

func _try_set_bold_font(label: Label):
	"""Try to load Tahoma Bold (the project's UI font). Falls back to default."""
	var font_path = "res://src/fonts/tahomabd.ttf"
	if ResourceLoader.exists(font_path):
		var font = load(font_path)
		if font:
			label.add_theme_font_override("font", font)

func _update_loading_screen(pct: float, downloaded_bytes: int, total_bytes: int):
	if _loading_label == null:
		return

	var loaded_count = _loaded_packs.size()
	var percent_int = int(pct * 100.0)
	var dl_str = _format_bytes(downloaded_bytes)
	var total_str = _format_bytes(total_bytes)

	_loading_label.text = "Loaded: %d Downloaded: %d / %d\n\nDownloading %s... %d%% (%s / %s)" % [
		loaded_count, _downloaded_count, _total_to_download,
		_current_pack_name, percent_int, dl_str, total_str
	]

	if _progress_bar:
		_progress_bar.value = pct * 100.0

func _hide_loading_screen():
	if _loading_overlay != null:
		# Brief "complete" flash before removing
		if _loading_label:
			_loading_label.text = "All packages up to date!"
		if _progress_bar:
			_progress_bar.value = 100.0

		# Fade out after a short delay
		var tween = create_tween()
		tween.tween_interval(0.6)
		tween.tween_callback(func():
			if _loading_overlay and is_instance_valid(_loading_overlay):
				_loading_overlay.queue_free()
			_loading_overlay = null
			_loading_panel = null
			_loading_label = null
			_progress_bar = null
		)

func _format_bytes(bytes: int) -> String:
	if bytes >= 1048576:
		return "%.1f MB" % (bytes / 1048576.0)
	elif bytes >= 1024:
		return "%.0f KB" % (bytes / 1024.0)
	else:
		return "%d B" % bytes

# ── Main entry point (called by NetworkController) ──────────────────────────

func handle_server_manifest(data: Dictionary):
	"""Compare server manifest against local, queue downloads for mismatches."""
	_server_manifest = data
	_download_base_url = data.get("download_base_url", "")
	var server_packages: Dictionary = data.get("packages", {})
	var local_packages: Dictionary = _local_manifest.get("packages", {})

	_download_queue.clear()
	_downloaded_count = 0

	print("[PCK Manager] Server has ", server_packages.size(), " package(s)")

	# Check each server package against local state
	for pack_name in server_packages:
		var server_pack: Dictionary = server_packages[pack_name]
		var server_version: String = str(server_pack.get("version", "0"))
		var filename: String = server_pack.get("filename", pack_name + ".pck")

		var local_pack: Dictionary = local_packages.get(pack_name, {})
		var local_version: String = str(local_pack.get("version", ""))

		var pck_path: String = PCK_DIR + filename
		var needs_download: bool = false

		if local_version != server_version:
			needs_download = true
			print("[PCK Manager] Version mismatch for '", pack_name,
				  "': local=", local_version, " server=", server_version)
		elif not FileAccess.file_exists(pck_path):
			needs_download = true
			print("[PCK Manager] File missing for '", pack_name, "': ", pck_path)

		if needs_download:
			_download_queue.append({
				"name": pack_name,
				"filename": filename,
				"version": server_version,
				"url": _download_base_url + filename
			})
		else:
			# Already up-to-date – just make sure it's loaded this session
			if not _loaded_packs.has(pack_name):
				_load_pck(pack_name, pck_path)

	# Remove packages no longer on the server
	var to_remove: Array = []
	for pack_name in local_packages:
		if not server_packages.has(pack_name):
			to_remove.append(pack_name)
			var filename: String = local_packages[pack_name].get("filename", pack_name + ".pck")
			var pck_path: String = PCK_DIR + filename
			if FileAccess.file_exists(pck_path):
				DirAccess.remove_absolute(pck_path)
				print("[PCK Manager] Removed obsolete package: ", pack_name)
			# Also remove any instantiated scene from the workspace
			remove_pack_scene(pack_name)

	for pack_name in to_remove:
		_local_manifest["packages"].erase(pack_name)

	# Start downloading or signal completion
	if _download_queue.is_empty():
		print("[PCK Manager] All packages up to date")
		_save_local_manifest()
		all_packs_loaded.emit()
	else:
		_total_to_download = _download_queue.size()
		print("[PCK Manager] Need to download ", _total_to_download, " package(s)")
		_show_loading_screen()
		_process_download_queue()

# ── Download pipeline ────────────────────────────────────────────────────────

func _process_download_queue():
	if _download_queue.is_empty():
		_save_local_manifest()
		print("[PCK Manager] All downloads complete")
		_hide_loading_screen()
		all_packs_loaded.emit()
		return

	if _is_downloading:
		return  # Will be called again when current download finishes

	var pack_info: Dictionary = _download_queue[0]
	_download_pack(pack_info)

func _download_pack(pack_info: Dictionary):
	var url: String = pack_info.url
	var filename: String = pack_info.filename
	var pck_path: String = PCK_DIR + filename

	print("[PCK Manager] Downloading: ", url)

	_is_downloading = true
	_current_pack_name = pack_info.name

	# Update loading screen immediately for new file
	if _loading_label:
		_loading_label.text = "Loaded: %d Downloaded: %d / %d\n\nDownloading %s..." % [
			_loaded_packs.size(), _downloaded_count, _total_to_download, _current_pack_name
		]
	if _progress_bar:
		_progress_bar.value = 0.0

	var http = HTTPRequest.new()
	http.download_file = pck_path
	# Allow large PCK files (up to 500 MB)
	http.download_chunk_size = 65536
	http.timeout = 300  # 5 minute timeout for large files
	add_child(http)
	_current_http = http

	http.request_completed.connect(
		func(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
			_current_http = null
			_current_pack_name = ""
			http.queue_free()
			_is_downloading = false

			if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
				print("[PCK Manager] Downloaded: ", filename)
				_downloaded_count += 1

				# Update local manifest
				if not _local_manifest.has("packages"):
					_local_manifest["packages"] = {}
				_local_manifest["packages"][pack_info.name] = {
					"version": pack_info.version,
					"filename": filename
				}

				# Load the PCK into the resource system
				_load_pck(pack_info.name, pck_path)
				pack_downloaded.emit(pack_info.name)
			else:
				var err_msg = "Download failed: result=%d HTTP %d" % [result, response_code]
				print("[PCK Manager] ", err_msg, " for ", filename)
				pack_load_failed.emit(pack_info.name, err_msg)

			# Move to next queued package
			_download_queue.remove_at(0)
			_process_download_queue()
	)

	var error = http.request(url)
	if error != OK:
		print("[PCK Manager] HTTP request error: ", error)
		_current_http = null
		_current_pack_name = ""
		http.queue_free()
		_is_downloading = false
		pack_load_failed.emit(pack_info.name, "HTTP request error: " + str(error))
		_download_queue.remove_at(0)
		_process_download_queue()

# ── PCK loading & scene instantiation ────────────────────────────────────────

func _load_pck(pack_name: String, pck_path: String):
	if _loaded_packs.has(pack_name):
		return  # Already loaded this session

	if ProjectSettings.load_resource_pack(pck_path):
		_loaded_packs[pack_name] = true
		print("[PCK Manager] Loaded resource pack: ", pack_name, " from ", pck_path)

		# If the manifest defines a scene_path, instantiate it into the workspace
		var scene_path = _get_pack_scene_path(pack_name)
		if scene_path != "":
			_instantiate_pack_scene(pack_name, scene_path)
	else:
		print("[PCK Manager] FAILED to load resource pack: ", pack_name, " from ", pck_path)
		pack_load_failed.emit(pack_name, "ProjectSettings.load_resource_pack() returned false")

func _get_pack_scene_path(pack_name: String) -> String:
	"""Look up the scene_path for a package from the server manifest."""
	var packages = _server_manifest.get("packages", {})
	var pack = packages.get(pack_name, {})
	return pack.get("scene_path", "")

func _instantiate_pack_scene(pack_name: String, scene_path: String):
	"""Load a scene from the PCK and add it to the workspace."""
	if not ResourceLoader.exists(scene_path):
		print("[PCK Manager] Scene not found in pack '", pack_name, "': ", scene_path)
		pack_load_failed.emit(pack_name, "Scene not found: " + scene_path)
		return

	var scene = load(scene_path)
	if not scene:
		print("[PCK Manager] Failed to load scene for '", pack_name, "': ", scene_path)
		pack_load_failed.emit(pack_name, "Failed to load scene: " + scene_path)
		return

	var instance = scene.instantiate()
	# Tag the node so we can identify/remove it later
	instance.set_meta("pck_pack_name", pack_name)
	instance.set_meta("pck_scene_path", scene_path)

	# Find the workspace to add it to
	var workspace = _find_workspace()
	if workspace:
		# Remove the Baseplate – it's the fallback floor that clashes with loaded maps
		var baseplate = workspace.get_node_or_null("Baseplate")
		if baseplate:
			baseplate.queue_free()
			print("[PCK Manager] Removed Baseplate (replaced by pack '", pack_name, "')")

		workspace.add_child(instance)
		print("[PCK Manager] Instantiated scene '", scene_path, "' from pack '",
			  pack_name, "' into workspace")
	else:
		# Fallback: add to scene root
		get_tree().current_scene.add_child(instance)
		print("[PCK Manager] Instantiated scene '", scene_path, "' from pack '",
			  pack_name, "' into current scene (no workspace found)")

func _find_workspace() -> Node:
	"""Find the workspace node in the scene tree."""
	var root = get_tree().get_root()
	var workspace = root.find_child("workspace", true, false)
	if not workspace:
		workspace = root.find_child("localworkspace", true, false)
	return workspace

func remove_pack_scene(pack_name: String):
	"""Remove an instantiated pack scene from the workspace (e.g. if pack is removed)."""
	var workspace = _find_workspace()
	if not workspace:
		workspace = get_tree().current_scene
	if not workspace:
		return

	for child in workspace.get_children():
		if child.has_meta("pck_pack_name") and child.get_meta("pck_pack_name") == pack_name:
			print("[PCK Manager] Removing scene for pack: ", pack_name)
			child.queue_free()
			return

# ── Public helpers ───────────────────────────────────────────────────────────

func is_pack_loaded(pack_name: String) -> bool:
	"""Check if a specific pack has been loaded this session."""
	return _loaded_packs.has(pack_name)

func get_loaded_packs() -> Array:
	"""Return list of pack names loaded this session."""
	return _loaded_packs.keys()

func get_local_version(pack_name: String) -> String:
	"""Return the locally cached version string for a package, or empty."""
	var packages = _local_manifest.get("packages", {})
	var pack = packages.get(pack_name, {})
	return str(pack.get("version", ""))

func is_downloading() -> bool:
	"""True if a download is currently in progress."""
	return _is_downloading

func get_download_queue_size() -> int:
	"""How many packages are still queued for download."""
	return _download_queue.size()
