extends PortalEntity
class_name Player

signal died

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var gun_pivot: Node2D = $GunPivot

const SPEED := 300.0
const JUMP_VELOCITY := -350.0

var _alive: bool = true

func _ready() -> void:
    add_to_group("characters")

func _physics_process(delta: float) -> void:
    # Add the gravity.
    if not is_on_floor():
        velocity += get_gravity() * delta

    # Handle jump.
    if Input.is_action_just_pressed("jump") and is_grounded:
        velocity.y = JUMP_VELOCITY

    # Get the input direction and handle the movement/deceleration.
    var direction := Input.get_axis("left", "right")
    var mouse_pos := get_global_mouse_position()
    animated_sprite_2d.flip_h = global_position.x > mouse_pos.x
    var look_dir := 1 if animated_sprite_2d.flip_h else -1
    gun_pivot.position.x = look_dir * gun_pivot.position.abs().x
    if direction:
        velocity.x = direction * SPEED
    else:
        velocity.x = move_toward(velocity.x, 0, SPEED)

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
