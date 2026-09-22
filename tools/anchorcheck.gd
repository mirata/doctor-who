extends SceneTree
## Where does the floor art land relative to its cell, and does a wall panel's
## base sit on it? Places one floor tile and reports its opaque bounds against
## the cell that map_to_local says it occupies.
var _f := 0
var _go := false
var _done := false

func _initialize() -> void:
	Engine.max_fps = 60
	var r2 := Node2D.new()
	root.add_child(r2)
	current_scene = r2
	var layer := TileMapLayer.new()
	layer.tile_set = load("res://levels/street_floor_tileset.tres")
	r2.add_child(layer)
	var raw: Dictionary = JSON.parse_string(
		FileAccess.get_file_as_string("res://sprites/street/tiles.json"))
	for n in ["pave_4", "pave_4_t24"]:
		var at: Array = raw["surfaces"][n]
		layer.set_cell(Vector2i(0, 0), 0, Vector2i(int(at[0]), int(at[1])))
		var centre: Vector2 = layer.map_to_local(Vector2i(0, 0))
		var cam := Camera2D.new()
		cam.position = centre
		cam.enabled = true
		r2.add_child(cam)
		cam.make_current()
		for i in 8:
			await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var size := img.get_size()
		var bg := img.get_pixel(2, 2)
		var minx := 99999; var maxx := -99999; var miny := 99999; var maxy := -99999
		for y in size.y:
			for x in size.x:
				if img.get_pixel(x, y) != bg:
					minx = mini(minx, x); maxx = maxi(maxx, x)
					miny = mini(miny, y); maxy = maxi(maxy, y)
		var cx := size.x / 2
		var cy := size.y / 2
		print("%-12s art x %d..%d  y %d..%d   (cell footprint is x -32..31, y -16..15)"
			% [n, minx - cx, maxx - cx, miny - cy, maxy - cy])
		cam.queue_free()
	_done = true

func _process(_d: float) -> bool:
	return _done
