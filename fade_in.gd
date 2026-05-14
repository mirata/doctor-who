extends Node2D

func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 128
	add_child(layer)

	var rect := ColorRect.new()
	rect.color = Color.BLACK
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(rect)

	var tween := create_tween()
	tween.tween_property(rect, "color:a", 0.0, 2.5)
	tween.tween_callback(rect.queue_free)
