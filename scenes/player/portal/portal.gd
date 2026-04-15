extends Area2D

@export var linked_portal: Area2D
const EXIT_BUFFER := 32.0

func teleport_object(body: PortalEntity):
    if not linked_portal: return
    var new_pos: Vector2 = linked_portal.global_position
    var current_speed: float = min(20000, body.velocity.length() * 1.1)
    var push_direction := Vector2.RIGHT.rotated(linked_portal.global_rotation)
    body.velocity = push_direction * current_speed
    body.global_position = new_pos + (push_direction * EXIT_BUFFER)
