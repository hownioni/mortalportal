class_name Player extends CharacterBody2D

signal died

const RUN_SPEED: float = 400.0
const ACCEL: float = 1000.0
const FRICTION: float = 1000.0
const GRAVITY: float = 1500.0
const JUMP_FORCE: float = -400.0
const MAX_FALL_SPEED: float = 2000.0
const JUMP_BUFFER_TIME: float = 0.15
const COYOTE_TIME: float = 0.10

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _movement: PortalMovementComponent = $PortalMovementComponent

var _alive: bool = true
var _jump_buffer: float = 0.0
var _coyote_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")


func _physics_process(delta: float) -> void:
	# Coyote time: refresh when grounded, drain when airborne
	if _movement.is_grounded:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)

	# Jump buffer: set on press, drain each tick
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)

	# Gravity
	if not _movement.is_grounded:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)

	# Jump: fire when buffer is live and player is eligible
	if _jump_buffer > 0.0 and (_movement.is_grounded or _coyote_timer > 0.0):
		velocity.y = JUMP_FORCE
		_jump_buffer = 0.0
		_coyote_timer = 0.0

	# Horizontal movement
	var move_dir: float = Input.get_axis("left", "right")
	if move_dir:
		velocity.x = move_toward(velocity.x, move_dir * RUN_SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)

	# Aim flip from mouse position
	_sprite.flip_h = get_global_mouse_position().x < global_position.x

	# Animation priority: jump > crouch > run > idle
	if absf(velocity.y) > 50.0:
		_play_anim("jump")
	elif Input.is_action_pressed("down"):
		_play_anim("crouch")
	elif absf(velocity.x) > 20.0:
		_play_anim("run")
	else:
		_play_anim("idle")

	_movement.tick(delta)
	global_position = global_position.round()


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


func _on_enemy_hitbox_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		die()
