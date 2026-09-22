extends SceneTree
## A raised patch in a flat field. Its faces should show along the front and
## sides where it meets lower ground, and nowhere inside it.
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
	var road: Array = raw["surfaces"]["road_3"]
	var kerb: Array = raw["surfaces"]["pave_4_t6"]
	var step: Array = raw["surfaces"]["pave_4_t24"]
	for y in range(-12, 13):
		for x in range(-12, 13):
			var pick: Array = road
			if x >= -4 and x <= 1 and y >= -4 and y <= 1:
				pick = kerb                       # a 6 px kerb patch
			elif x >= 4 and x <= 7 and y >= 4 and y <= 7:
				pick = step                       # a 24 px platform
			layer.set_cell(Vector2i(x, y), 0, Vector2i(int(pick[0]), int(pick[1])))
	var cam := Camera2D.new()
	cam.position = layer.map_to_local(Vector2i(0, 0))
	cam.zoom = Vector2(0.62, 0.62)
	cam.enabled = true
	r2.add_child(cam)
	cam.make_current()
	RenderingServer.frame_post_draw.connect(func():
		_f += 1
		if _f < 30 or _go: return
		_go = true
		root.get_texture().get_image().save_png("user://patch.png")
		_done = true)

func _process(_d: float) -> bool:
	return _done
