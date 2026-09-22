extends SceneTree

# Builds levels/street_tileset.tres and levels/street.tscn.
# Re-run with:
#   godot --headless --path . --script res://tools/build_street.gd
#
# Editing the generated scene in the editor is fine - just know re-running this
# overwrites it.
#
# TWO GRIDS
# ---------
# The map below is authored in BIG cells (96x48) because that is a comfortable
# size to lay a street out in. The TileMapLayers underneath run on a QUARTER
# grid (24x48 / 4 = 24x12), and each big floor cell is stamped as 4x4 of the
# sliced pieces that tools/make_tiles.py emits.
#
# That is what reconciles "floors are handy large" with "detail needs to be
# smaller": painting stays coarse, while collision, navigation and anything
# placed gets to work at a quarter of the tile.

const TILES_JSON := "res://sprites/street/tiles.json"
# One sheet per job. Anything not listed here is not placed by this build.
const FLOOR_SHEET := "res://sprites/street/floors.png"    # 96x48 floor diamonds
const DECAL_SHEET := "res://sprites/street/decals.png"    # 24x12 decal slices
const KERB_SHEET := "res://sprites/street/kerbs.png"      # 96x64 kerbs
const THIN_WALL_SHEET := "res://sprites/street/thin_walls.png"  # 24x36 low walls
const WALL_SHEET := "res://sprites/street/walls.png"
const FLOOR_TILESET_OUT := "res://levels/street_floor_tileset.tres"
const TILESET_OUT := "res://levels/street_tileset.tres"
const SCENE_OUT := "res://levels/street.tscn"
## Hand edits, re-applied after generating. The scene is regenerated from
## scratch every build, so anything tweaked in the editor would otherwise be
## lost; this is how a change survives. Capture new ones with
## tools/capture_edits.py, which diffs the scene against a pristine build.
const EDITS := "res://levels/street_edits.json"

var SUB := 4
var GRID := Vector2i(24, 12)        # the cell Godot lays down
var ART := Vector2i(96, 48)         # the drawn floor diamond

var GRID_TILES := {}                # name -> {atlas, layer, walkable, solid}
var QUARTER_ART := {}               # name -> Vector2i in the quarter sheet
var KERB_TILES := {}                # the subset placed as tiles, not sprites
var QUARTER_CELL := Vector2i(24, 36)
var KERB_CELL := Vector2i(96, 64)
var FLOOR_COORDS := {}              # floor name -> its 96x48 region in the sheet
var _carved := 0                    # floor cells taken out from under props

# ---------------------------------------------------------------- the map --
# One character per BIG cell.
const GROUND := [
	"BBBBBBBBBBBBBBBBBBBBBBBB",
	"BBBBBBBB....BBBBBBBBBBBB",
	"pppppppppppppppppppppppp",
	"ppppgppppppppppppppgpppp",
	"kkkkkkkkxxkkkkkkkkkkkkkk",
	"aabbaabbaabbmabbaabbaabb",
	"bbaabbaatbaabbaabbaatbaa",
	"aabbaaubaabbaabbauubaabb",
	"bbaabbaatbaabbmabbaatbaa",
	"aabbaabbaabbaabbaabbaabb",
	"kkkkkkkkkkkkkkxxkkkkkkkk",
	"ppppppppgppppppppppgpppp",
	"pppppppppppppppppppppppp",
	"BBBBBBBBBBBBBBBBBBBBBBBB",
]
const BLOCKS := [
	"WWWWWWWWWWWWWWWWWWWWWWWW",
	"WWWWWWWD....DWWWWWWWWWWW",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"........................",
	"SSSSSSSSSSSSSSSSSSSSSSSS",
]
## One big 96x48 tile per cell. Back on the big grid because that is the size
## a floor is comfortable to author and paint at; the fineness that the quarter
## grid bought has moved to the invisible navigation and collision layers,
## where it was the only thing that actually needed it.
const FLOOR_KEY := {
	"a": ["road_4", "road_5", "road_3"],
	"b": ["road_3", "road_4", "road_5"],
	"p": ["pave_4", "pave_5", "pave_3"],
	".": ["road_2", "road_3", "road_4"],
	"k": ["pave_4", "pave_5"],
	"x": ["pave_3", "pave_4"],
	"g": ["pave_2"],
	"m": ["road_2"],
	"u": ["shade_2"],
	"t": ["road_1"],
	"d": ["dirt_1", "dirt_2", "dirt_3"],
	"B": ["pave_4", "pave_5"],
}
# Only things that genuinely fill a tile belong here. Street furniture does
# not: a block is 96 px wide by definition, so a crate laid this way is the
# size of a garden shed. Those live in PROPS, sized by their own artwork.
const BLOCK_KEY := {
	"W": ["brick_wall", "brick_wall", "wall_window", "wall_poster", "wall_pipe"],
	"D": ["wall_door"],
	"S": ["stone_wall"],
}
# Kerbs sit on the floor map, so the ground layer gets a flat stand-in under
# them and the lip itself is painted on the Kerbs layer.
## Kerb variants, chosen per BIG cell rather than per fine cell: at quarter
## resolution there are 16 tiles to a big one, so rolling per tile scatters
## weeds and chips sixteen times as thickly and the kerb reads as speckled.
## Every pavement cell gets an edge tile, not just the row beside the road.
## The pavement IS the kerb: each tile hangs its drop below itself, the next
## pavement tile covers it, and only the boundary with the road shows a lip.
const KERB_KEY := {
	"p": ["pave_4_edge", "pave_5_edge", "pave_3_edge"],
	"B": ["pave_4_edge", "pave_5_edge"],
	"k": ["pave_4_edge", "pave_5_edge"],
	"x": ["pave_3_edge", "pave_4_edge"],
}

## Roughly what percentage of QUARTER floor cells get a decal.
const DECAL_DENSITY := 5

## Thin brick walls, laid a QUARTER cell at a time.
##
## `from`/`to` are in big cells and step by quarters. `axis` has to match the
## way the run travels - "a" for a run heading south-east, "b" for south-west -
## because these are drawn sprites, not something the projection can rotate.
const WALL_RUNS := [
	# the near-side boundary: knee-high, so it never hides a character
	{"axis": "a", "from": Vector2(0.0, 13.0), "to": Vector2(23.75, 13.0), "low": false},
	{"axis": "a", "from": Vector2(6.0, 3.0),   "to": Vector2(9.75, 3.0),  "low": true},
	{"axis": "b", "from": Vector2(9.75, 3.0),  "to": Vector2(9.75, 3.75), "low": true},
	{"axis": "a", "from": Vector2(13.0, 11.5), "to": Vector2(17.75, 11.5), "low": false},
	{"axis": "a", "from": Vector2(2.0, 11.5),  "to": Vector2(4.75, 11.5), "low": true},
]

## Free-standing props. `at` is in BIG cells but takes fractions - a quarter is
## 0.25 - so anything can sit anywhere without a nudge in raw pixels.
const PROPS := [
	# north pavement, west to east
	{"art": "barrel_right",    "at": Vector2(5.25, 2.3),   "blocks": 11},
	{"art": "barrel_left",     "at": Vector2(5.75, 2.6),   "blocks": 11},
	{"art": "cardboard_box",   "at": Vector2(6.5, 3.25),   "blocks": 11},
	{"art": "bollard",         "at": Vector2(7.5, 3.8),    "blocks": 5},
	{"art": "bollard",         "at": Vector2(8.5, 3.8),    "blocks": 5},
	{"art": "bollard",         "at": Vector2(9.5, 3.8),    "blocks": 5},
	{"art": "phone_box",       "at": Vector2(10.5, 2.4),   "blocks": 13},
	{"art": "trash_can",       "at": Vector2(11.5, 2.35),  "blocks": 9},
	{"art": "trash_can_rusty", "at": Vector2(11.9, 2.6),   "blocks": 9},
	{"art": "postbox",         "at": Vector2(13.5, 2.4),   "blocks": 10},
	{"art": "skip_large",      "at": Vector2(16.5, 2.5),   "blocks": 15},
	{"art": "skip_small",      "at": Vector2(17.25, 2.75), "blocks": 12},
	{"art": "trash_can_full",  "at": Vector2(18.25, 2.4),  "blocks": 9},
	{"art": "wall_lamp",       "at": Vector2(20.5, 2.1),   "blocks": 0},
	# south pavement
	{"art": "barrel_right",    "at": Vector2(3.5, 11.25),  "blocks": 11},
	{"art": "trash_skip",      "at": Vector2(5.5, 11.4),   "blocks": 16},
	{"art": "trash_can",       "at": Vector2(6.6, 11.3),   "blocks": 9},
	{"art": "skip_small",      "at": Vector2(8.5, 11.75),  "blocks": 12},
	{"art": "bollard",         "at": Vector2(10.5, 10.6),  "blocks": 5},
	{"art": "bollard",         "at": Vector2(11.5, 10.6),  "blocks": 5},
	{"art": "cardboard_box",   "at": Vector2(12.25, 11.5), "blocks": 11},
	{"art": "trash_can_rusty", "at": Vector2(14.5, 11.35), "blocks": 9},
	{"art": "trash_can_full",  "at": Vector2(14.9, 11.6),  "blocks": 9},
	{"art": "postbox",         "at": Vector2(17.5, 11.3),  "blocks": 10},
	{"art": "bike_rack",       "at": Vector2(19.5, 11.5),  "blocks": 18},
	{"art": "wall_lamp",       "at": Vector2(8.0, 12.9),   "blocks": 0},
]



# ── Night ─────────────────────────────────────────────────────────────────────
# Extra pools of light, on top of the one every `wall_lamp` prop gets for free.
# `at` is a big cell; `r` is the pool's radius in pixels along the ground.
const NIGHT_LIGHTS := [
	# the phone box glows from inside
	{"at": Vector2(10.5, 2.6),  "r": 60.0,  "e": 0.85, "c": Color(1.0, 0.86, 0.62)},
	# lit shop windows on the far side, spilling onto the pavement
	{"at": Vector2(6.0, 3.1),   "r": 85.0,  "e": 0.60, "c": Color(1.0, 0.84, 0.55)},
	{"at": Vector2(14.0, 3.1),  "r": 85.0,  "e": 0.60, "c": Color(1.0, 0.84, 0.55)},
	# a lamp further down the road, no fitting drawn for it yet
	{"at": Vector2(15.0, 7.0),  "r": 160.0, "e": 1.10, "c": Color(1.0, 0.80, 0.45)},
]

## Where the cycle sits when the level loads, and how fast it runs.
##
## Applied to the node so this is the one place the level's default lives.
## Godot omits a value equal to the script default when it saves, so do not
## read the scene file to find out what it is - read this. night.gd is `@tool`,
## so dragging `night` in the Inspector updates the viewport live.
const NIGHT_AT_BUILD := 1.0
## 0 holds still. A running cycle under a conversation is a distraction, so it
## is opt-in.
const NIGHT_CYCLE_SECONDS := 0.0

## How far a wall lamp throws, and what colour. Sodium rather than white.
const LAMP_RADIUS := 150.0
const LAMP_ENERGY := 1.45
const LAMP_COLOUR := Color(1.0, 0.78, 0.42)


## A soft round falloff, white so the light's own `color` sets the hue.
##
## Linear alpha reads as a flat disc with a visible rim - the eye finds the
## edge of a straight ramp. These stops approximate an inverse-square knee:
## bright in the middle, most of the fade happening early, a long faint tail.
func _light_texture() -> GradientTexture2D:
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.55, 0.8, 1.0])
	grad.colors = PackedColorArray([
		Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.78), Color(1, 1, 1, 0.34),
		Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


## Night tint plus the lamps. Returns how many lights were made.
##
## The lamp pools are derived from the `wall_lamp` entries in PROPS rather than
## listed again, so moving a lamp moves its light. Anything with no fitting
## drawn for it goes in NIGHT_LIGHTS.
func _build_night(root: Node2D) -> int:
	var night := Node2D.new()
	night.name = "Night"
	night.set_script(load("res://levels/night.gd"))
	night.set("cycle_seconds", NIGHT_CYCLE_SECONDS)
	night.set("night", NIGHT_AT_BUILD)
	root.add_child(night)
	night.owner = root

	var tint := CanvasModulate.new()
	tint.name = "Tint"
	night.add_child(tint)
	tint.owner = root

	var tex := _light_texture()
	var wanted := []
	for prop in PROPS:
		if String(prop["art"]) == "wall_lamp":
			wanted.append({"at": prop["at"], "r": LAMP_RADIUS,
				"e": LAMP_ENERGY, "c": LAMP_COLOUR})
	for extra in NIGHT_LIGHTS:
		wanted.append(extra)

	var made := 0
	for spec in wanted:
		var light := PointLight2D.new()
		light.name = "Light%d" % made
		light.texture = tex
		light.color = spec["c"]
		light.energy = float(spec["e"])
		light.set_meta("night_energy", float(spec["e"]))
		light.blend_mode = Light2D.BLEND_MODE_ADD
		light.texture_scale = float(spec["r"]) / 64.0
		# A pool of light lying on the floor is an ELLIPSE on screen, not a
		# circle: the ground is a 2:1 isometric plane. A round one reads as a
		# glowing ball hanging in the air in front of the wall.
		light.scale = Vector2(1.0, 0.5)
		light.position = _big_to_local(null, spec["at"])
		night.add_child(light)
		light.owner = root
		made += 1
	return made


## `-- capture` diffs the scene on disk against a freshly generated one and
## writes the difference to street_edits.json, instead of saving. That is how
## an edit made in the editor becomes permanent: generate, compare, record.
var _capturing := false


func _initialize() -> void:
	_capturing = OS.get_cmdline_user_args().has("capture")
	_load_catalogue()
	var tileset := _build_tileset()
	var floor_tileset := _build_floor_tileset()
	print("tileset save err=", ResourceSaver.save(tileset, TILESET_OUT),
		" floor=", ResourceSaver.save(floor_tileset, FLOOR_TILESET_OUT))
	_build_scene(tileset, floor_tileset)
	quit()


func _load_catalogue() -> void:
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(TILES_JSON))
	SUB = int(raw["sub"])
	GRID = Vector2i(int(raw["grid_tile_size"][0]), int(raw["grid_tile_size"][1]))
	ART = Vector2i(int(raw["art_tile_size"][0]), int(raw["art_tile_size"][1]))
	KERB_CELL = Vector2i(int(raw["kerb_cell"][0]), int(raw["kerb_cell"][1]))
	for name in raw["kerbs"]:
		KERB_TILES[name] = Vector2i(int(raw["kerbs"][name][0]), int(raw["kerbs"][name][1]))
	for name in raw["floors"]:
		FLOOR_COORDS[name] = Vector2i(int(raw["floors"][name][0]), int(raw["floors"][name][1]))
	for name in raw["grid"]:
		GRID_TILES[name] = raw["grid"][name]
	BAY_W = int(ART.x / 2)
	PANEL_CELL = Vector2i(int(raw["panel_cell"][0]), int(raw["panel_cell"][1]))
	PANEL_H = int(raw["panel_height"])
	PANEL_RISE = int(raw["panel_rise"])
	for name in raw["panels"]:
		PANELS[name] = Vector2i(int(raw["panels"][name][0]), int(raw["panels"][name][1]))
	QUARTER_CELL = Vector2i(int(raw["quarter_art_cell"][0]), int(raw["quarter_art_cell"][1]))
	for name in raw["quarter_art"]:
		var q: Dictionary = raw["quarter_art"][name]
		QUARTER_ART[name] = Vector2i(int(q["atlas"][0]), int(q["atlas"][1]))
	_sort_panel_families()
	print("catalogue: %d decal tiles at %s, %d floors at %s, %d wall panels at %s, sub=%d"
		% [GRID_TILES.size(), str(GRID), FLOOR_COORDS.size(), str(ART),
		PANELS.size(), str(PANEL_CELL), SUB])


func _diamond(size: Vector2i) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(0, -size.y / 2.0), Vector2(size.x / 2.0, 0),
		Vector2(0, size.y / 2.0), Vector2(-size.x / 2.0, 0)])


func _build_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size = GRID
	ts.add_physics_layer()
	ts.set_physics_layer_collision_layer(0, 1)
	ts.add_navigation_layer()

	var src := TileSetAtlasSource.new()
	src.texture = load(DECAL_SHEET)
	src.texture_region_size = GRID
	ts.add_source(src, 0)


	for name in GRID_TILES:
		var t: Dictionary = GRID_TILES[name]
		var coords := Vector2i(int(t["atlas"][0]), int(t["atlas"][1]))
		src.create_tile(coords)
		var data: TileData = src.get_tile_data(coords, 0)
		if bool(t["walkable"]):
			var np := NavigationPolygon.new()
			np.vertices = _diamond(GRID)
			np.add_polygon(PackedInt32Array([0, 1, 2, 3]))
			data.set_navigation_polygon(0, np)
		if bool(t["solid"]):
			data.add_collision_polygon(0)
			data.set_collision_polygon_points(0, 0, _diamond(GRID))
	return ts


## Which variant a cell gets. Hashed from the coordinates rather than random, so
## rebuilding produces the same street every time.
func _pick(options: Array, x: int, y: int) -> String:
	var h: int = abs(x * 73856093 ^ y * 19349663)
	return options[h % options.size()]


## The fine cells a big cell covers.
func _fine(big_x: int, big_y: int, i: int, j: int) -> Vector2i:
	return Vector2i(big_x * SUB + i, big_y * SUB + j)
## Corners a character would be sliced in half standing in.
##
## A walkable cell whose SOUTH-EAST neighbour is a building sits behind that
## building in depth, so the building correctly draws over it - but the wall
## panel's left edge is a straight vertical line, so a character tucked into
## that corner is cut cleanly down the middle. The occlusion is right; standing
## there is what is wrong, and there is nothing to do in such a nook anyway.
##
## Only the inside corner of a recess can be one: an ordinary pavement cell has
## pavement to its south-east. On this map it is exactly one cell.
func _paint_corner_nooks(layer: TileMapLayer) -> int:
	var laid := 0
	for y in GROUND.size():
		var row: String = GROUND[y]
		for x in row.length():
			if not FLOOR_KEY.has(row[x]):
				continue
			if _is_building(x, y) or not _is_building(x + 1, y):
				continue
			for i in SUB:
				for j in SUB:
					_mark_solid(layer, _fine(x, y, i, j), "n")
					laid += 1
	return laid


## Marks one fine cell solid and remembers WHY, so the build can print a map of
## what is walled off. Four different things add collision here and it is easy
## to blame the wrong one.
func _mark_solid(layer: TileMapLayer, cell: Vector2i, why: String) -> void:
	layer.set_cell(cell, 0, Vector2i(int(GRID_TILES["collision"]["atlas"][0]),
		int(GRID_TILES["collision"]["atlas"][1])))
	if not _solid_why.has(cell):
		_solid_why[cell] = why


func _paint_collision(layer: TileMapLayer) -> int:
	var laid := 0
	for y in BLOCKS.size():
		var row: String = BLOCKS[y]
		for x in row.length():
			if not BLOCK_KEY.has(row[x]):
				continue
			for i in SUB:
				for j in SUB:
					_mark_solid(layer, _fine(x, y, i, j), "B")
					laid += 1
	return laid


## Litter and grime, now scattered per QUARTER cell so it clusters naturally
## instead of stamping a whole 96 px tile at a time.
func _scatter_decals(layer: TileMapLayer) -> int:
	var kinds: Array = []
	for name in GRID_TILES:
		if String(GRID_TILES[name]["layer"]) == "decal":
			kinds.append(name)
	kinds.sort()
	if kinds.is_empty():
		return 0
	var placed := 0
	for y in GROUND.size():
		var row: String = GROUND[y]
		for x in row.length():
			if not FLOOR_KEY.has(row[x]):
				continue
			for i in SUB:
				for j in SUB:
					var cell := _fine(x, y, i, j)
					var h: int = abs(cell.x * 2654435761 ^ cell.y * 40503)
					if h % 100 >= DECAL_DENSITY:
						continue
					var name: String = kinds[(h / 100) % kinds.size()]
					_note("decal 24x12 slice", name.split("@")[0])
					layer.set_cell(cell, 0, Vector2i(
						int(GRID_TILES[name]["atlas"][0]),
						int(GRID_TILES[name]["atlas"][1])))
					placed += 1
	return placed


## Where a BIG cell centre lands in world space. `at` may be fractional.
##
## This has to agree with where the TileMapLayer actually draws the floor, and
## two things make that easy to get wrong: Godot puts cell (0,0) with its
## CORNER on the origin, not its centre, and a big cell spans SUB x SUB fine
## cells so its centre sits SUB-1 fine rows below the first of them. Getting it
## wrong puts every sprite off the floor it stands on while collision - painted
## on the tile grid - stays put, so you walk through the art and bump into
## nothing. Checked against the layer in _assert_alignment().
func _big_to_local(_layer: TileMapLayer, at: Vector2) -> Vector2:
	var fx: float = at.x * SUB + (SUB - 1) / 2.0
	var fy: float = at.y * SUB + (SUB - 1) / 2.0
	return Vector2((fx - fy) * GRID.x / 2.0 + GRID.x / 2.0,
		(fx + fy) * GRID.y / 2.0 + GRID.y / 2.0)


## Where a QUARTER cell lands in world space, for sprites the size of one fine
## cell. `at` is still in big cells, but 0.25 steps one fine cell and a whole
## number lands on the first fine cell of that big one - the same convention
## the collision painting below uses, so art and collision cannot disagree.
func _quarter_to_local(at: Vector2) -> Vector2:
	var fx: float = at.x * SUB
	var fy: float = at.y * SUB
	return Vector2((fx - fy) * GRID.x / 2.0 + GRID.x / 2.0,
		(fx + fy) * GRID.y / 2.0 + GRID.y / 2.0)


## Confirms the placement maths still matches the tilemap. Cheap, and the last
## drift here cost a debugging session.
func _assert_alignment(layer: TileMapLayer) -> void:
	for big in [Vector2i(0, 0), Vector2i(3, 2), Vector2i(10, 7)]:
		var sum := Vector2.ZERO
		for i in SUB:
			for j in SUB:
				sum += layer.map_to_local(Vector2i(big.x * SUB + i, big.y * SUB + j))
		var centre: Vector2 = sum / float(SUB * SUB)
		var ours: Vector2 = _big_to_local(null, Vector2(big))
		if ours.distance_to(centre) > 0.01:
			push_error("big cell %s: placing sprites at %s but the floor is at %s"
				% [str(big), str(ours), str(centre)])
			print("ALIGNMENT BROKEN at %s: off by %s" % [str(big), str(ours - centre)])
		# and the quarter anchor against the fine cell it claims to sit on
		var fine := Vector2i(big.x * SUB, big.y * SUB)
		var q: Vector2 = _quarter_to_local(Vector2(big))
		if q.distance_to(layer.map_to_local(fine)) > 0.01:
			print("QUARTER ALIGNMENT BROKEN at %s: off by %s"
				% [str(big), str(q - layer.map_to_local(fine))])


## Kerbs draw above the floor but never sort against anything: 96 px of art
## judged from one point puts its lip across the shins of anyone standing just
## north of that point. A 4 px lip could only ever hide 4 px of a character, so
## it is pinned below everything that walks instead of being sorted at all.
const KERB_Z := -50
const KERB_SOURCE := 1


## The kerb lip, painted on its own layer at quarter resolution.
func _paint_kerbs(layer: TileMapLayer) -> int:
	var laid := 0
	for y in GROUND.size():
		var row: String = GROUND[y]
		for x in row.length():
			if not KERB_KEY.has(row[x]):
				continue
			var pick: String = _pick(KERB_KEY[row[x]], x, y)
			_note("kerb 96x64", pick)
			layer.set_cell(Vector2i(x, y), KERB_SOURCE, KERB_TILES[pick])
			laid += 1
	return laid
func _place_props(parent: Node2D, nav: TileMapLayer, owner_node: Node) -> int:
	var made := 0
	for prop in PROPS:
		var path: String = "res://sprites/street/props/%s.png" % prop["art"]
		if not ResourceLoader.exists(path):
			push_warning("prop art missing: %s" % path)
			continue
		_note("prop png", String(prop["art"]))
		var tex: Texture2D = load(path)
		var spr := Sprite2D.new()
		spr.name = "%s_%d" % [prop["art"], made]
		spr.texture = tex
		spr.offset = Vector2(0, -tex.get_height() / 2.0)
		spr.position = _big_to_local(null, prop["at"])
		parent.add_child(spr)
		spr.owner = owner_node
		_add_sorter(spr, owner_node, Vector2.ZERO)

		if float(prop["blocks"]) <= 0.0:    # scenery, not an obstacle
			made += 1
			continue
		_carved += _carve_nav_circle(nav, spr.position, float(prop["blocks"]))
		_prop_blocks.append([spr.position, float(prop["blocks"])])
		var body := StaticBody2D.new()
		body.name = "Blocker"
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = float(prop["blocks"])
		shape.shape = circle
		body.add_child(shape)
		spr.add_child(body)
		body.owner = owner_node
		shape.owner = owner_node
		made += 1
	return made


func _quarter_texture(name: String) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = load(THIN_WALL_SHEET)
	var c: Vector2i = QUARTER_ART[name]
	tex.region = Rect2(c.x * QUARTER_CELL.x, c.y * QUARTER_CELL.y,
		QUARTER_CELL.x, QUARTER_CELL.y)
	return tex


## Thin walls: a sprite per quarter cell, plus collision on that one fine cell
## rather than the whole big cell a block would take.
func _spawn_wall_runs(parent: Node2D, layer: TileMapLayer, solid_layer: TileMapLayer,
		owner_node: Node) -> int:
	var step := 1.0 / float(SUB)
	var made := 0
	for run in WALL_RUNS:
		var art: String = "q_wall_%s%s" % [run["axis"], "_low" if run["low"] else ""]
		if not QUARTER_ART.has(art):
			push_warning("wall art missing: %s" % art)
			continue
		var from: Vector2 = run["from"]
		var to: Vector2 = run["to"]
		var span: Vector2 = to - from
		var steps: int = int(round(span.length() / step))
		var delta: Vector2 = span / maxf(float(steps), 1.0)
		for k in steps + 1:
			var at: Vector2 = from + delta * k
			var spr := Sprite2D.new()
			spr.name = "%s_%d" % [art, made]
			_note("thin wall 24x36", art)
			spr.texture = _quarter_texture(art)
			# the art is drawn with its floor diamond at the cell foot
			spr.offset = Vector2(0, -(QUARTER_CELL.y - GRID.y) / 2.0)
			spr.position = _quarter_to_local(at)
			parent.add_child(spr)
			spr.owner = owner_node
			_add_sorter(spr, owner_node, Vector2.ZERO)
			_mark_solid(solid_layer, Vector2i(
				int(floor(at.x * SUB)), int(floor(at.y * SUB))), "w")
			made += 1
	return made
func _add_character(root: Node2D, scene: String, node_name: String, at: Vector2) -> Node2D:
	var who := (load(scene) as PackedScene).instantiate() as Node2D
	who.name = node_name
	who.position = at
	who.y_sort_enabled = true
	root.add_child(who)
	# Only the instance ROOT gets an owner: owning its children makes Godot
	# serialise them as new nodes, and the character ends up with a second
	# Sprite and AnimationTree fighting the real ones.
	who.owner = root
	return who


# ------------------------------------------------------------- facades ----
# Buildings are FACES, not cubes. Each exposed wall face of a building cell is
# covered by panel sprites - one storey tall, PANEL_BAYS cells wide - stacked
# sideways into runs and upwards into storeys.
#
# Which neighbour shares which face, worked out once so it is not re-derived:
#   the "l" face runs west vertex -> south vertex, is hidden by cell (x, y+1),
#   and consecutive l faces join along +x (down-right on screen);
#   the "r" face runs south vertex -> east vertex, is hidden by cell (x+1, y),
#   and consecutive r faces join along -y (up-right on screen).

## How tall each kind of block stands.
##
## Only the south-west and south-east faces of anything are ever visible in
## this projection, so a two-storey building on the SOUTH side of the street
## would present its back to the camera and simply hide the street. The far
## side gets buildings; the near side gets a single-storey boundary wall.
const STOREYS := 2
## 0 = no facade drawn at all. The NEAR side of the street stands between the
## camera and the pavement, so any wall there occludes the people walking on
## it - correctly, but a single 112 px storey hides a 96 px character outright.
## The near side gets a low wall laid as WALL_RUNS instead, which bounds the
## street without swallowing anyone.
const STOREYS_BY_BLOCK := {"S": 0}
## Which layouts may be picked for which storey. Derived from the sheet at
## load, NOT listed here: a hand-kept list silently rots the moment a layout is
## renamed, and the only symptom is a hole in a wall where `_spawn_wall` could
## not find the art. That is exactly what happened when the panels went from
## two bays to one.
##
##   g_*    ground floor        everything else   upper storeys
##   quoin  a corner column, placed deliberately rather than at random
var GROUND_PANELS: Array = []
var UPPER_PANELS: Array = []
var BOUNDARY_PANELS: Array = []
## Layouts with nothing in them, for the cropped end of a short run.
var PLAIN_GROUND: Array = []
var PLAIN_UPPER: Array = []


func _sort_panel_families() -> void:
	var seen := {}
	for full in PANELS:
		var base: String = full.substr(0, full.length() - 2)   # drop _l / _r
		if base == "quoin" or seen.has(base):
			continue
		seen[base] = true
		if base.begins_with("g_"):
			GROUND_PANELS.append(base)
		else:
			UPPER_PANELS.append(base)
	GROUND_PANELS.sort()
	UPPER_PANELS.sort()
	BOUNDARY_PANELS = GROUND_PANELS.duplicate()
	for n in GROUND_PANELS:
		if String(n).contains("plain"):
			PLAIN_GROUND.append(n)
	for n in UPPER_PANELS:
		if String(n).contains("plain"):
			PLAIN_UPPER.append(n)
	if PLAIN_GROUND.is_empty():
		PLAIN_GROUND = GROUND_PANELS.duplicate()
	if PLAIN_UPPER.is_empty():
		PLAIN_UPPER = UPPER_PANELS.duplicate()
	if GROUND_PANELS.is_empty() or UPPER_PANELS.is_empty():
		push_error("no wall layouts found in the sheet")
	print("panel layouts: %d ground, %d upper" % [GROUND_PANELS.size(), UPPER_PANELS.size()])

var PANELS := {}                    # name -> Vector2i in walls.png
var PANEL_CELL := Vector2i(96, 162)
var PANEL_H := 112
var PANEL_RISE := 48
var PANEL_PAD := 1
## The width of ONE CELL's wall face, which is what a panel is measured in.
## Derived from the tile so it cannot drift when the tile size changes.
var BAY_W := 32
var _bays_covered := 0              # faces the spawned panels actually span
var _missing_panels := 0            # panels skipped for want of art
var _partial_panels := 0            # panels cropped to fit a short run
var _solid_why := {}                # fine cell -> what made it solid
var _prop_blocks := []              # prop circles, which are bodies not tiles
var _used := {}                     # every art name the build actually places


func _note(kind: String, name: String) -> void:
	if not _used.has(kind):
		_used[kind] = {}
	_used[kind][name] = int(_used[kind].get(name, 0)) + 1


func _is_building(x: int, y: int) -> bool:
	if y < 0 or y >= BLOCKS.size():
		return false
	var row: String = BLOCKS[y]
	if x < 0 or x >= row.length():
		return false
	return BLOCK_KEY.has(row[x])


## `bays` narrower than a whole panel crops from the LEFT of the art, which is
## the start of the run for both facings, so a short run gets a short wall
## instead of one that overhangs into the building.
func _panel_texture(name: String, bays: int = -1) -> AtlasTexture:
	var tex := AtlasTexture.new()
	tex.atlas = load(WALL_SHEET)
	var c: Vector2i = PANELS[name]
	var whole: int = _panel_bays()
	var used: int = whole if bays <= 0 else mini(bays, whole)
	tex.region = Rect2(c.x * PANEL_CELL.x, c.y * PANEL_CELL.y,
		PANEL_CELL.x * used / whole, PANEL_CELL.y)
	return tex


func _panel_bays() -> int:
	return int(PANEL_CELL.x / BAY_W)


## The two ends of a panel's base, as offsets from the sprite's top-left.
##
## THE TWO FACINGS SLOPE OPPOSITE WAYS and this has to follow the artwork: an
## "r" base starts low at the south vertex and rises to the east vertex, while
## an "l" base starts high at the west vertex and falls to the south vertex.
## Using one for both puts the sort line across the grain of the picture and
## hangs the panel half its rise off the ground.
func _panel_base(side: String, storey: int, bays: int = -1) -> Array:
	var lift: float = storey * PANEL_H
	var whole: int = _panel_bays()
	var used: int = whole if bays <= 0 else mini(bays, whole)
	var span: float = PANEL_CELL.x * used / float(whole) - 1.0
	var rise: float = PANEL_RISE * used / float(whole)
	var start := PANEL_PAD + PANEL_H + lift
	if side == "r":
		return [Vector2(0, start + PANEL_RISE), Vector2(span, start + PANEL_RISE - rise)]
	return [Vector2(0, start), Vector2(span, start + rise)]


## How many storeys the block at this cell stands.
func _storeys_at(x: int, y: int) -> int:
	if y < 0 or y >= BLOCKS.size():
		return 0
	var row: String = BLOCKS[y]
	if x < 0 or x >= row.length():
		return 0
	return int(STOREYS_BY_BLOCK.get(row[x], STOREYS))


## Builds a whole stacked wall as ONE sorted object.
##
## Every storey shares the same base line, so giving each its own IsoSorter
## makes the comparison return "equal" and the draw order fall back to
## registration order. That is invisible for an "r" wall, whose upper storey
## sits clear above a character, but an "l" upper storey reaches down to
## `anchor.y - 63` while a character's head is at `anchor.y - 74` - an 11 px
## overlap right across the hat, which flickers in and out as they walk.
##
## Storeys above the ground are therefore CHILDREN of the ground panel: one
## sort line, one z_index, and the whole wall draws together.
func _spawn_wall(parent: Node2D, owner_node: Node, side: String,
		start: Vector2i, bays: int, storeys: int, anchor: Vector2) -> int:
	var single: bool = storeys == 1
	var made := 0
	var root_spr: Sprite2D = null
	for storey in storeys:
		var family: Array = (BOUNDARY_PANELS if single
			else (GROUND_PANELS if storey == 0 else UPPER_PANELS))
		# A run that is not a whole number of panels long has its last panel
		# CROPPED, and cropping a door leaves half a door. Give the remainder
		# plain brick, which survives being cut.
		if bays < _panel_bays():
			_partial_panels += 1
			family = PLAIN_GROUND if storey == 0 else PLAIN_UPPER
		var name: String = "%s_%s" % [_pick(family, start.x * 31 + storey, start.y), side]
		if not PANELS.has(name):
			# a hole in a wall, not a warning to scroll past
			print("MISSING PANEL ART: %s - facade will have a gap here" % name)
			_missing_panels += 1
			continue
		var spr := Sprite2D.new()
		spr.name = "panel_%s_%d_%d_%d" % [side, start.x, start.y, storey]
		_note("wall panel 96x162", name)
		spr.texture = _panel_texture(name, bays)
		spr.centered = false
		if storey == 0:
			# the base's left end sits on `anchor`; the art rises from there
			var base: Array = _panel_base(side, 0, bays)
			spr.position = anchor - base[0]
			parent.add_child(spr)
			spr.owner = owner_node
			root_spr = spr

			# LINE sorting, because a wall is judged by the line of its foot. A
			# point would be wrong by up to half the panel's rise at either end
			# - which is how a character gets drawn through a wall behind them.
			var sorter := IsoSorter.new()
			sorter.name = "IsoSorter"
			sorter.sort_type = IsoSorter.SortType.LINE
			sorter.sort_offsets = [base[0], base[1]] as Array[Vector2]
			sorter.is_movable = false
			spr.add_child(sorter)
			sorter.owner = owner_node
		else:
			if root_spr == null:
				continue
			spr.position = Vector2(0, -PANEL_H * storey)   # stacked on the one below
			root_spr.add_child(spr)
			spr.owner = owner_node
		made += 1
	return made


## Every exposed face, for checking the runs cover all of them and no more.
func _count_exposed() -> int:
	var n := 0
	for y in BLOCKS.size():
		for x in BLOCKS[y].length():
			if not _is_building(x, y) or _storeys_at(x, y) == 0:
				continue
			if not _is_building(x, y + 1):
				n += 1
			if not _is_building(x + 1, y):
				n += 1
	return n


## Groups exposed faces into runs, chops each into panels and spawns them.
func _spawn_facades(parent: Node2D, owner_node: Node) -> int:
	# how many cell faces one panel spans - the same figure _panel_bays() uses,
	# because a mismatch here crops every panel and slices its door in half
	var bays: int = _panel_bays()
	var made := 0
	var height := BLOCKS.size()
	var width := 0
	for row in BLOCKS:
		width = maxi(width, row.length())

	# "l" faces: runs along +x, exposed when the cell to the south-west is open
	for y in height:
		var x := 0
		while x < width:
			if not (_is_building(x, y) and not _is_building(x, y + 1)):
				x += 1
				continue
			var run_start := x
			while x < width and _is_building(x, y) and not _is_building(x, y + 1):
				x += 1
			var n := x - run_start
			var i := 0
			while i < n:
				var fit: int = mini(bays, n - i)   # short runs get a short panel
				var cell := Vector2i(run_start + i, y)
				# west vertex of the first cell in this panel
				var anchor: Vector2 = _big_to_local(null, Vector2(cell)) + Vector2(-ART.x / 2.0, 0)
				if _storeys_at(cell.x, cell.y) > 0:
					_bays_covered += fit
				made += _spawn_wall(parent, owner_node, "l", cell, fit,
					_storeys_at(cell.x, cell.y), anchor)
				i += fit

	# "r" faces: runs along -y, exposed when the cell to the south-east is open
	for x in width:
		var y := height - 1
		while y >= 0:
			if not (_is_building(x, y) and not _is_building(x + 1, y)):
				y -= 1
				continue
			var run_start := y
			while y >= 0 and _is_building(x, y) and not _is_building(x + 1, y):
				y -= 1
			var n := run_start - y
			var i := 0
			while i < n:
				var fit: int = mini(bays, n - i)
				var cell := Vector2i(x, run_start - i)
				# south vertex of the lowest cell in this panel
				var anchor: Vector2 = _big_to_local(null, Vector2(cell)) + Vector2(0, ART.y / 2.0)
				if _storeys_at(cell.x, cell.y) > 0:
					_bays_covered += fit
				made += _spawn_wall(parent, owner_node, "r", cell, fit,
					_storeys_at(cell.x, cell.y), anchor)
				i += fit
	return made


## The visible floor, back on the BIG 96x48 grid.
##
## Painting a big tile no longer forces a big navigation cell: navigation and
## collision live on their own invisible quarter-resolution layers, so the two
## resolutions are independent. That is the whole reason for splitting them.
func _build_floor_tileset() -> TileSet:
	var ts := TileSet.new()
	ts.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	ts.tile_layout = TileSet.TILE_LAYOUT_DIAMOND_DOWN
	ts.tile_offset_axis = TileSet.TILE_OFFSET_AXIS_HORIZONTAL
	ts.tile_size = ART
	# floors.png holds one 96x48 diamond per cell, the same size as the tile.
	# A cell BIGGER than the tile overhangs, and Godot drops overhanging art in
	# a band along the top and left of the map - so the sheet is cut to size
	# rather than compensated for with texture_origin.
	var src := TileSetAtlasSource.new()
	src.texture = load(FLOOR_SHEET)
	src.texture_region_size = ART
	ts.add_source(src, 0)
	for name in FLOOR_COORDS:
		src.create_tile(FLOOR_COORDS[name])

	# Kerbs sit on the same grid as the floor - a kerb IS a floor tile with a
	# lip. The cell is taller than the tile to hold that lip, so the art is
	# lifted onto its footprint and the layer is padded for the overhang.
	var kerb_src := TileSetAtlasSource.new()
	kerb_src.texture = load(KERB_SHEET)
	kerb_src.texture_region_size = KERB_CELL
	ts.add_source(kerb_src, KERB_SOURCE)
	for kname in KERB_TILES:
		var kc: Vector2i = KERB_TILES[kname]
		kerb_src.create_tile(kc)
		kerb_src.get_tile_data(kc, 0).texture_origin = Vector2i(
			0, -(KERB_CELL.y - ART.y) / 2)
	return ts


func _paint_floor(layer: TileMapLayer) -> int:
	var laid := 0
	for y in GROUND.size():
		var row: String = GROUND[y]
		for x in row.length():
			if not FLOOR_KEY.has(row[x]):
				continue
			var name: String = _pick(FLOOR_KEY[row[x]], x, y)
			if not FLOOR_COORDS.has(name):
				continue
			_note("floor 96x48", name)
			layer.set_cell(Vector2i(x, y), 0, FLOOR_COORDS[name])
			laid += 1
	return laid


## Navigation, at quarter resolution, wherever the floor is walkable.
func _paint_nav(layer: TileMapLayer) -> int:
	var walk := Vector2i(int(GRID_TILES["walkable"]["atlas"][0]),
		int(GRID_TILES["walkable"]["atlas"][1]))
	var laid := 0
	for y in GROUND.size():
		var row: String = GROUND[y]
		for x in row.length():
			if not FLOOR_KEY.has(row[x]):
				continue
			for i in SUB:
				for j in SUB:
					layer.set_cell(_fine(x, y, i, j), 0, walk)
					laid += 1
	return laid


## With the art on its own layer, carving navigation is just erasing cells -
## there is no floor tile to keep, so no stand-in layer is needed.
func _carve_nav_cells(nav: TileMapLayer, solid: TileMapLayer) -> int:
	var cut := 0
	for cell in solid.get_used_cells():
		if nav.get_cell_source_id(cell) != -1:
			nav.erase_cell(cell)
			cut += 1
	return cut


func _carve_nav_circle(nav: TileMapLayer, at: Vector2, radius: float) -> int:
	var reach: float = radius + 4.0        # the navmesh is where a CENTRE may go
	var centre := nav.local_to_map(at)
	var span := int(ceil(reach / float(GRID.y))) + 1
	var cut := 0
	for dx in range(-span, span + 1):
		for dy in range(-span, span + 1):
			var cell := centre + Vector2i(dx, dy)
			if nav.get_cell_source_id(cell) == -1:
				continue
			if nav.map_to_local(cell).distance_to(at) > reach:
				continue
			nav.erase_cell(cell)
			cut += 1
	return cut


## Puts an IsoSorter on a sprite. POINT is right for anything compact; walls
## use LINE and build their own.
func _add_sorter(spr: Node2D, owner_node: Node, offset: Vector2,
		movable: bool = false) -> void:
	var sorter := IsoSorter.new()
	sorter.name = "IsoSorter"
	sorter.sort_type = IsoSorter.SortType.POINT
	sorter.sort_offset_1 = offset
	sorter.is_movable = movable
	spr.add_child(sorter)
	sorter.owner = owner_node


## Godot drops tile art that overhangs the layer's used rect, in a band along
## the top and left as deep as the overhang. A floor tile whose region is the
## same size as the tile never notices; a kerb, whose 24x36 art stands 24 px
## proud of its 24x12 cell, silently loses its first two rows.
##
## Where the art genuinely needs the height, pad the layer with fully
## transparent cells so the band that gets dropped is empty.
func _pad_for_overhang(layer: TileMapLayer, depth: int, source: int,
		blank: Vector2i) -> int:
	var rect := layer.get_used_rect()
	var added := 0
	for y in range(rect.position.y - depth, rect.position.y + rect.size.y):
		for x in range(rect.position.x - depth, rect.position.x + rect.size.x):
			if x >= rect.position.x and y >= rect.position.y:
				continue                    # inside: leave it alone
			if layer.get_cell_source_id(Vector2i(x, y)) != -1:
				continue
			layer.set_cell(Vector2i(x, y), source, blank)
			added += 1
	return added


func _build_scene(tileset: TileSet, floor_tileset: TileSet) -> void:
	var root := Node2D.new()
	root.name = "Street"
	root.set_script(load("res://levels/street.gd"))

	# The visible floor runs on the big grid; everything else on the quarter
	# grid. Godot puts a cell's CORNER on the origin, so the two grids' origins
	# do not coincide - the offset is measured rather than assumed.
	var floors := TileMapLayer.new()
	floors.name = "Floor"
	floors.tile_set = floor_tileset
	floors.z_index = -100
	print("floor cells: ", _paint_floor(floors))
	root.add_child(floors)
	floors.owner = root

	var nav := TileMapLayer.new()
	nav.name = "Nav"
	nav.tile_set = tileset
	nav.visible = false             # navigation only; the floor is drawn above
	print("nav cells: ", _paint_nav(nav))
	root.add_child(nav)
	nav.owner = root
	floors.position = _fine_centre_of_big(nav, Vector2i.ZERO) - floors.map_to_local(Vector2i.ZERO)
	print("floor layer offset: ", floors.position)

	var blocks := TileMapLayer.new()
	blocks.name = "Blocks"
	blocks.tile_set = tileset
	blocks.visible = false          # collision only
	blocks.navigation_enabled = false
	print("collision cells: %d (+%d closing corner nooks)"
		% [_paint_collision(blocks), _paint_corner_nooks(blocks)])
	root.add_child(blocks)
	blocks.owner = root

	var decals := TileMapLayer.new()
	decals.name = "Decals"
	decals.tile_set = tileset
	decals.z_index = -99
	decals.navigation_enabled = false
	print("decals: ", _scatter_decals(decals))
	root.add_child(decals)
	decals.owner = root

	var kerbs := TileMapLayer.new()
	kerbs.name = "Kerbs"
	kerbs.tile_set = floor_tileset
	kerbs.z_index = KERB_Z          # above the floor, below anything that walks
	kerbs.navigation_enabled = false
	var kerb_cells: int = _paint_kerbs(kerbs)
	var kerb_pad: int = _pad_for_overhang(kerbs,
		int(ceil(float(KERB_CELL.y - ART.y) / float(ART.y))), 0, FLOOR_COORDS["blank"])
	print("kerb cells: %d (+%d transparent, to keep the lip out of the clipped band)"
		% [kerb_cells, kerb_pad])
	kerbs.position = floors.position      # same grid as the floor, same origin
	root.add_child(kerbs)
	kerbs.owner = root

	var walls := Node2D.new()
	walls.name = "Walls"
	root.add_child(walls)
	walls.owner = root
	var panels_made: int = _spawn_facades(walls, root)
	var exposed: int = _count_exposed()
	print("wall panels: %d covering %d of %d exposed faces%s%s"
		% [panels_made, _bays_covered, exposed,
		"" if _bays_covered == exposed else "   <-- MISMATCH",
		"" if _missing_panels == 0 else "   <-- %d MISSING ART" % _missing_panels])
	if _partial_panels > 0:
		print("  %d panel(s) cropped to a short run - given plain brick so the"
			% _partial_panels + " crop does not cut a door in half")

	var props := Node2D.new()
	props.name = "Props"
	root.add_child(props)
	props.owner = root
	print("thin walls: ", _spawn_wall_runs(props, nav, blocks, root))
	var editable := {"Blocks": blocks, "Kerbs": kerbs, "Floor": floors, "Decals": decals}
	if _capturing:
		_capture_hand_edits(editable)
		quit()
		return
	_apply_hand_edits(editable)
	print("nav cut by walls and buildings: ", _carve_nav_cells(nav, blocks))
	print("props: %d (nav cut under them: %d)"
		% [_place_props(props, nav, root), _carved])

	_assert_alignment(nav)
	# Arriving from the TARDIS: a little east of the way back, so stepping out
	# does not immediately re-trigger it.
	_add_character(root, "res://player.tscn", "Player", _big_to_local(null, Vector2(3.0, 3.0)))
	_add_character(root, "res://sarah.tscn", "Sarah", _big_to_local(null, Vector2(3.6, 3.2)))

	print("night lights: ", _build_night(root))

	var door := Area2D.new()
	door.name = "DoorTrigger"
	door.set_script(load("res://scene_door.gd"))
	door.target_scene = "res://secondaryconsole.tscn"
	# the way back to the TARDIS, at the top-left (west) end of the street
	door.position = _big_to_local(null, Vector2(1.0, 2.6))
	root.add_child(door)
	door.owner = root
	var shape := CollisionShape2D.new()
	shape.name = "CollisionShape2D"
	var rect := RectangleShape2D.new()
	rect.size = Vector2(72, 36)
	shape.shape = rect
	door.add_child(shape)
	shape.owner = root

	var kinds := _used.keys()
	kinds.sort()
	print("")
	_print_walk_map(nav)
	print("=== ART ACTUALLY PLACED (see sprites/street/ASSETS.md) ===")
	for k in kinds:
		var names := (_used[k] as Dictionary).keys()
		names.sort()
		print("%s  (%d kinds): %s" % [k, names.size(), ", ".join(names)])
	print("")
	var packed := PackedScene.new()
	packed.pack(root)
	print("scene save err=", ResourceSaver.save(packed, SCENE_OUT))


## Prints where you can and cannot walk, and what is responsible.
##
## Collision on this level comes from FOUR separate places, which is one more
## than anybody keeps in their head:
##   B  the BLOCKS map - a building is solid across its WHOLE footprint
##   n  _paint_corner_nooks() - inside corners you would be sliced in half in
##   w  WALL_RUNS - the thin walls, including the near-side boundary
##   p  a prop's StaticBody2D circle, sized by its "blocks" radius
## plus `-`, which is solid nothing: floor that exists but has no navigation,
## usually because something was carved out from under it.
func _print_walk_map(nav: TileMapLayer) -> void:
	var height: int = GROUND.size()
	var width := 0
	for row in GROUND:
		width = maxi(width, row.length())
	print("")
	print("=== WHERE YOU CAN WALK (one character per %dx%d cell) ===" % [ART.x, ART.y])
	print("    . open   B building   n corner nook   w thin wall   p prop   - no navmesh")
	var header := "     "
	for x in width:
		header += str(x / 10) if x >= 10 else " "
	print(header)
	var header2 := "     "
	for x in width:
		header2 += str(x % 10)
	print(header2)
	for y in height:
		var line := ""
		for x in width:
			var blocked := 0
			var why := ""
			var navigable := 0
			for i in SUB:
				for j in SUB:
					var cell := _fine(x, y, i, j)
					var hit: String = ""
					if _solid_why.has(cell):
						hit = String(_solid_why[cell])
					else:
						# a prop blocks with a circle, not a tile, so it owns no
						# cell - test the fine cell's centre against each one
						var at: Vector2 = nav.map_to_local(cell)
						for pb in _prop_blocks:
							if (pb[0] as Vector2).distance_to(at) <= float(pb[1]):
								hit = "p"
								break
					if hit != "":
						blocked += 1
						if why == "":
							why = hit
					if nav.get_cell_source_id(cell) != -1:
						navigable += 1
			if blocked >= SUB * SUB:
				line += why
			elif blocked > 0:
				line += why.to_lower()
			elif navigable == 0:
				line += "-"
			else:
				line += "."
		print("%3d  %s" % [y, line])
	print("")


## Records how the scene on disk differs from what this build just generated,
## so edits made in the editor survive the next build.
func _capture_hand_edits(by_name: Dictionary) -> void:
	if not ResourceLoader.exists(SCENE_OUT):
		print("nothing to capture: no scene on disk yet")
		return
	var existing := (load(SCENE_OUT) as PackedScene).instantiate()
	var layers := {}
	var total_erase := 0
	var total_set := 0
	for layer_name in by_name:
		var made: TileMapLayer = by_name[layer_name]
		var theirs := existing.get_node_or_null(layer_name) as TileMapLayer
		if theirs == null:
			continue
		var have := {}
		for c in theirs.get_used_cells():
			have[c] = true
		var erase := []
		for c in made.get_used_cells():
			if not have.has(c):
				erase.append([c.x, c.y])
		var add := []
		for c in theirs.get_used_cells():
			if made.get_cell_source_id(c) == -1:
				add.append([c.x, c.y, theirs.get_cell_source_id(c),
					theirs.get_cell_atlas_coords(c).x, theirs.get_cell_atlas_coords(c).y,
					theirs.get_cell_alternative_tile(c)])
		if erase.is_empty() and add.is_empty():
			continue
		layers[layer_name] = {"erase": erase, "set": add}
		total_erase += erase.size()
		total_set += add.size()
		print("  %-8s you cleared %d, you added %d" % [layer_name, erase.size(), add.size()])
	existing.free()
	var out := {
		"_comment": "Hand edits to the generated street, re-applied after every build. "
			+ "Fine-grid cell coordinates. Nav is not listed: it is derived from Blocks, "
			+ "so clearing collision here frees the navmesh automatically. "
			+ "Regenerate with: godot --headless --path . "
			+ "--script res://tools/build_street.gd -- capture",
		"layers": layers,
	}
	var f := FileAccess.open(EDITS, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " "))
	f.close()
	print("captured %d cleared and %d added cells to %s" % [total_erase, total_set, EDITS])


## Re-applies the hand edits from street_edits.json.
##
## Runs BEFORE navigation is carved, so clearing a collision cell frees the
## navmesh over it without the overlay having to say so.
func _apply_hand_edits(by_name: Dictionary) -> void:
	if not FileAccess.file_exists(EDITS):
		return
	var raw = JSON.parse_string(FileAccess.get_file_as_string(EDITS))
	if raw == null or not (raw as Dictionary).has("layers"):
		return
	var erased := 0
	var placed := 0
	for layer_name in (raw["layers"] as Dictionary):
		if not by_name.has(layer_name):
			push_warning("hand edits name a layer that does not exist: %s" % layer_name)
			continue
		var layer: TileMapLayer = by_name[layer_name]
		var entry: Dictionary = raw["layers"][layer_name]
		for cell in entry.get("erase", []):
			layer.erase_cell(Vector2i(int(cell[0]), int(cell[1])))
			erased += 1
		for cell in entry.get("set", []):
			layer.set_cell(Vector2i(int(cell[0]), int(cell[1])), int(cell[2]),
				Vector2i(int(cell[3]), int(cell[4])), int(cell[5]))
			placed += 1
	print("hand edits: %d cells cleared, %d placed (levels/street_edits.json)"
		% [erased, placed])


## Where the SUB x SUB fine cells of a big cell actually sit, averaged - the
## thing the big floor layer has to line up with.
func _fine_centre_of_big(fine: TileMapLayer, big: Vector2i) -> Vector2:
	var sum := Vector2.ZERO
	for i in SUB:
		for j in SUB:
			sum += fine.map_to_local(Vector2i(big.x * SUB + i, big.y * SUB + j))
	return sum / float(SUB * SUB)
