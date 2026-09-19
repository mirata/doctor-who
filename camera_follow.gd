extends Camera2D

## Follows a character with a little slack while they speed up, turn or stop,
## and with no lag at all once they settle into a constant walking speed.
##
## Godot's own position_smoothing always trails a moving target by
## velocity / smoothing_speed — at walking pace that is a permanent ~20 px lag.
## The offset itself is harmless, but with snap_2d_transforms_to_pixel the
## camera and the sprite cross pixel boundaries at slightly different moments,
## so the sprite shimmers by a pixel the whole time it is moving.
##
## Feeding the target's velocity forward removes the steady-state error: the
## camera travels at exactly their speed, so the spring below only ever has to
## absorb *changes* in speed. Constant speed means the error settles to zero and
## the sprite sits rock still.

## How sharply the remaining error is taken up. Higher recovers the slack
## faster after a change of direction.
@export var follow_speed: float = 8.0

## Roughly how long, in seconds, the camera takes to pick up speed when they
## start moving or speed up. It deliberately does not apply to slowing down or
## stopping: easing out of a speed means coasting past them and springing back.
## Zero makes the camera perfectly rigid.
@export var slack_seconds: float = 0.18

## Who to follow. Empty means the parent, which is the usual arrangement.
@export var target_path: NodePath

var _target: Node2D
var _previous_target_position: Vector2
var _followed_velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	_target = get_node_or_null(target_path) as Node2D
	if _target == null:
		_target = get_parent() as Node2D
	if _target == null:
		push_error("camera_follow: nothing to follow")
		return

	# Drive the camera ourselves rather than inheriting the target's transform,
	# and turn off the built-in smoothing this replaces.
	top_level = true
	position_smoothing_enabled = false
	global_position = _target.global_position
	_previous_target_position = _target.global_position

func _physics_process(delta: float) -> void:
	if _target == null or delta <= 0.0:
		return

	# Measured rather than read off the body, so being blocked by a wall counts
	# as standing still even though velocity says otherwise.
	var target_position: Vector2 = _target.global_position
	var target_velocity: Vector2 = (target_position - _previous_target_position) / delta
	_previous_target_position = target_position

	# Ease into the target's *speed*, but take their direction exactly, and drop
	# the speed the instant they slow. Letting the fed-forward velocity coast on
	# after they have stopped is what made the camera sail past and spring back.
	var target_speed: float = target_velocity.length()
	var followed_speed: float = _followed_velocity.length()
	var speed: float = target_speed
	if slack_seconds > 0.0 and target_speed > followed_speed:
		speed = lerpf(followed_speed, target_speed, 1.0 - exp(-delta / slack_seconds))
	_followed_velocity = target_velocity.normalized() * speed

	# Travel with them first, then take up whatever error is left over. Doing the
	# correction second is what makes the resting offset exactly zero — correcting
	# first leaves the camera permanently one frame of travel ahead.
	global_position += _followed_velocity * delta
	global_position = global_position.lerp(target_position, minf(follow_speed * delta, 1.0))
