extends SceneTree
var _f := 0
var _room: Node2D
func _big(x: float, y: float) -> Vector2:
	var fx: float = x * 4 + 1.5
	var fy: float = y * 4 + 1.5
	return Vector2((fx - fy) * 12.0 + 12.0, (fx + fy) * 6.0 + 6.0)
func _process(_d: float) -> bool:
	_f += 1
	if _f == 1:
		_room = (load("res://levels/street.tscn") as PackedScene).instantiate()
		root.add_child(_room)
		current_scene = _room
		return false
	if _f < 20:
		return false
	var mgr = root.get_node_or_null("/root/IsoSortingManager")
	var doc: Node2D = _room.get_node("Player")
	var sorter: IsoSorter = doc.get_node("IsoSorter")
	var panels := _room.get_node("Walls").get_children()
	var bad := {}
	var spots := 0
	for xi in range(0, 93):
		for yi in range(6, 15):
			var p := _big(xi * 0.25, yi * 0.25)
			doc.global_position = p
			mgr._process(0.016)
			spots += 1
			var db: Rect2 = sorter.get_bounds()
			for c in panels:
				var cs: IsoSorter = c.get_node("IsoSorter")
				var pts: Array = cs.get_sort_points()
				var a: Vector2 = pts[0]
				var b: Vector2 = pts[1]
				# positive cross = the character stands SOUTH of the wall, so in front
				if (b - a).cross(p - a) <= 0.0:
					continue
				if not cs.get_bounds().intersects(db):
					continue                      # art does not overlap: invisible either way
				if c.z_index < doc.z_index:
					continue                      # correctly behind
				if not bad.has(c.name):
					bad[c.name] = 0
				bad[c.name] += 1
	var keys := bad.keys()
	keys.sort()
	for k in keys:
		print("%s draws over the character at %d standing spots" % [k, bad[k]])
	print("spots tested: %d, panels that visibly clip: %d" % [spots, keys.size()])
	quit()
	return true
