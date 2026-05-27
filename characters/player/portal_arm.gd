class_name PortalArm extends Node2D

@export var player: Player

@onready var _sprite: Sprite2D = $Sprite2D


func _process(_delta: float) -> void:
	global_position = player.global_position
	rotation = player.gun_rotation
	_sprite.flip_v = rotation > PI / 2.0 or rotation < -PI / 2.0
