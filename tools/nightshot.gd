extends SceneTree
## Renders the street at four points of the cycle, with the Doctor standing in
## a lamp pool so the light on him can be judged as well as the light on the
## floor. Saves user://n_<name>.png.
var _room: Node2D
var _f := 0
var _shots := [
	{"n": "day", "night": 0.0}, {"n": "dusk", "night": 0.4},
	{"n": "evening", "night": 0.7}, {"n": "night", "night": 1.0}]
var _i := 0
var _busy := false

func _initialize() -> void:
	Engine.max_fps = 60
	_room = (load("res://levels/street.tscn") as PackedScene).instantiate()
	root.add_child(_room)
	current_scene = _room
	RenderingServer.frame_post_draw.connect(_grab)

func _process(_d: float) -> bool:
	_f += 1
	return _i >= _shots.size() and not _busy

func _grab() -> void:
	if _f < 40 or _busy or _i >= _shots.size():
		return
	_busy = true
	var night := _room.get_node("Night")
	var lamp: Light2D = null
	for c in night.get_children():
		if c is Light2D:
			lamp = c
			break
	var who: Node2D = _room.get_node("Player")
	who.set_physics_process(false)
	who.global_position = lamp.position + Vector2(-16, 6)
	var cam: Camera2D = who.find_children("*", "Camera2D", true, false)[0]
	cam.global_position = lamp.position
	night.set("night", float(_shots[_i]["night"]))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://n_%s.png" % _shots[_i]["n"])
	print("shot ", _shots[_i]["n"])
	_i += 1
	_busy = false
