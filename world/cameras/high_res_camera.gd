class_name HighResCamera extends Camera2D

@export var sub_viewport_container: SubViewportContainer
@export var player: Player
@export var smooth_speed: float = 3.0
@export var velocity_influence: float = 0.2

const MAX_OFFSET := 50.0

func _physics_process(delta: float) -> void:
	var center_pos := sub_viewport_container.global_position + Vector2(sub_viewport_container.size) / 2.0
	var target_offset := player.velocity * velocity_influence
	target_offset.x = clamp(target_offset.x, -MAX_OFFSET, MAX_OFFSET)
	target_offset.y = clamp(target_offset.y, -MAX_OFFSET, MAX_OFFSET)
	global_position = global_position.lerp(center_pos + target_offset, smooth_speed * delta)
