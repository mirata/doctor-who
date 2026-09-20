extends AudioStreamPlayer2D

const SOUNDS: Array[AudioStream] = [
	preload("res://audio/console/console1.mp3"),
	preload("res://audio/console/console2.mp3"),
	preload("res://audio/console/console3.mp3"),
	preload("res://audio/console/console4.mp3"),
	preload("res://audio/console/console5.mp3"),
	preload("res://audio/console/console6.mp3"),
	preload("res://audio/console/console7.mp3"),
	preload("res://audio/console/console8.mp3"),
	preload("res://audio/console/console9.mp3"),
]

## Shortest gap between console noises, in seconds.
@export var min_interval: float = 20.0

## Longest gap between console noises, in seconds.
@export var max_interval: float = 55.0

var _timer: Timer

func _ready() -> void:
	_timer = Timer.new()
	_timer.one_shot = true
	_timer.timeout.connect(_play_random)
	add_child(_timer)
	_schedule_next()

func _play_random() -> void:
	stream = SOUNDS[randi() % SOUNDS.size()]
	play()
	_schedule_next()

func _schedule_next() -> void:
	_timer.start(randf_range(min_interval, max_interval))
