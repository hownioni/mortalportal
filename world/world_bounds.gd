class_name WorldBounds extends Area2D

func _on_body_entered(body: Player) -> void:
    body.die()
