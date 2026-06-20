class_name PortalArm extends Sprite2D

@export var player: Player
@export var sub_viewport_container: SubViewportContainer
@export var sub_viewport: SubViewport

func _process(_delta: float) -> void:
    var gun_offset := player.get_gun_global_position() - player.global_position
    global_position = ViewportMath.overlay_position(
        sub_viewport_container.global_position,
        sub_viewport_container.size,
        Vector2(sub_viewport.size),
        gun_offset,
    )
    rotation = player.get_gun_global_rotation()
    flip_v = ViewportMath.overlay_flip_v(rotation)
