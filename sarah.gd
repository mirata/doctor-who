extends Character

## Sarah Jane, who tags along after the Doctor.
##
## She routes to him through the room's navigation mesh whenever he gets too far
## ahead, so she goes around the furniture and up the stairs rather than walking
## into things. In a room with no navigation mesh she falls back to heading
## straight for him.

## Who to follow. Left empty, she looks for a node named "Player" beside her.
@export var follow_target_path: NodePath

@export_category("Following")
## She sets off once he is further away than this. The characters are ~39 px per
## metre at this sprite scale, so 3 m is ~120 px — but this is the distance she
## *reacts* at, not the worst case. While he keeps walking the gap still opens
## before she closes it, so this sits lower to put the measured peak at 3 m.
@export var follow_distance: float = 90.0
## ...and stops once she is back inside this. The gap between the two values is
## what stops her twitching on the spot while he shuffles about.
@export var close_enough: float = 55.0
## She walks a little faster while closing a gap, since her route around the
## furniture is longer than his straight line.
@export var catch_up_speed: float = 1.25
## How far he has to move from where she last routed to before she re-routes.
## Re-pathing every frame at a moving target is wasted work.
@export var repath_distance: float = 20.0

var _target: Node2D
var _catching_up: bool = false

func _ready() -> void:
	if not follow_target_path.is_empty():
		_target = get_node_or_null(follow_target_path) as Node2D
	else:
		_target = get_parent().get_node_or_null("Player") as Node2D
	if _target == null:
		push_warning("Sarah has no one to follow; she will stand still")
	elif _target is PhysicsBody2D:
		# They walk through one another. Without this she blocks him bodily —
		# both are 6 px radius, so a path that runs through where she is standing
		# simply jams, and she will not step aside because she only moves when he
		# gets far away, which he cannot do.
		add_collision_exception_with(_target)
		(_target as PhysicsBody2D).add_collision_exception_with(self)

	if nav_agent != null:
		nav_agent.path_desired_distance = arrive_distance
		nav_agent.target_desired_distance = arrive_distance

func _current_speed() -> float:
	return float(speed) * (catch_up_speed if _catching_up else 1.0)

func _decide_direction() -> Vector2:
	if _target == null:
		return Vector2.ZERO

	# Hysteresis: set off when he gets too far, keep going until comfortably close.
	var gap: float = global_position.distance_to(_target.global_position)
	if _catching_up:
		if gap <= close_enough:
			_catching_up = false
			clear_destination()
	elif gap > follow_distance:
		_catching_up = true

	if not _catching_up:
		return Vector2.ZERO

	# Re-route once he has wandered far enough from where she was last headed.
	if not has_destination() or get_destination().distance_to(_target.global_position) > repath_distance:
		set_destination(_target.global_position)

	return direction_to_destination()
