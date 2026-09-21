extends SceneTree
var _room: Node
var _f := 0
func _initialize() -> void:
	Engine.max_fps = 60
	_room = (load("res://levels/street.tscn") as PackedScene).instantiate()
	root.add_child(_room)
	current_scene = _room
	# default zoom, as the game actually shows it
	RenderingServer.frame_post_draw.connect(_grab)
func _process(_d: float) -> bool:
	_f += 1
	if _f > 100: quit(); return true
	return false
func _grab() -> void:
	if _f == 80:
		root.get_texture().get_image().save_png("user://z1.png")
