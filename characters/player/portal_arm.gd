class_name PortalArm extends Node2D

@export var player: Player
@export var sub_viewport_container: SubViewportContainer
@export var sub_viewport: SubViewport

@onready var _sprite: Sprite2D = $Sprite2D


func _process(_delta: float) -> void:
    var scale := Vector2(sub_viewport_container.size) / Vector2(sub_viewport.size)
    var center := sub_viewport_container.global_position + Vector2(sub_viewport_container.size) / 2.0
    global_position = center + player.gun_pivot.position * scale
    rotation = player.gun_rotation
    _sprite.flip_v = rotation > PI / 2.0 or rotation < -PI / 2.0
