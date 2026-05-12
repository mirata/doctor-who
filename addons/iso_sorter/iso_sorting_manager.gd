extends Node

# Sprites that always render behind everything else.
var _floor: Array = []
# Non-moving sprites — dependencies computed once on register/unregister.
var _static: Array = []
# Moving sprites — dependencies rebuilt every frame.
var _movable: Array = []

# _static_deps[sorter] = [sorters that must render before it] (static pairs only)
var _static_deps: Dictionary = {}

# DFS state reused across _find_cycle / _dfs calls to avoid recursive lambdas.
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
	# Floor sprites get fixed negative z-order.
	for i in _floor.size():
		_set_z(_floor[i], Z_FLOOR_BASE + i)

	# Build full dependency graph.
	var all: Array = _static + _movable
	var deps: Dictionary = {}
	for s in all:
		deps[s] = []

	# Copy pre-computed static deps.
	for s in _static:
		if _static_deps.has(s):
			for dep in _static_deps[s]:
				if dep in all:
					(deps[s] as Array).append(dep)

	# Add movable deps (against everything).
	for a in _movable:
		for b in all:
			if a == b:
				continue
			if not _bounds_intersect(a, b):
				continue
			var cmp := _compare(a, b)
			if cmp == 1:    # a in front of b → b must render before a
				if not b in deps[a]:
					(deps[a] as Array).append(b)
			elif cmp == -1: # b in front of a → a must render before b
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
		return _compare_line_line(a, b)
	elif at == IsoSorter.SortType.POINT and bt == IsoSorter.SortType.LINE:
		return _compare_point_line(a.get_sort_point_1(), b)
	else:
		return -_compare_point_line(b.get_sort_point_1(), a)


# Is `point` (the sprite it represents) in front of the `line` sprite?
# In Godot 2D: higher screen Y = closer to camera = in front.
static func _compare_point_line(point: Vector2, line: IsoSorter) -> int:
	var p1 := line.get_sort_point_1()
	var p2 := line.get_sort_point_2()
	var lo := min(p1.y, p2.y)
	var hi := max(p1.y, p2.y)
	if point.y > hi: return 1
	if point.y < lo: return -1
	# Point Y is between the two endpoints — use line equation.
	if abs(p2.x - p1.x) < 0.001:
		return 1 if point.y > (p1.y + p2.y) * 0.5 else -1
	var slope := (p2.y - p1.y) / (p2.x - p1.x)
	var y_on_line := p1.y + slope * (point.x - p1.x)
	return 1 if point.y > y_on_line else -1


static func _compare_line_line(a: IsoSorter, b: IsoSorter) -> int:
	var ra1 := _compare_point_line(a.get_sort_point_1(), b)
	var ra2 := _compare_point_line(a.get_sort_point_2(), b)
	var a_vs_b := ra1 if ra1 == ra2 else 0

	var rb1 := _compare_point_line(b.get_sort_point_1(), a)
	var rb2 := _compare_point_line(b.get_sort_point_2(), a)
	var b_vs_a := -rb1 if rb1 == rb2 else 0

	if a_vs_b != 0 and b_vs_a != 0 and a_vs_b == b_vs_a:
		return a_vs_b
	if a_vs_b != 0:
		return a_vs_b
	if b_vs_a != 0:
		return b_vs_a
	var avg_a := (a.get_sort_point_1().y + a.get_sort_point_2().y) * 0.5
	var avg_b := (b.get_sort_point_1().y + b.get_sort_point_2().y) * 0.5
	if avg_a > avg_b: return 1
	if avg_a < avg_b: return -1
	return 0


# ── Topological sort ──────────────────────────────────────────────────────────
# Uses regular methods instead of recursive lambdas (GDScript 4 closures
# capture the variable's value at creation time, so self-referential
# lambdas always see Callable() null).

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
			var dx := abs(from_node.get_sort_point_1().x - to_node.get_sort_point_1().x)
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


# DFS using instance state (_dfs_*) to avoid recursive lambda capture issue.
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
