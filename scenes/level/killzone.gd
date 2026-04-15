extends Area2D

@onready var world_bound: CollisionShape2D = $WorldBound

func _on_body_entered(body: Node2D) -> void:
    if body is Player:
        var player: Player = body
        player.die()
