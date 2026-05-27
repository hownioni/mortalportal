class_name PortalArm extends Node2D

@export var player: Player
@export var sub_viewport_container: SubViewportContainer

@onready var _sprite: Sprite2D = $Sprite2D


func _process(_delta: float) -> void:
    global_position = sub_viewport_container.global_position + Vector2(sub_viewport_container.size) / 2.0
    rotation = player.gun_rotation
    _sprite.flip_v = rotation > PI / 2.0 or rotation < -PI / 2.0
