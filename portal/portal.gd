class_name Portal extends Area2D

const EXIT_BUFFER := 40
const MAX_TELEPORT_SPEED := 20000.0
const EXIT_SPEED_BOOST := 1.1

@export var linked_portal: Portal
@export var palette_index: int = 0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
    add_to_group("portals")
    if _sprite.material:
        _sprite.material = _sprite.material.duplicate()
        _sprite.material.set_shader_parameter("palette_index", palette_index)


func _physics_process(_delta: float) -> void:
    for body in get_overlapping_bodies():
        if body.is_in_group("portal_travelers"):
            _teleport(body)


func _teleport(body: CharacterBody2D) -> void:
    if not linked_portal:
        return
    var current_speed := minf(MAX_TELEPORT_SPEED, body.velocity.length() * EXIT_SPEED_BOOST)
    var push_direction := Vector2.RIGHT.rotated(linked_portal.global_rotation)
    body.velocity = push_direction * current_speed
    body.global_position = linked_portal.global_position + push_direction * EXIT_BUFFER
