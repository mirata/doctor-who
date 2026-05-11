extends CharacterBody2D

enum State {
	IDLE,
	RUN,
	ATTACK,
	DEAD
}

@export_category(("Stats"))
@export var speed: int = 400

var state: State = State.IDLE
var move_direction: Vector2 = Vector2.ZERO

@onready var animation_tree: AnimationTree = $AnimationTree
@onready var animation_playback: AnimationNodeStateMachinePlayback = $AnimationTree["parameters/playback"]

func _physics_process(delta: float) -> void:
	movement_loop()
	
func movement_loop() -> void:
	move_direction.x = int(Input.is_action_pressed("right")) - int(Input.is_action_pressed("left"))
	move_direction.y = int(Input.is_action_pressed("down")) - int(Input.is_action_pressed("up"))
	var motion: Vector2 = move_direction.normalized() * speed;
	set_velocity(motion)
	move_and_slide()
	
	if state == State.IDLE or State.RUN:
		if move_direction.x < -0.01:
			$WarriorBlue.flip_h = true
		elif move_direction.x > 0.01:
			$WarriorBlue.flip_h = false
	
	
	if motion != Vector2.ZERO and state == State.IDLE:
		state = State.RUN
		update_anmation()
	elif motion == Vector2.ZERO and state == State.RUN:
		state = State.IDLE
		update_anmation()


func update_anmation() -> void:
	match state:
		State.IDLE:
			animation_playback.travel("idle")
		State.RUN:
			animation_playback.travel("run")
		State.ATTACK:
			animation_playback.travel("attack")
				
