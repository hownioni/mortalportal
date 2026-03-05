extends CharacterBody2D

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D

const SPEED := 300.0
const JUMP_VELOCITY := -350.0

@export var pause_menu: PauseMenu

func _ready() -> void:
	add_to_group("Player")

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		SceneManager.pause_game(true)

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("left", "right")
	if direction:
		velocity.x = direction * SPEED
		if direction < 0:
			animated_sprite_2d.play("idle_left")
		else:
			animated_sprite_2d.play("idle_right")
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()
	
	global_position = global_position.round()
