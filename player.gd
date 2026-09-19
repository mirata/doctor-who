extends Character

## The Doctor. Click a spot to walk there, or steer with WASD — the keys take
## over mid-walk and cancel wherever the last click was sending him.

@export_category("Audio")
@export var footsteps_volume_db: float = -20.0
@export var footsteps_pitch: float = 1.0

var _footsteps: AudioStreamPlayer

func _ready() -> void:
	_footsteps = AudioStreamPlayer.new()
	_footsteps.stream = preload("res://audio/characters/footsteps.mp3")
	_footsteps.volume_db = footsteps_volume_db
	_footsteps.pitch_scale = footsteps_pitch
	add_child(_footsteps)

	if nav_agent != null:
		nav_agent.path_desired_distance = arrive_distance
		nav_agent.target_desired_distance = arrive_distance

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("click_move"):
		set_destination(get_global_mouse_position())

func _decide_direction() -> Vector2:
	var keys := Vector2(
		int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left")),
		int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	)
	if keys != Vector2.ZERO:
		clear_destination()
		return keys
	return direction_to_destination()

func _on_started_walking() -> void:
	_footsteps.play()

func _on_stopped_walking() -> void:
	_footsteps.stop()
