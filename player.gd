extends Character

## The Doctor. Click a spot to walk there, or steer with WASD — the keys take
## over mid-walk and cancel wherever the last click was sending him.
##
## Clicking something interactable walks him to it and starts the conversation on
## arrival; pressing "interact" talks to whatever is already within reach.

@export_category("Interaction")
## How close he has to be to talk to something.
@export var interact_distance: float = 34.0

@export_category("Audio")
@export var footsteps_volume_db: float = -30.0
@export var footsteps_pitch: float = 1.0

var _footsteps: AudioStreamPlayer
# Set when a click lands on something interactable: he walks over, then talks.
var _walking_to_interact: DialogueActionable2D = null
var _in_dialogue: bool = false

func _ready() -> void:
	_footsteps = AudioStreamPlayer.new()
	_footsteps.stream = preload("res://audio/characters/footsteps.mp3")
	_footsteps.volume_db = footsteps_volume_db
	_footsteps.pitch_scale = footsteps_pitch
	add_child(_footsteps)

	if nav_agent != null:
		nav_agent.path_desired_distance = arrive_distance
		nav_agent.target_desired_distance = arrive_distance

	var dialogue := get_node_or_null("/root/DialogueManager")
	if dialogue != null:
		dialogue.dialogue_started.connect(func(_res): _in_dialogue = true)
		dialogue.dialogue_ended.connect(func(_res): _in_dialogue = false)

func _unhandled_input(event: InputEvent) -> void:
	if _in_dialogue:
		return      # the balloon owns input while someone is talking

	if event.is_action_pressed("click_move"):
		var spot: Vector2 = get_global_mouse_position()
		_walking_to_interact = _actionable_at(spot)
		if _walking_to_interact != null:
			set_destination(_walking_to_interact.global_position)
		else:
			set_destination(spot)
	elif event.is_action_pressed("interact"):
		var nearby := _actionable_within_reach()
		if nearby != null:
			_talk_to(nearby)

func _decide_direction() -> Vector2:
	if _in_dialogue:
		return Vector2.ZERO

	# Walking over to talk to something: stop and start once within reach.
	if _walking_to_interact != null:
		if global_position.distance_to(_walking_to_interact.global_position) <= interact_distance:
			var target := _walking_to_interact
			_walking_to_interact = null
			clear_destination()
			_talk_to(target)
			return Vector2.ZERO
		if not has_destination():
			_walking_to_interact = null      # gave up or could not get there

	var keys := Vector2(
		int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left")),
		int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	)
	if keys != Vector2.ZERO:
		clear_destination()
		return keys
	return direction_to_destination()

## Turns to face them and starts the conversation.
func _talk_to(actionable: DialogueActionable2D) -> void:
	var towards: Vector2 = global_position.direction_to(actionable.global_position)
	if towards != Vector2.ZERO:
		last_facing = Vector2(abs(towards.x), -towards.y).normalized()
		if absf(towards.x) > 0.1:
			sprite.flip_h = towards.x < 0
	actionable.action()

## The interactable under a world position, if there is one.
func _actionable_at(world_position: Vector2) -> DialogueActionable2D:
	var query := PhysicsPointQueryParameters2D.new()
	query.position = world_position
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for hit in get_world_2d().direct_space_state.intersect_point(query, 8):
		if hit.collider is DialogueActionable2D:
			return hit.collider
	return null

## The nearest interactable he could talk to from where he is standing.
func _actionable_within_reach() -> DialogueActionable2D:
	var nearest := DialogueActionable2D.get_nearest_actionable_to(global_position)
	if nearest != null and global_position.distance_to(nearest.global_position) <= interact_distance:
		return nearest
	return null

func _on_started_walking() -> void:
	_footsteps.play()

func _on_stopped_walking() -> void:
	_footsteps.stop()
