class_name GunPivot extends Node2D

const SHOOT_RANGE: float = 1000.0
const SURFACE_OFFSET: float = -2.0

@export var portal_scene: PackedScene
@export var portal_surface_mask: int = 16

var portal_container: Node

var _portal_a: Portal
var _portal_b: Portal
var _base_position_x: float


func _ready() -> void:
    _base_position_x = position.x


func _physics_process(_delta: float) -> void:
    rotation = (get_global_mouse_position() - global_position).angle()
    position.x = _base_position_x * (-1.0 if cos(rotation) < 0.0 else 1.0)
    if Input.is_action_just_pressed("fire_one"):
        _fire(0)
    elif Input.is_action_just_pressed("fire_two"):
        _fire(1)


func _fire(slot: int) -> void:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.new()
    query.from = global_position
    query.to = global_position + Vector2.RIGHT.rotated(rotation) * SHOOT_RANGE
    query.collision_mask = portal_surface_mask
    var result := space_state.intersect_ray(query)
    if result.is_empty():
        return
    _place_portal(slot, result["position"], result["normal"])


func _place_portal(slot: int, hit_position: Vector2, hit_normal: Vector2) -> void:
    if slot == 0:
        if _portal_a:
            _portal_a.queue_free()
            if _portal_b:
                _portal_b.linked_portal = null
        _portal_a = portal_scene.instantiate() as Portal
        _portal_a.palette_index = 0
        portal_container.add_child(_portal_a)
        _portal_a.global_position = hit_position + hit_normal * SURFACE_OFFSET
        _portal_a.global_rotation = hit_normal.angle()
        if _portal_b:
            _portal_a.linked_portal = _portal_b
            _portal_b.linked_portal = _portal_a
    else:
        if _portal_b:
            _portal_b.queue_free()
            if _portal_a:
                _portal_a.linked_portal = null
        _portal_b = portal_scene.instantiate() as Portal
        _portal_b.palette_index = 1
        portal_container.add_child(_portal_b)
        _portal_b.global_position = hit_position + hit_normal * SURFACE_OFFSET
        _portal_b.global_rotation = hit_normal.angle()
        if _portal_a:
            _portal_b.linked_portal = _portal_a
            _portal_a.linked_portal = _portal_b
