extends PortalEntity
class_name Player

signal died

@export var level_controller: LevelController

# ==========================================
# MODOS
# ==========================================
var mobile_mode := true

# ==========================================
# NODOS
# ==========================================
@onready var aim_joystick = get_tree().root.find_child("AimJoystick", true, false)

@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var gun_pivot: Node2D = $GunPivot

# ==========================================
# MOVIMIENTO
# ==========================================
const RUN_SPEED := 400.0
const ACCEL := 1000.0
const FRICTION := 1000.0
const GRAVITY := 1500.0
const JUMP_FORCE := -400.0
const MAX_FALL_SPEED := 2000.0

var _alive := true
var can_jump := true


func _ready() -> void:
	add_to_group("characters")
	mobile_mode = GameSettings.mobile_mode


func _physics_process(delta: float) -> void:

	# ======================================
	# GRAVEDAD
	# ======================================
	if not is_grounded:
		velocity.y += GRAVITY * delta

	velocity.y = clamp(
		velocity.y,
		-9999,
		MAX_FALL_SPEED
	)


	# ======================================
	# SALTO
	# ======================================
	if Input.is_action_just_pressed("jump") and can_jump:

		if test_move(transform, Vector2.DOWN):

			can_jump = false
			velocity.y = JUMP_FORCE

			jump_cooldown()


	# ======================================
	# MOVIMIENTO
	# ======================================
	var move_dir := Input.get_axis("left", "right")

	if move_dir:

		velocity.x = move_toward(
			velocity.x,
			move_dir * RUN_SPEED,
			ACCEL * delta
		)

	else:

		velocity.x = move_toward(
			velocity.x,
			0,
			FRICTION * delta
		)


	# ======================================
	# MODO PC
	# ======================================
	if mobile_mode == false:

		var mouse_pos := get_global_mouse_position()

		animated_sprite_2d.flip_h = global_position.x > mouse_pos.x

		var look_dir := 1 if animated_sprite_2d.flip_h else -1

		gun_pivot.position.x = (
			look_dir *
			abs(gun_pivot.position.x)
		)

		gun_pivot.look_at(mouse_pos)


	# ======================================
	# MODO MOVIL
	# ======================================
	else:

		if aim_joystick:

			var aim_dir = aim_joystick.get_direction()

			if aim_dir.length() > 0.1:

				gun_pivot.rotation = aim_dir.angle()

				if aim_dir.x != 0:
					animated_sprite_2d.flip_h = aim_dir.x < 0


	# ======================================
	# ANIMACIONES
	# ======================================

	# JUMP
	if velocity.y < -50:

		play_anim("jump")


	# FALL
	elif velocity.y > 50 and not is_grounded:

		play_anim("jump")


	# CROUCH
	elif Input.is_action_pressed("down"):

		play_anim("crouch")


	# RUN
	elif abs(velocity.x) > 20:

		play_anim("run")


	# IDLE
	else:

		play_anim("idle")


	# ======================================
	# MOVIMIENTO FINAL
	# ======================================
	custom_move_and_slide(delta)

	global_position = global_position.round()


# ==========================================
# PLAY ANIMATION
# ==========================================
func play_anim(anim_name):

	if animated_sprite_2d.animation != anim_name:
		animated_sprite_2d.play(anim_name)


# ==========================================
# COOLDOWN SALTO
# ==========================================
func jump_cooldown():

	await get_tree().create_timer(0.1).timeout
	can_jump = true


# ==========================================
# MUERTE
# ==========================================
func die() -> void:

	if _alive == true:

		_alive = false

		animated_sprite_2d.visible = false

		process_mode = Node.PROCESS_MODE_DISABLED

		died.emit()


# ==========================================
# RESPAWN
# ==========================================
func respawn(pos: Vector2) -> void:

	if _alive == false:

		_alive = true

		global_position = pos

		velocity = Vector2.ZERO

		animated_sprite_2d.visible = true

		process_mode = Node.PROCESS_MODE_INHERIT
