extends Area2D

@export var linked_portal: Area2D
const EXIT_BUFFER := 40

func _ready() -> void:
    add_to_group("portals")

func _physics_process(_delta: float) -> void:
    for body in get_overlapping_bodies():
        if body is PortalEntity:
            teleport_object(body)

func teleport_object(body: PortalEntity) -> void:
    if not linked_portal: return
    var new_pos: Vector2 = linked_portal.global_position
    var current_speed: float = min(20000, body.velocity.length() * 1.1)
    var push_direction := Vector2.RIGHT.rotated(linked_portal.global_rotation)
    body.velocity = push_direction * current_speed
    body.global_position = new_pos + (push_direction * EXIT_BUFFER)
