class_name Character
extends CharacterBody2D

## Shared movement and animation for anyone who walks around a room.
##
## Subclasses only decide *where* to walk by overriding `_decide_direction()`;
## everything below — blend positions, sprite flipping, the idle/run state
## machine — is identical for every character and lives here so it can't drift
## between them.

enum State {
	IDLE,
	RUN,
	ATTACK,
	DEAD
}

@export_category("Stats")
## Pixels per second. Keep this a multiple of the physics tick rate (60), so a
## frame's movement lands on a whole pixel: the viewport is only 640x320, so
## nothing can move less than one pixel and a fractional step renders as an
## uneven 1,2,2 stutter. 120 gives exactly 2 px/frame.
@export var speed: int = 120

@export_category("Navigation")
## How close counts as having arrived at a destination.
@export var arrive_distance: float = 4.0

var _destination: Vector2 = Vector2.ZERO
var _has_destination: bool = false
var _pathfinding: bool = false

var state: State = State.IDLE
var move_direction: Vector2 = Vector2.ZERO
var last_facing: Vector2 = Vector2.UP

@onready var animation_tree: AnimationTree = $AnimationTree
# Each character has exactly one Sprite2D child holding its sheet.
@onready var sprite: Sprite2D = _find_sprite()
# Optional: rooms without a NavigationRegion2D fall back to straight-line steering.
@onready var nav_agent: NavigationAgent2D = get_node_or_null("NavigationAgent2D")

func _physics_process(_delta: float) -> void:
	movement_loop()

func movement_loop() -> void:
	move_direction = _decide_direction()

	var motion: Vector2 = move_direction.normalized() * _current_speed()
	set_velocity(motion)
	move_and_slide()

	_drive_animation()
	_update_state(motion)

## Speed to walk at this frame. Override to vary it situationally.
func _current_speed() -> float:
	return float(speed)

## Direction to walk this frame. Zero means stand still. Override this.
func _decide_direction() -> Vector2:
	return Vector2.ZERO

func _drive_animation() -> void:
	# Driven by input/steering direction rather than velocity, so the facing
	# stays correct when walking into a wall.
	if move_direction != Vector2.ZERO:
		last_facing = Vector2(abs(move_direction.x), -move_direction.y).normalized()
	animation_tree.set("parameters/Idle/blend_position", last_facing)
	animation_tree.set("parameters/Run/blend_position", last_facing)

	var idle: bool = velocity == Vector2.ZERO
	animation_tree.set("parameters/conditions/Idle", idle)
	animation_tree.set("parameters/conditions/Run", !idle)

	# The sheet only holds right-facing frames; left is a flip. Only updated
	# while actually moving horizontally, so the facing holds at rest.
	if (state == State.IDLE or state == State.RUN) and velocity.x != 0:
		sprite.flip_h = velocity.x < 0

func _update_state(motion: Vector2) -> void:
	if motion != Vector2.ZERO and state == State.IDLE:
		state = State.RUN
		_on_started_walking()
	elif motion == Vector2.ZERO and state == State.RUN:
		state = State.IDLE
		_on_stopped_walking()

func _on_started_walking() -> void:
	pass

func _on_stopped_walking() -> void:
	pass

## Sends this character to a world position, pathfinding around the room's
## geometry when it has a navigation mesh and walking straight at it when it
## does not. The point is snapped onto the mesh, so clicking a wall walks as
## close as the character can get rather than doing nothing.
func set_destination(world_position: Vector2) -> void:
	_destination = world_position
	_has_destination = true
	_sync_agent_target()

## Points the navigation agent at the current destination, if the room has a
## navigation mesh. Re-checked every frame rather than latched at the moment the
## destination was set: the NavigationServer registers its regions during the
## first physics frames, so an early destination would otherwise fall back to
## straight-line steering and stay there for the rest of the walk.
func _sync_agent_target() -> void:
	if nav_agent == null or not _navigation_available():
		_pathfinding = false
		return
	var map: RID = get_world_2d().navigation_map
	var snapped_target: Vector2 = NavigationServer2D.map_get_closest_point(map, _destination)
	# Belt and braces: an unusable map snaps everything to the origin, which
	# would send the character walking to (0, 0).
	if snapped_target == Vector2.ZERO and _destination.length_squared() > 1.0:
		_pathfinding = false
		return
	if not _pathfinding or not nav_agent.target_position.is_equal_approx(snapped_target):
		nav_agent.target_position = snapped_target
	_pathfinding = true

## Direction to travel toward the current destination, or ZERO once arrived.
func direction_to_destination() -> Vector2:
	if not _has_destination:
		return Vector2.ZERO
	if not _pathfinding:
		_sync_agent_target()
	if _pathfinding:
		var goal: Vector2 = nav_agent.target_position
		var path_ready: bool = nav_agent.get_current_navigation_path().size() > 0
		# Arrival is measured by distance, not is_navigation_finished(): the path
		# is built asynchronously and the agent reports "finished" during the
		# frames before it exists, which reads as an instant arrival.
		if global_position.distance_to(goal) <= arrive_distance 				or (path_ready and nav_agent.is_navigation_finished()):
			_has_destination = false
			return Vector2.ZERO
		var next: Vector2 = nav_agent.get_next_path_position()
		if next.distance_to(global_position) <= 0.01:
			return Vector2.ZERO      # path not ready this frame; stand still
		return global_position.direction_to(next)
	if global_position.distance_to(_destination) <= arrive_distance:
		_has_destination = false
		return Vector2.ZERO
	return global_position.direction_to(_destination)

func has_destination() -> bool:
	return _has_destination

func clear_destination() -> void:
	_has_destination = false
	_pathfinding = false

## The current destination as asked for, which may be off the navigation mesh.
func get_destination() -> Vector2:
	return _destination

## True once the room has a navigation mesh that is safe to query. Both halves
## matter: a room with no NavigationRegion2D never gets one, and querying a map
## before its first synchronisation is an error rather than a miss.
func _navigation_available() -> bool:
	var map: RID = get_world_2d().navigation_map
	if not map.is_valid() or NavigationServer2D.map_get_regions(map).is_empty():
		return false
	return NavigationServer2D.map_get_iteration_id(map) > 0

func _find_sprite() -> Sprite2D:
	for child in get_children():
		if child is Sprite2D:
			return child
	push_error("%s has no Sprite2D child" % name)
	return null
