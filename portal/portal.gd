class_name Portal extends Area2D

const EXIT_BUFFER := 40

@export var linked_portal: Area2D


func _ready() -> void:
	add_to_group("portals")


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is CharacterBody2D and body.is_in_group("portal_travelers"):
			_teleport(body)


func _teleport(body: CharacterBody2D) -> void:
	if not linked_portal:
		return
	var current_speed: float = minf(20000.0, body.velocity.length() * 1.1)
	var push_direction := Vector2.RIGHT.rotated(linked_portal.global_rotation)
	body.velocity = push_direction * current_speed
	body.global_position = linked_portal.global_position + push_direction * EXIT_BUFFER
