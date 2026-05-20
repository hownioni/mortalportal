extends Area2D

@onready var world_bound: CollisionShape2D = $WorldBound

func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		var player: Player = body
		# Usamos call_deferred para retrasar la muerte una fracción de frame
		# y permitir que la física termine de procesar la colisión limpiamente.
		player.call_deferred("die")
