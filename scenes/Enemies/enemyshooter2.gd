extends CharacterBody2D
class_name EnemyShooter2  # <--- AÑADE ESTA LÍNEA JUSTO AQUÍ Abajo
# ==========================================
# CONFIGURACIÓN DEL ENEMIGO
# ==========================================
@export var speed := 150.0
@export var shoot_cooldown := 1.5
@export var bullet_scene: PackedScene

# ==========================================
# NODOS
# ==========================================
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var shoot_point: Marker2D = $ShootPoint

# ==========================================
# VARIABLES DE ESTADO
# ==========================================
var player: Node2D = null
var can_shoot := true

func _ready() -> void:
	# Buscamos al jugador por su grupo único
	player = get_tree().get_first_node_in_group("player")
	
	if animated_sprite:
		animated_sprite.play("default")

func _physics_process(delta: float) -> void:
	if player == null:
		return

	# Calcular dirección hacia el jugador
	var direction_to_player = (player.global_position - global_position).normalized()
	var dir = direction_to_player.x

	if dir != 0:
		animated_sprite.flip_h = dir > 0

	# VALIDA QUE ESTA LÍNEA NO ESTÉ COMENTADA O BORRADA:
	if can_shoot:
		shoot() # <--- Esto es lo que activa los prints y crea la bala real
	move_and_slide()

# ==========================================
# FUNCIÓN DE DISPARO
# ==========================================
func shoot() -> void:
	if bullet_scene == null:
		return

	can_shoot = false
	
	if animated_sprite.sprite_frames.has_animation("shoot"):
		animated_sprite.play("shoot")

	var bullet = bullet_scene.instantiate()
	get_tree().current_scene.add_child(bullet)

	# Al usar global_position, Godot buscará el Marker2D en el mapa real
	bullet.global_position = shoot_point.global_position

	var target_dir = (player.global_position - shoot_point.global_position).normalized()
	bullet.direction = target_dir

	await get_tree().create_timer(shoot_cooldown).timeout
	
	if animated_sprite.sprite_frames.has_animation("default"):
		animated_sprite.play("default")
		
	can_shoot = true
