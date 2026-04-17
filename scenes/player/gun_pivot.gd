extends Node2D

@onready var aim_line: Line2D = $AimLine

var portal_1_scene: PackedScene = preload(ScenePaths.PACKED.OBJECTS.PORTAL_ONE)
var portal_2_scene: PackedScene = preload(ScenePaths.PACKED.OBJECTS.PORTAL_TWO)
var active_portal_1: Node2D = null
var active_portal_2: Node2D = null

var level_controller: LevelController

func _ready() -> void:
    level_controller = owner.level_controller

func _process(_delta: float) -> void:
    look_at(get_global_mouse_position())
    aim_line.points = [Vector2.ZERO, get_local_mouse_position().normalized() * 1000]

    if Input.is_action_just_pressed("fire_one"):
        spawn_portal("one")
    elif Input.is_action_just_pressed("fire_two"):
        spawn_portal("two")

func spawn_portal(type: String) -> void:
    var space_state := get_world_2d().direct_space_state
    var query := PhysicsRayQueryParameters2D.create(global_position, global_position + transform.x * 2000, 1)
    query.collide_with_areas = false

    var result := space_state.intersect_ray(query)

    if result:
        var new_portal: Node2D = null

        if type == "one":
            if active_portal_1: active_portal_1.queue_free()
            new_portal = portal_1_scene.instantiate()
            active_portal_1 = new_portal
        elif type == "two":
            if active_portal_2: active_portal_2.queue_free()
            new_portal = portal_2_scene.instantiate()
            active_portal_2 = new_portal

        level_controller.add_child(new_portal)
        new_portal.global_position = result.position
        new_portal.rotation = result.normal.angle()

        if active_portal_1 and active_portal_2:
            active_portal_1.linked_portal = active_portal_2
            active_portal_2.linked_portal = active_portal_1
