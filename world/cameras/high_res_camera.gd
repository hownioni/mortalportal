class_name HighResCamera extends Camera2D

@export var player: Player
@export var sub_viewport_container: SubViewportContainer
@export var smooth_speed: float = 3.0
@export var velocity_influence: float = 0.2
@export var max_offset: float = 50.0

func _physics_process(delta: float) -> void:
	var target := ViewportMath.camera_target_position(
		sub_viewport_container.global_position,
		sub_viewport_container.size,
		player.velocity,
		velocity_influence,
		max_offset,
	)
	global_position = global_position.lerp(target, smooth_speed * delta)
