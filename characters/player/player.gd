class_name Player extends CharacterBody2D

signal died

const RUN_SPEED := 400.0
const ACCEL := 1000.0
const FRICTION := 1000.0
const GRAVITY := 1500.0
const JUMP_FORCE := -400.0
const MAX_FALL_SPEED := 2000.0
const JUMP_BUFFER_TIME := 0.15
const COYOTE_TIME := 0.10
const GATHER_TIME := 0.05
const ANIM_JUMP_THRESHOLD := 50.0
const ANIM_RUN_THRESHOLD := 35.0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _gun_pivot: GunPivot = $GunPivot
@onready var _hitbox: Hitbox = $Hitbox

@onready var portal_movement_component: PortalMovementComponent = %PortalMovementComponent

var _alive := true
var _jump_buffer := 0.0
var _coyote_timer := 0.0
var _gathering := false
var _gather_timer := 0.0
var _crouching := false


func _ready() -> void:
    add_to_group("player")
    _hitbox.hit.connect(die, CONNECT_DEFERRED)


func _physics_process(delta: float) -> void:
    _apply_gravity(delta)
    _handle_jump(delta)
    _handle_crouch()
    _apply_horizontal(delta)
    _update_facing()
    _update_visual_state()
    portal_movement_component.move(delta)
    global_position = global_position.round()


func _apply_gravity(delta: float) -> void:
    if not portal_movement_component.is_grounded:
        velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)


func _handle_jump(delta: float) -> void:
    if portal_movement_component.is_grounded:
        _coyote_timer = COYOTE_TIME
    else:
        _coyote_timer = maxf(0.0, _coyote_timer - delta)
    if Input.is_action_just_pressed("jump"):
        _jump_buffer = JUMP_BUFFER_TIME
    else:
        _jump_buffer = maxf(0.0, _jump_buffer - delta)
    if not _gathering and _jump_buffer > 0.0 and (portal_movement_component.is_grounded or _coyote_timer > 0.0):
        _gathering = true
        _gather_timer = GATHER_TIME
        _jump_buffer = 0.0
        _coyote_timer = 0.0
    if _gathering:
        _gather_timer = maxf(0.0, _gather_timer - delta)
        if _gather_timer == 0.0:
            _gathering = false
            velocity.y = JUMP_FORCE


func _handle_crouch() -> void:
    _crouching = portal_movement_component.is_grounded and Input.is_action_pressed("down") and not _gathering
    _hitbox.set_crouched(_crouching)


func _apply_horizontal(delta: float) -> void:
    if _crouching:
        velocity.x = 0.0
        return
    var move_dir := Input.get_axis("left", "right")
    if move_dir:
        velocity.x = move_toward(velocity.x, move_dir * RUN_SPEED, ACCEL * delta)
    else:
        velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)


func _update_facing() -> void:
    _sprite.flip_h = get_global_mouse_position().x < global_position.x


func _update_visual_state() -> void:
    if _gathering:
        _play_anim("gather")
        _gun_pivot.position_offset = Vector2(0, 11)
    elif not portal_movement_component.is_grounded and velocity.y < -ANIM_JUMP_THRESHOLD:
        _play_anim("jump")
        _gun_pivot.position_offset = Vector2(0, -2)
    elif not portal_movement_component.is_grounded and velocity.y > ANIM_JUMP_THRESHOLD:
        _play_anim("fall")
        _gun_pivot.position_offset = Vector2(0, -2)
    elif _crouching:
        _play_anim("crouch")
        _gun_pivot.position_offset = Vector2(0, 8)
    elif absf(velocity.x) > ANIM_RUN_THRESHOLD:
        _play_anim("run")
        _gun_pivot.position_offset = Vector2(2, 0)
    else:
        _play_anim("idle")
        _gun_pivot.position_offset = Vector2.ZERO


func _play_anim(anim_name: String) -> void:
    if _sprite.animation != anim_name:
        _sprite.play(anim_name)


func die() -> void:
    if not _alive:
        return
    _alive = false
    _sprite.visible = false
    process_mode = Node.PROCESS_MODE_DISABLED
    died.emit()


func respawn(pos: Vector2) -> void:
    if _alive:
        return
    _alive = true
    global_position = pos
    velocity = Vector2.ZERO
    _sprite.visible = true
    process_mode = Node.PROCESS_MODE_INHERIT


func set_portal_container(c: Node2D) -> void:
    _gun_pivot.portal_container = c


func reset_portals() -> void:
    _gun_pivot.reset()


func is_facing_left() -> bool:
    return _sprite.flip_h


func get_gun_global_position() -> Vector2:
    return _gun_pivot.global_position


func get_gun_global_rotation() -> float:
    return _gun_pivot.global_rotation
