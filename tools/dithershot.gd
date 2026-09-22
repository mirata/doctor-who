extends SceneTree
## Renders the same lamp at several dither strengths.
var _room: Node2D
var _f := 0
var _i := 0
var _busy := false
## (pattern, dither) pairs. 0 = BAYER_4X4, 1 = BAYER_2X2
var _steps := [[0, 0.4], [1, 0.4], [0, 0.8], [1, 0.8]]

func _initialize() -> void:
	Engine.max_fps = 60
	_room = (load("res://levels/street.tscn") as PackedScene).instantiate()
	root.add_child(_room)
	current_scene = _room
	RenderingServer.frame_post_draw.connect(_grab)

func _process(_d: float) -> bool:
	_f += 1
	return _i >= _steps.size() and not _busy

func _grab() -> void:
	if _f < 40 or _busy or _i >= _steps.size():
		return
	_busy = true
	var night := _room.get_node("Night")
	night.set("night", 1.0)
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
	night.set("dither_pattern", int(_steps[_i][0]))
	night.set("dither", float(_steps[_i][1]))
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("user://d_%d.png" % _i)
	print("shot %s dither %.1f" % ["2x2" if int(_steps[_i][0]) == 1 else "4x4", float(_steps[_i][1])])
	_i += 1
	_busy = false
