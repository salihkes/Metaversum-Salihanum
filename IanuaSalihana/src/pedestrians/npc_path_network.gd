extends Node

## Builds a walkable graph from Path3D nodes placed in the scene.
##
## The developer draws Path3D curves (sidewalks, corridors, etc.) in the
## editor.  This script samples each curve at regular intervals, then
## auto-connects endpoints of different paths that are close together.
## NPCs query the resulting graph for routes between arbitrary positions.
##
## Usage:
##   1. Add Path3D nodes under a "Sidewalks" container (or anywhere in
##      the workspace — the script will find them).
##   2. Draw curves by clicking in the editor.
##   3. Drop this node into the workspace — graph builds automatically.

## How often to sample each curve (in local units).
@export var sample_interval := 5.0
## Endpoints closer than this are auto-connected across paths.
@export var connection_threshold := 3.0

# ── Graph data ──────────────────────────────────────────────────────
var _points: PackedVector3Array = PackedVector3Array()
var _edges: Dictionary = {}           # point_idx -> PackedInt32Array of neighbors
var _point_meta: Array[Dictionary] = []  # per-point metadata (path_idx, offset)

var _workspace: Node3D = null
var _built := false


func _ready():
	_workspace = get_parent()
	# Defer one frame so all Path3D nodes are ready
	await get_tree().process_frame
	rebuild()


# ════════════════════════════════════════════════════════════════════
#  GRAPH CONSTRUCTION
# ════════════════════════════════════════════════════════════════════

func rebuild():
	_points = PackedVector3Array()
	_edges.clear()
	_point_meta.clear()

	var paths: Array[Path3D] = []
	_collect_paths(get_parent(), paths)

	if paths.is_empty():
		print("[NpcPathNetwork] No Path3D nodes found — path navigation disabled")
		_built = false
		return

	# ── Sample each curve ───────────────────────────────────────────
	for path_idx in paths.size():
		var path: Path3D = paths[path_idx]
		var curve: Curve3D = path.curve
		if curve == null or curve.point_count < 2:
			continue

		var length := curve.get_baked_length()
		if length < 0.01:
			continue

		var num_samples := maxi(2, int(length / sample_interval) + 1)
		var first_idx := _points.size()

		for i in num_samples:
			var offset: float = float(i) / float(num_samples - 1) * length
			var local_pos: Vector3 = curve.sample_baked(offset)
			# Convert to workspace-local coordinates
			var ws_pos: Vector3 = _to_workspace(path, local_pos)

			var idx := _points.size()
			_points.append(ws_pos)
			_point_meta.append({"path": path_idx, "offset": offset})
			_edges[idx] = PackedInt32Array()

			# Connect to previous sample on same curve
			if i > 0:
				_connect(idx, idx - 1)

	# ── Auto-connect nearby points across different paths ───────────
	# Any two sample points from different paths that are within the
	# connection threshold get linked.  This handles T-intersections,
	# crossings, and paths that share a stretch.
	for i in _points.size():
		var pi: int = _point_meta[i]["path"]
		for j in range(i + 1, _points.size()):
			if _point_meta[j]["path"] == pi:
				continue  # same path — already connected sequentially
			if _edges[i].has(j):
				continue
			var dist := _points[i].distance_to(_points[j])
			if dist <= connection_threshold:
				_connect(i, j)

	_built = true
	print("[NpcPathNetwork] Built graph: %d points, %d paths" % [_points.size(), paths.size()])


func _collect_paths(node: Node, out: Array[Path3D]):
	for child in node.get_children():
		if child is Path3D:
			out.append(child)
		elif not (child is CharacterBody3D):
			# Don't recurse into NPCs or players
			_collect_paths(child, out)


func _to_workspace(path: Path3D, local_pos: Vector3) -> Vector3:
	if _workspace == null:
		return local_pos
	return _workspace.to_local(path.to_global(local_pos))


func _connect(a: int, b: int):
	if not _edges[a].has(b):
		_edges[a].append(b)
	if not _edges[b].has(a):
		_edges[b].append(a)


# ════════════════════════════════════════════════════════════════════
#  PUBLIC API
# ════════════════════════════════════════════════════════════════════

func has_paths() -> bool:
	return _built and _points.size() > 0


func nearest_point_index(pos: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in _points.size():
		var d := pos.distance_to(_points[i])
		if d < best_d:
			best_d = d
			best = i
	return best


func nearest_point_position(pos: Vector3) -> Vector3:
	var idx := nearest_point_index(pos)
	if idx >= 0:
		return _points[idx]
	return pos


func find_route(from: Vector3, to: Vector3) -> Array[Vector3]:
	"""Return a list of workspace-local positions leading from `from` to `to`,
	   following the path network.  Falls back to [to] if no path exists."""
	if not _built or _points.size() == 0:
		return [to]

	var start := nearest_point_index(from)
	var goal := nearest_point_index(to)
	if start < 0 or goal < 0:
		return [to]
	if start == goal:
		return [_points[goal], to]

	# ── BFS (edge weights are roughly uniform) ──────────────────────
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array[int] = [start]
	visited[start] = true
	parent[start] = -1
	var found := false

	while queue.size() > 0:
		var cur: int = queue.pop_front()
		if cur == goal:
			found = true
			break
		for nb in _edges.get(cur, PackedInt32Array()):
			if not visited.has(nb):
				visited[nb] = true
				parent[nb] = cur
				queue.append(nb)

	if not found:
		return [to]  # unreachable — direct walk

	# Reconstruct
	var route: Array[Vector3] = []
	var idx := goal
	while idx != -1:
		route.insert(0, _points[idx])
		idx = parent.get(idx, -1)

	# Append exact destination (waypoint may be off-path)
	route.append(to)
	return route


func random_point_near(pos: Vector3, radius: float) -> Vector3:
	"""Pick a random graph point within `radius` of `pos`.
	   Returns `pos` if no points are in range."""
	if not _built or _points.size() == 0:
		return pos

	var candidates: PackedInt32Array = PackedInt32Array()
	for i in _points.size():
		if pos.distance_to(_points[i]) <= radius:
			candidates.append(i)

	if candidates.is_empty():
		# No point in range — return nearest
		return nearest_point_position(pos)

	return _points[candidates[randi() % candidates.size()]]
