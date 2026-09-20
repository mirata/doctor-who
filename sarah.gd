extends Character

## Sarah Jane, who tags along after the Doctor.
##
## She routes to him through the room's navigation mesh, so she goes around the
## furniture and up the stairs rather than walking into things. In a room with no
## navigation mesh she falls back to heading straight for him.
##
## Her pace is continuous rather than on/off: the further behind she is the
## harder she pushes, and once she has closed the gap she settles into his exact
## walking speed and holds station. An on/off version stops dead the moment it is
## close enough, which reads as a stop-start shuffle over any real distance.

## Who to follow. Left empty, she looks for a node named "Player" beside her.
@export var follow_target_path: NodePath

@export_category("Following")
## The gap she settles into while he is walking. The characters are ~39 px per
## metre at this sprite scale, so this is a little over 2 m.
@export var follow_distance: float = 90.0
## The gap she closes to once he stops, so she gathers round rather than hanging
## back at walking distance.
@export var stop_distance: float = 55.0
## Extra speed per pixel she is behind `follow_distance`. This is the burst: at
## 2.0 being 60 px too far back asks for 120 px/s on top of his pace.
@export var catch_up_gain: float = 2.0
## Ceiling on that burst, so she never appears to teleport after him.
@export var max_speed: int = 240
## How far he moves from where she was last headed before she re-routes.
@export var repath_distance: float = 20.0

## How close he can get before she gives way. Walking into her shoulders her
## aside rather than passing through, but because it moves *her* rather than
## blocking *him*, he can never end up wedged against her.
@export var personal_space: float = 14.0

## Ceiling on how fast she is shouldered aside, in pixels per second. This has
## to stay comfortably above walking speed or he simply outruns her giving way
## and walks through her anyway — at 90 against his 120 he passed clean through.
@export var yield_speed: float = 300.0

var _target: Node2D
var _target_pace: float = 0.0
var _previous_target_position: Vector2 = Vector2.ZERO
var _walk_speed: float = 0.0

func _ready() -> void:
	if not follow_target_path.is_empty():
		_target = get_node_or_null(follow_target_path) as Node2D
	else:
		_target = get_parent().get_node_or_null("Player") as Node2D
	if _target == null:
		push_warning("Sarah has no one to follow; she will stand still")
	else:
		_previous_target_position = _target.global_position
		if _target is PhysicsBody2D:
			# No hard collision between the two of them: a path that runs through
			# where she is standing would simply jam, and she will not move aside
			# of her own accord while he is close. Instead she is nudged out of
			# his way in _after_move(), which cannot wedge either of them.
			add_collision_exception_with(_target)
			(_target as PhysicsBody2D).add_collision_exception_with(self)

	if nav_agent != null:
		nav_agent.path_desired_distance = arrive_distance
		nav_agent.target_desired_distance = arrive_distance

func _current_speed() -> float:
	return _walk_speed

func _decide_direction() -> Vector2:
	if _target == null:
		return Vector2.ZERO

	_measure_target_pace()

	# Hold `follow_distance` while he walks, close to `stop_distance` when he
	# stops. Matching his pace at the right distance is a stable equilibrium:
	# drop behind and the gain pushes her faster, crowd him and she eases off.
	var gap: float = global_position.distance_to(_target.global_position)
	var wanted_gap: float = follow_distance if _target_pace > 1.0 else stop_distance
	var raw_speed: float = _target_pace + (gap - wanted_gap) * catch_up_gain

	_walk_speed = _to_whole_pixels_per_frame(raw_speed)
	if _walk_speed <= 0.0:
		return Vector2.ZERO

	if not has_destination() or get_destination().distance_to(_target.global_position) > repath_distance:
		set_destination(_target.global_position)
	return direction_to_destination()

## His speed right now, measured from how far he actually moved rather than read
## off his velocity, so walking into a wall counts as standing still.
## Steps out of his way when he walks into her. Uses move_and_collide so she is
## still stopped by walls; if she is cornered and cannot give way, he simply
## passes through rather than both of them jamming.
func _after_move() -> void:
	if _target == null:
		return
	var offset: Vector2 = global_position - _target.global_position
	var gap: float = offset.length()
	if gap >= personal_space:
		return

	# Standing exactly on top of one another has no meaningful direction to
	# push along, so pick one rather than dividing by zero.
	var away: Vector2 = offset / gap if gap > 0.01 else Vector2.RIGHT

	# If he is walking into her, step aside rather than straight back: pushing
	# along his heading just shoves her across the room ahead of him and he
	# never gets past. Sidestep towards whichever side she already leans.
	var his_heading: Vector2 = (_target as CharacterBody2D).velocity if _target is CharacterBody2D else Vector2.ZERO
	if his_heading.length() > 1.0 and away.dot(his_heading.normalized()) > 0.3:
		var heading: Vector2 = his_heading.normalized()
		var sideways: Vector2 = Vector2(-heading.y, heading.x)
		if sideways.dot(away) < 0.0:
			sideways = -sideways
		away = (away + sideways * 2.0).normalized()

	var overlap: float = personal_space - gap
	var step: float = minf(overlap, yield_speed * get_physics_process_delta_time())
	move_and_collide(away * step)


func _measure_target_pace() -> void:
	var delta: float = get_physics_process_delta_time()
	if delta <= 0.0:
		return
	_target_pace = _target.global_position.distance_to(_previous_target_position) / delta
	_previous_target_position = _target.global_position

## Rounds a speed to a whole number of pixels per physics frame. The viewport is
## only 640x320, so a fractional step renders as an uneven stutter; this keeps
## her as smooth as he is, and gives the burst distinct gears rather than a
## continuously sliding speed.
func _to_whole_pixels_per_frame(raw_speed: float) -> float:
	if raw_speed <= 0.0:
		return 0.0
	var step: float = 1.0 / get_physics_process_delta_time()   # 60 px/s = 1 px/frame
	var geared: float = roundf(raw_speed / step) * step
	return minf(maxf(geared, step), float(max_speed))
