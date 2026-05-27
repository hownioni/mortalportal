class_name PortalArm extends Node2D

@export var player: Player
@export var gun_pivot: GunPivot

@onready var _sprite: Sprite2D = $Sprite2D


func _process(_delta: float) -> void:
	global_position = player.global_position
	rotation = gun_pivot.rotation
	_sprite.flip_v = rotation > PI / 2.0 or rotation < -PI / 2.0
