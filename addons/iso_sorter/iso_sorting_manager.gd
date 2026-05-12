extends Node

var _floor: Array = []
var _static: Array = []
var _movable: Array = []

var _static_deps: Dictionary = {}

var _dfs_color: Dictionary = {}
var _dfs_parent: Dictionary = {}
var _dfs_deps: Dictionary = {}
var _dfs_cycle_start = null
var _dfs_cycle_end = null

const Z_FLOOR_BASE := -1000
const Z_BASE := 0
const Z_STEP := 2


func register_sorter(sorter: IsoSorter) -> void:
	if sorter.render_below_all:
		if not sorter in _floor:
			_floor.append(sorter)
	elif sorter.is_movable:
		if not sorter in _movable:
			_movable.append(sorter)
			(sorter.get_parent() as CanvasItem).z_as_relative = false
	else:
		if not sorter in _static:
			_static.append(sorter)
			(sorter.get_parent() as CanvasItem).z_as_relative = false
			_rebuild_static_deps()


func unregister_sorter(sorter: IsoSorter) -> void:
	_floor.erase(sorter)
	_static.erase(sorter)
	_movable.erase(sorter)
	_static_deps.erase(sorter)
	_rebuild_static_deps()


func _process(_delta: float) -> void:
	for i in _floor.size():
		_set_z(_floor[i], Z_FLOOR_BASE + i)

	var all: Array = _static + _movable
	var deps: Dictionary = {}
	for s in all:
		deps[s] = []

	for s in _static:
		if _static_deps.has(s):
			for dep in _static_deps[s]:
				if dep in all:
					(deps[s] as Array).append(dep)

	for a in _movable:
		for b in all:
			if a == b:
				continue
			if not _bounds_intersect(a, b):
				continue
			var cmp := _compare(a, b)
			if cmp == 1:
				if not b in deps[a]:
					(deps[a] as Array).append(b)
			elif cmp == -1:
				if deps.has(b) and not a in deps[b]:
					(deps[b] as Array).append(a)

	var sorted := _topological_sort(all, deps)
	var z := Z_BASE
	for s in sorted:
		_set_z(s, z)
		z += Z_STEP


# ── Dependency helpers ────────────────────────────────────────────────────────

func _rebuild_static_deps() -> void:
	_static_deps.clear()
	for s in _static:
		_static_deps[s] = []
	for i in _static.size():
		var a = _static[i]
		for j in range(i + 1, _static.size()):
			var b = _static[j]
			if not _bounds_intersect(a, b):
				continue
			var cmp := _compare(a, b)
			if cmp == 1:
				(_static_deps[a] as Array).append(b)
			elif cmp == -1:
				(_static_deps[b] as Array).append(a)


static func _set_z(sorter: IsoSorter, z: int) -> void:
	var p = sorter.get_parent()
	if p is CanvasItem:
		(p as CanvasItem).z_index = z


static func _bounds_intersect(a: IsoSorter, b: IsoSorter) -> bool:
	return a.get_bounds().intersects(b.get_bounds())


# Returns  1 if a is in front of b (higher z),
#         -1 if a is behind b,
#          0 if equal / unknown.
static func _compare(a: IsoSorter, b: IsoSorter) -> int:
	var at := a.sort_type
	var bt := b.sort_type
	if at == IsoSorter.SortType.POINT and bt == IsoSorter.SortType.POINT:
		var ay := a.get_sort_point_1().y
		var by := b.get_sort_point_1().y
		if ay > by: return 1
		if ay < by: return -1
		return 0
	elif at == IsoSorter.SortType.LINE and bt == IsoSorter.SortType.LINE:
		return _compare_pts_pts(a.get_sort_points(), b.get_sort_points())
	elif at == IsoSorter.SortType.POINT and bt == IsoSorter.SortType.LINE:
		return _compare_point_pts(a.get_sort_point_1(), b.get_sort_points())
	else:
		return -_compare_point_pts(b.get_sort_point_1(), a.get_sort_points())


# Is `point` in front of the polyline defined by `pts`?
# Finds the segment whose x-range best covers point.x, then interpolates y.
static func _compare_point_pts(point: Vector2, pts: Array) -> int:
	var n := pts.size()
	if n == 0:
		return 0
	if n == 1:
		return 1 if point.y > (pts[0] as Vector2).y else -1

	var best_seg := 0
	var best_dist := INF
	for i in range(n - 1):
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var lo_x := min(a.x, b.x)
		var hi_x := max(a.x, b.x)
		if point.x >= lo_x and point.x <= hi_x:
			best_seg = i
			best_dist = 0.0
			break
		var d := min(abs(point.x - lo_x), abs(point.x - hi_x))
		if d < best_dist:
			best_dist = d
			best_seg = i

	var pa: Vector2 = pts[best_seg]
	var pb: Vector2 = pts[best_seg + 1]
	if abs(pb.x - pa.x) < 0.001:
		return 1 if point.y > (pa.y + pb.y) * 0.5 else -1
	var slope := (pb.y - pa.y) / (pb.x - pa.x)
	var y_on_line := pa.y + slope * (point.x - pa.x)
	return 1 if point.y > y_on_line else -1


# Compares two polylines by sampling each set of endpoints against the other.
static func _compare_pts_pts(a_pts: Array, b_pts: Array) -> int:
	var a_votes := 0
	for pt in a_pts:
		a_votes += _compare_point_pts(pt, b_pts)

	# b_votes > 0 means b's points are in front of a's line → a is behind
	var b_votes := 0
	for pt in b_pts:
		b_votes += _compare_point_pts(pt, a_pts)

	var a_vs_b := 0
	if a_votes > 0: a_vs_b = 1
	elif a_votes < 0: a_vs_b = -1

	var b_vs_a := 0
	if b_votes > 0: b_vs_a = -1
	elif b_votes < 0: b_vs_a = 1

	if a_vs_b != 0 and b_vs_a != 0 and a_vs_b == b_vs_a:
		return a_vs_b
	if a_vs_b != 0:
		return a_vs_b
	if b_vs_a != 0:
		return b_vs_a

	var sum_a := 0.0
	for p in a_pts:
		sum_a += (p as Vector2).y
	var sum_b := 0.0
	for p in b_pts:
		sum_b += (p as Vector2).y
	var avg_a := sum_a / a_pts.size()
	var avg_b := sum_b / b_pts.size()
	if avg_a > avg_b: return 1
	if avg_a < avg_b: return -1
	return 0


static func _avg_sort_x(sorter: IsoSorter) -> float:
	if sorter.sort_type == IsoSorter.SortType.LINE:
		var pts := sorter.get_sort_points()
		if pts.is_empty():
			return sorter.get_sort_point_1().x
		var sum := 0.0
		for p in pts:
			sum += p.x
		return sum / pts.size()
	return sorter.get_sort_point_1().x


# ── Topological sort ──────────────────────────────────────────────────────────

func _topological_sort(nodes: Array, deps: Dictionary) -> Array:
	_break_cycles(nodes, deps)
	var visited: Dictionary = {}
	var result: Array = []
	for n in nodes:
		_topo_visit(n, deps, visited, result)
	return result


func _topo_visit(node: Object, deps: Dictionary, visited: Dictionary, result: Array) -> void:
	if visited.has(node):
		return
	visited[node] = true
	for dep in deps.get(node, []):
		_topo_visit(dep, deps, visited, result)
	result.append(node)


func _break_cycles(nodes: Array, deps: Dictionary) -> void:
	for _pass in range(5):
		var cycle := _find_cycle(nodes, deps)
		if cycle.is_empty():
			return
		var best_from = null
		var best_to = null
		var best_dx := -1.0
		for i in cycle.size():
			var from_node: IsoSorter = cycle[i]
			var to_node: IsoSorter = cycle[(i + 1) % cycle.size()]
			var dx := abs(_avg_sort_x(from_node) - _avg_sort_x(to_node))
			if dx > best_dx:
				best_dx = dx
				best_from = from_node
				best_to = to_node
		if best_to != null and deps.has(best_to):
			(deps[best_to] as Array).erase(best_from)


func _find_cycle(nodes: Array, deps: Dictionary) -> Array:
	_dfs_color = {}
	_dfs_parent = {}
	_dfs_deps = deps
	_dfs_cycle_start = null
	_dfs_cycle_end = null

	for n in nodes:
		if not _dfs_color.has(n) or _dfs_color[n] == 0:
			if _dfs(n):
				break

	if _dfs_cycle_start == null:
		return []

	var cycle: Array = []
	var cur = _dfs_cycle_end
	while cur != _dfs_cycle_start:
		cycle.append(cur)
		cur = _dfs_parent.get(cur)
		if cur == null:
			break
	if cur == _dfs_cycle_start:
		cycle.append(_dfs_cycle_start)
	cycle.reverse()
	return cycle


func _dfs(node: Object) -> bool:
	_dfs_color[node] = 1
	for dep in _dfs_deps.get(node, []):
		var dep_color: int = _dfs_color.get(dep, 0)
		if dep_color == 0:
			_dfs_parent[dep] = node
			if _dfs(dep):
				return true
		elif dep_color == 1:
			_dfs_cycle_end = node
			_dfs_cycle_start = dep
			return true
	_dfs_color[node] = 2
	return false
