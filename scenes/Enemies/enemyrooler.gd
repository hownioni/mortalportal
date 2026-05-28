extends CharacterBody2D

@export var speed := 150.0
@export var detection_range := 250.0

const GRAVITY := 1500.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var floor_ray: RayCast2D = $RayCast2D

var player: Node2D

func _ready() -> void:
	# Nos aseguramos de que el enemigo se registre en el grupo global al arrancar
	add_to_group("enemies")
	
	player = get_tree().get_first_node_in_group("player") as Node2D
	if animated_sprite:
		animated_sprite.play("default")


func _physics_process(delta: float) -> void:
	# ======================================
	# GRAVEDAD
	# ======================================
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if player == null:
		return

	var distance := player.global_position.x - global_position.x
	var dir: int = 0

	# ======================================
	# DETECCIÓN Y MOVIMIENTO (Corregido y Unificado)
	# ======================================
	if abs(distance) < detection_range:
		# Frenamos a 5 píxeles para asegurar el contacto físico real
		if abs(distance) > 5: 
			var wanted_dir: int = sign(distance)

			# Mover el RayCast al frente de la dirección deseada
			floor_ray.position.x = wanted_dir * 20
			
			# Solo avanza en el eje X si el RayCast detecta suelo adelante
			if floor_ray.is_colliding():
				dir = wanted_dir

	# Asignamos velocidad y movemos una SOLA vez por fotograma
	velocity.x = dir * speed
	var _was_moved: bool = move_and_slide()

	# ======================================
	# CONTROL VISUAL: FLIP DEL SPRITE
	# ======================================
	if dir != 0:
		animated_sprite.flip_h = dir > 0

	# ======================================
	# CONTROL DE ANIMACIONES
	# ======================================
	if abs(velocity.x) > 0:
		if animated_sprite.animation != "run":
			animated_sprite.play("run")
	else:
		if animated_sprite.animation != "default":
			animated_sprite.play("default")

	# ======================================
	# DAÑO POR CONTACTO DIRECTO CON EL PLAYER
	# ======================================
	for i in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(i)
		var collider: Node2D = collision.get_collider() as Node2D
		
		# Si el objeto colisionado es el jugador, activamos su función .die()
		if collider and collider.is_in_group("player"):
			if collider.has_method("die"):
				collider.call("die")
