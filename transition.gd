extends CanvasLayer

var _rect: ColorRect
var _busy := false

func _ready() -> void:
	layer = 200
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rect = ColorRect.new()
	_rect.color = Color.BLACK
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_rect)
	_fade_in()

func _fade_in() -> void:
	_rect.color = Color.BLACK
	create_tween().tween_property(_rect, "color:a", 0.0, 0.5)

func fade_to(scene_path: String) -> void:
	if _busy:
		return
	_busy = true
	_rect.color.a = 0.0
	var tween := create_tween()
	tween.tween_property(_rect, "color:a", 1.0, 0.5)
	await tween.finished
	get_tree().change_scene_to_file(scene_path)
	_busy = false
	_fade_in()
