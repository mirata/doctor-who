extends CharacterBody2D

enum State {
	IDLE,
	RUN,
	ATTACK,
	DEAD
}

@export_category(("Stats"))
@export var speed: int = 100

var state: State = State.IDLE
var move_direction: Vector2 = Vector2.ZERO
var last_facing: Vector2 = Vector2.UP

@onready var animation_tree: AnimationTree = $AnimationTree
#@onready var animation_playback: AnimationNodeStateMachinePlayback = $AnimationTree["parameters/playback"]

func _physics_process(delta: float) -> void:
	movement_loop()
	
func movement_loop() -> void:
	move_direction.x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	move_direction.y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	var motion: Vector2 = move_direction.normalized() * speed;
	set_velocity(motion)
	move_and_slide()
	
	if move_direction != Vector2.ZERO:
		last_facing = Vector2(abs(move_direction.x), -move_direction.y).normalized()
	animation_tree.set("parameters/Idle/blend_position", last_facing)
	animation_tree.set("parameters/Run/blend_position", last_facing)
	
	var idle = !velocity;
	animation_tree.set("parameters/conditions/Idle", idle);
	animation_tree.set("parameters/conditions/Run", !idle);
	
	if (state == State.IDLE or state == State.RUN) and velocity.x != 0:
		$TomBaker.flip_h = velocity.x < 0
	
	
	if motion != Vector2.ZERO and state == State.IDLE:
		state = State.RUN
		#update_anmation()
	elif motion == Vector2.ZERO and state == State.RUN:
		state = State.IDLE
		#update_anmation()


#func update_anmation() -> void:
	#match state:
		#State.IDLE:
			#animation_playback.travel("idle")
		#State.RUN:
			#animation_playback.travel("run")
		#State.ATTACK:
			#animation_playback.travel("attack")
				#
