extends Camera2D

@export var sub_viewport_container: SubViewportContainer
@export var level_controller: LevelController
@export var smooth_speed := 3.0
@export var velocity_influence := 0.2

var player: Player

func _ready() -> void:
    player = level_controller.player

func _physics_process(delta: float) -> void:
    var center_pos := sub_viewport_container.global_position + (sub_viewport_container.size / 2)

    var target_offset := player.velocity * velocity_influence

    var max_offset := 50.0
    target_offset.x = clamp(target_offset.x, -max_offset, max_offset)
    target_offset.y = clamp(target_offset.y, -max_offset, max_offset)

    var target_pos = center_pos + target_offset

    global_position = global_position.lerp(target_pos, smooth_speed * delta)
