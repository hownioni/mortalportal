extends CharacterBody2D
class_name PortalEntity

var is_grounded := false

func custom_move_and_slide(delta: float) -> void:
    var collision := move_and_collide(velocity * delta)
    if collision:
        var portal := find_portal_at_collision(collision)

        if collision.get_normal().dot(Vector2.UP) > 0.7:
            is_grounded = true

        if portal: return
        else:
            velocity = velocity.slide(collision.get_normal())

            var remainder := collision.get_remainder()
            var slide_collision := move_and_collide(remainder.slide(collision.get_normal()))
            if slide_collision:
                if slide_collision.get_normal().dot(Vector2.UP) > 0.7:
                    is_grounded = true

func find_portal_at_collision(collision: KinematicCollision2D) -> Area2D:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsPointQueryParameters2D.new()
    query.position = collision.get_position() + (collision.get_normal() * -2.0)
    query.collide_with_areas = true
    query.collide_with_bodies = false

    var results := space_state.intersect_point(query)
    for result in results:
        if result.collider.is_in_group("portalS"):
            return result.collider
    return null
