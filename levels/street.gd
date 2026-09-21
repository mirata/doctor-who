extends Node2D

## A tile level whose depth comes from the IsoSorter, not from Y-sorting.
##
## Y-sort judges a sprite by a single point, which a long wall does not have —
## its depth is the LINE of its foot, and a character standing near one end of
## a panel sorts wrong against a point taken from the middle. The wall panels
## therefore carry `IsoSorter` in LINE mode, and once anything in the scene
## uses it everything that interleaves with it has to, since IsoSorter writes
## `z_index` every frame and that overrides Y-sort entirely.
##
## The floor, decals and kerbs are exempt: they are TileMapLayers pinned below
## everything that walks (z −100/−99/−50), so they never enter the sort.
##
## The characters' sorters must be switched on explicitly. `IsoSorter` reads
## `enabled` in its own `_ready`, which runs before this one, and a property
## override set while building the scene is not serialised onto a node inside
## an instanced scene — so the flag cannot simply be authored into the .tscn.

func _ready() -> void:
	_set_iso_sorters(self, true)


func _set_iso_sorters(node: Node, on: bool) -> void:
	for child in node.get_children():
		if child is IsoSorter:
			(child as IsoSorter).enabled = on
		else:
			_set_iso_sorters(child, on)


# ── Sorting trace ─────────────────────────────────────────────────────────────
# Keeps the last few seconds of sorting state in `user://sort_trace.txt`, which
# is rewritten as it goes. Play until something sorts wrongly, then read the
# file: it holds what was happening just before, which is the only way to catch
# something that will not reproduce on demand.
#
# Each frame records, per character, every occluder overlapping them and two
# numbers that should never disagree:
#   cmp   what IsoSortingManager's own comparison says (+1 = character is in
#         front of it, -1 = behind). Computed with the manager's logic, not a
#         guess at what the geometry ought to mean.
#   z     the z_index each actually got.
# `cmp=+1` with the occluder's z ABOVE the character's is a real fault, and is
# tagged WRONG.

@export_category("Sorting trace")
## Writes user://sort_trace.txt. Costs a little every frame; turn it off when
## not hunting something.
@export var trace_sorting: bool = true
## How much of a character an occluder must cover to be worth recording.
@export var trace_min_overlap: float = 0.08
## How many frames of history the file holds. At 60 fps, 600 is ten seconds.
@export var trace_frames: int = 600
## Stop recording once a fault is caught, so the moment is not rolled over by
## whatever happens next. Without this you have to notice and quit within the
## length of the buffer.
@export var trace_latch_on_fault: bool = true

const TRACE_PATH := "user://sort_trace.txt"

var _trace: Array[String] = []
var _occluders: Array = []
var _movers: Array = []
var _frame: int = 0
var _since_flush: int = 0
var _latched: bool = false
var _after_fault: int = 0


func _sorter_of(n: Node) -> IsoSorter:
	for c in n.get_children():
		if c is IsoSorter:
			return c
	return null


func _collect_traceables() -> void:
	_occluders.clear()
	for group in ["Walls", "Props"]:
		var parent := get_node_or_null(group)
		if parent == null:
			continue
		for c in parent.get_children():
			if c is Sprite2D and _sorter_of(c) != null:
				_occluders.append(c)
	_movers.clear()
	for c in get_children():
		if c is CharacterBody2D and _sorter_of(c) != null:
			_movers.append(c)


## Big-cell coordinates, which the build's maps are indexed by.
##
## Derived from the layers rather than hard-coded: the fine grid and SUB have
## both moved before now, and a trace that quietly reports the wrong cell is
## worse than no trace.
func _big_cell(p: Vector2) -> Vector2:
	var fine := get_node_or_null("Nav") as TileMapLayer
	var floors := get_node_or_null("Floor") as TileMapLayer
	if fine == null or floors == null:
		return Vector2.ZERO
	var g: Vector2i = fine.tile_set.tile_size
	var big: Vector2i = floors.tile_set.tile_size
	var sub: float = float(big.x) / float(g.x)
	var fx: float = (p.x - g.x * 0.5) / (g.x * 0.5)
	var fy: float = (p.y - g.y * 0.5) / (g.y * 0.5)
	var half: float = (sub - 1.0) * 0.5
	return Vector2(((fx + fy) / 2.0 - half) / sub, ((fy - fx) / 2.0 - half) / sub)


func _process(_delta: float) -> void:
	if not trace_sorting or _latched:
		return
	if _movers.is_empty():
		_collect_traceables()
		if _movers.is_empty():
			return
	_frame += 1

	var mgr := get_node_or_null("/root/IsoSortingManager")
	var broken: int = 0
	if mgr != null:
		broken = int(mgr.get("debug_cycles_broken"))

	var faults := 0
	var parts: Array[String] = []
	for who in _movers:
		var ws := _sorter_of(who)
		var wb: Rect2 = ws.get_bounds()
		var area: float = wb.size.x * wb.size.y
		if area <= 0.0:
			continue
		var at: Vector2 = _big_cell(who.global_position)
		var line := "  %s big(%.2f,%.2f) z=%d" % [who.name, at.x, at.y, who.z_index]
		for c in _occluders:
			var ov: Rect2 = _sorter_of(c).get_bounds().intersection(wb)
			if ov.size.x <= 0.0 or ov.size.y <= 0.0:
				continue
			var frac: float = (ov.size.x * ov.size.y) / area
			if frac < trace_min_overlap:
				continue
			# the manager's own verdict, so the trace cannot disagree with it
			# for the reason a hand-rolled predicate would
			var cmp: int = IsoSortingManager._compare(ws, _sorter_of(c))
			var wrong: bool = cmp == 1 and c.z_index > who.z_index
			if wrong:
				faults += 1
			line += "\n      %s%-22s z=%-4d covers=%3d%% cmp=%+d" % [
				"WRONG " if wrong else "      ", c.name, c.z_index,
				int(frac * 100), cmp]
		parts.append(line)

	var header := "f=%d cycles_broken=%d%s" % [
		_frame, broken, "   <<< FAULT" if faults > 0 else ""]
	_trace.append(header + "\n" + "\n".join(parts))
	while _trace.size() > trace_frames:
		_trace.pop_front()

	# keep a moment of the aftermath, then stop so the buffer holds the event
	if faults > 0 and trace_latch_on_fault and _after_fault == 0:
		_after_fault = 1
	if _after_fault > 0:
		_after_fault += 1
		if _after_fault > 30:
			_latched = true
			_flush()
			print("[trace] fault caught at frame %d - recording stopped, see %s"
				% [_frame, TRACE_PATH])
			return

	_since_flush += 1
	if _since_flush >= 15:
		_since_flush = 0
		_flush()


func _flush() -> void:
	var f := FileAccess.open(TRACE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_line("sorting trace - last %d frames, newest last" % _trace.size())
	f.store_line("WRONG = the sorter says the character is in front (cmp=+1)")
	f.store_line("        yet the occluder was given a higher z_index.")
	f.store_line("")
	for entry in _trace:
		f.store_line(entry)
	f.close()
