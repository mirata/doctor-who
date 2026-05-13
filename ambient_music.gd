extends Node

func _ready() -> void:
	var player := AudioStreamPlayer.new()
	player.stream = load("res://console-ambient.mp3")
	player.bus = "Master"
	player.autoplay = true
	add_child(player)
