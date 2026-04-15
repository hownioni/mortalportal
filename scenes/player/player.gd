extends CharacterBody2D
class_name Player

signal player_died

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var gun_pivot: Node2D = $GunPivot

const SPEED := 300.0
const JUMP_VELOCITY := -350.0

var _is_dead: bool = false

func _ready() -> void:
    add_to_group("characters")

func _physics_process(delta: float) -> void:
    if _is_dead:
        return

    # Add the gravity.
    if not is_on_floor():
        velocity += get_gravity() * delta

    # Handle jump.
    if Input.is_action_just_pressed("jump") and is_on_floor():
        velocity.y = JUMP_VELOCITY

    # Get the input direction and handle the movement/deceleration.
    var direction := Input.get_axis("left", "right")
    var mouse_pos = get_global_mouse_position()
    animated_sprite_2d.flip_h = true if global_position.x > mouse_pos.x else false
    if direction:
        velocity.x = direction * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)

    move_and_slide()

    global_position = global_position.round()

func _on_killzone_body_angered() -> void:
    _is_dead = true
    animated_sprite_2d.stop()
    player_died.emit()
