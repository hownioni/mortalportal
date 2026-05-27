class_name LowResCamera extends Camera2D

@export var follow_target: Player

func _process(_delta: float) -> void:
	global_position = follow_target.global_position.round()
