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
