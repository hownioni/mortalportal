class_name ViewportMath extends RefCounted

static func overlay_position(
    container_pos: Vector2, container_size: Vector2,
    subviewport_size: Vector2, gun_offset: Vector2,
) -> Vector2:
    var scale := container_size / subviewport_size
    var center := container_pos + container_size / 2.0
    return center + gun_offset * scale

static func overlay_flip_v(rotation: float) -> bool:
    return rotation > PI / 2.0 or rotation < -PI / 2.0

static func camera_target_position(
    container_pos: Vector2, container_size: Vector2,
    player_velocity: Vector2, velocity_influence: float, max_offset: float,
) -> Vector2:
    var center := container_pos + container_size / 2.0
    var offset := player_velocity * velocity_influence
    offset.x = clampf(offset.x, -max_offset, max_offset)
    offset.y = clampf(offset.y, -max_offset, max_offset)
    return center + offset
