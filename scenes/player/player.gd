extends PortalEntity
class_name Player

signal died

@export var level_controller: LevelController

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var gun_pivot: Node2D = $GunPivot

const RUN_SPEED := 400.0
const ACCEL := 1000.0
const FRICTION := 1000.0
const GRAVITY := 1500.0
const JUMP_FORCE := -500.0

var _alive: bool = true

func _ready() -> void:
    add_to_group("characters")

func _physics_process(delta: float) -> void:
    # Add the gravity.
    if not is_grounded:
        velocity.y += GRAVITY * delta

    ### INPUT
    # Jump
    if Input.is_action_just_pressed("jump") and test_move(transform, Vector2.DOWN):
        velocity.y = JUMP_FORCE

    # Get the input direction and handle the movement/deceleration.
    var move_dir := Input.get_axis("left", "right")
    var mouse_pos := get_global_mouse_position()
    animated_sprite_2d.flip_h = global_position.x > mouse_pos.x

    var look_dir := 1 if animated_sprite_2d.flip_h else -1
    gun_pivot.position.x = look_dir * gun_pivot.position.abs().x

    if move_dir:
        velocity.x = move_toward(velocity.x, move_dir * RUN_SPEED, ACCEL * delta)
    else:
        velocity.x = move_toward(velocity.x, 0, FRICTION * delta)

    custom_move_and_slide(delta)

    global_position = global_position.round()

func die() -> void:
    if _alive == true:
        _alive = false
        animated_sprite_2d.visible = false
        process_mode = Node.PROCESS_MODE_DISABLED
        died.emit()

func respawn(pos: Vector2) -> void:
    if _alive == false:
        _alive = true
        global_position = pos
        velocity = Vector2.ZERO
        animated_sprite_2d.visible = true
        process_mode = Node.PROCESS_MODE_INHERIT
