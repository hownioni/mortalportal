class_name GunPivot extends Node2D

const SHOOT_RANGE: float = 1000.0
const SURFACE_OFFSET: float = -2.0

@export var portal_scene: PackedScene
@export var portal_surface_mask: int = 16 # collision layer 5

var portal_container: Node

var position_offset: Vector2 = Vector2.ZERO

var _portal_a: Portal
var _portal_b: Portal
var _base_position_x: float
var _base_position_y: float


func _ready() -> void:
    _base_position_x = position.x
    _base_position_y = position.y


func _physics_process(_delta: float) -> void:
    rotation = (get_global_mouse_position() - global_position).angle()
    var flip: float = -1.0 if cos(rotation) < 0.0 else 1.0
    position.x = (_base_position_x + position_offset.x) * flip
    position.y = _base_position_y + position_offset.y
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
    var existing: Portal = _portal_a if slot == 0 else _portal_b
    var other: Portal = _portal_b if slot == 0 else _portal_a

    if existing:
        existing.queue_free()
        if other:
            other.linked_portal = null

    var new_portal: Portal = portal_scene.instantiate() as Portal
    new_portal.palette_index = slot
    portal_container.add_child(new_portal)
    new_portal.global_position = hit_position + hit_normal * SURFACE_OFFSET
    new_portal.global_rotation = hit_normal.angle()

    if other:
        new_portal.linked_portal = other
        other.linked_portal = new_portal

    if slot == 0:
        _portal_a = new_portal
    else:
        _portal_b = new_portal
