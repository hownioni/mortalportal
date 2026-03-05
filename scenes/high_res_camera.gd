extends Camera2D

@export var sub_viewport_container: SubViewportContainer
@export var smooth_speed := 3.0
@export var velocity_influence := 0.2

func _physics_process(delta: float) -> void:
    var player: CharacterBody2D = get_parent().player
    var center_pos := sub_viewport_container.global_position + (sub_viewport_container.size / 2)

    var target_offset := player.velocity * velocity_influence

    var max_offset := 50.0
    target_offset.x = clamp(target_offset.x, -max_offset, max_offset)
    target_offset.y = clamp(target_offset.y, -max_offset, max_offset)

    var target_pos = center_pos + target_offset

    global_position = global_position.lerp(target_pos, smooth_speed * delta)
