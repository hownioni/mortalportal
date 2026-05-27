class_name PortalMovementComponent extends Node

const _DEG_45 := PI / 4
const WALL_QUERY_OFFSET: float = -2.0

@export var body: CharacterBody2D

var is_grounded := false


func _ready() -> void:
    if body:
        body.add_to_group("portal_travelers")


func tick(delta: float) -> void:
    is_grounded = false
    var collision := body.move_and_collide(body.velocity * delta)
    if not collision:
        return
    if collision.get_normal().dot(Vector2.UP) > _DEG_45:
        is_grounded = true
    if _find_portal_at_collision(collision):
        return
    body.velocity = body.velocity.slide(collision.get_normal())
    var remainder: Vector2 = collision.get_remainder()
    var slide_collision := body.move_and_collide(remainder.slide(collision.get_normal()))
    if slide_collision and slide_collision.get_normal().dot(Vector2.UP) > _DEG_45:
        is_grounded = true


func _find_portal_at_collision(collision: KinematicCollision2D) -> Area2D:
    var space_state := body.get_world_2d().direct_space_state
    var query := PhysicsPointQueryParameters2D.new()
    query.position = collision.get_position() + collision.get_normal() * WALL_QUERY_OFFSET
    query.collide_with_areas = true
    query.collide_with_bodies = false
    for result in space_state.intersect_point(query):
        if result.collider.is_in_group("portals"):
            return result.collider
    return null
