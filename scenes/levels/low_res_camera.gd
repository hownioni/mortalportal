extends Camera2D

@export var follow_target: Node2D

func _process(_delta: float) -> void:
    
    global_position = follow_target.global_position.round()
