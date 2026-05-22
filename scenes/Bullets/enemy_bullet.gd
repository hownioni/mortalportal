extends Area2D

@export var speed := 350.0
var direction := Vector2.ZERO

func _physics_process(delta: float) -> void:
	# Nos movemos en base a la dirección que calcula el tanque morado
	if direction != Vector2.ZERO:
		global_position += direction * speed * delta

# SEÑAL DE COLISIÓN CORREGIDA
func _on_body_entered(body: Node2D) -> void:
	# 1. Si choca con otro enemigo, lo ignoramos por completo
	if body.is_in_group("enemies") or "Enemy" in body.name:
		return

	# 2. Si impacta al jugador real
	if body.is_in_group("player"):
		print("¡La bala impactó al jugador!")
		queue_free()
		
	# 3. Si choca contra el suelo o plataformas
	elif body.name == "TileMap" or body is StaticBody2D:
		queue_free()

# Señal para borrar la bala si sale de la pantalla
func _on_visible_on_screen_notifier_2d_screen_exited() -> void:
	queue_free()
	
func _ready() -> void:
	# Hace que la bala ignore los movimientos del tanque una vez que ya nació arriba
	set_as_top_level(true)
