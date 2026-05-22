extends CharacterBody2D

@export var speed := 100.0

@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D

const GRAVITY := 1500.0

var player: Node2D

@export var detection_range := 250.0

@onready var floor_ray: RayCast2D = $RayCast2D

func _ready() -> void:

	add_to_group("enemies") # <-- Añade esto al inicio de su _ready
	# ... el resto de su código actual ...
	player = get_tree().get_first_node_in_group("characters")
	animated_sprite.play("default")
	


func _physics_process(delta: float) -> void:



	# GRAVEDAD
	if not is_on_floor():
		velocity.y += GRAVITY * delta

	if player == null:
		return

	var distance := player.global_position.x - global_position.x
	

	
	var dir: int = 0

	# DETECCIÓN
	if abs(distance) < detection_range:

		if abs(distance) > 20:

			var wanted_dir: int = sign(distance)

			# MOVER RAYCAST AL FRENTE
			floor_ray.position.x = wanted_dir * 20
			
			print(floor_ray.is_colliding())
			# SOLO AVANZA SI HAY SUELO
			if floor_ray.is_colliding():
				dir = wanted_dir

	velocity.x = dir * speed

	move_and_slide()

	# FLIP
	if dir != 0:
		animated_sprite.flip_h = dir > 0

	# ANIMACIONES
	if abs(velocity.x) > 0:
		if animated_sprite.animation != "run":
			animated_sprite.play("run")
	else:
		if animated_sprite.animation != "default":
			animated_sprite.play("default")
