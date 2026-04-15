extends Sprite2D

@export var sub_viewport_container: SubViewportContainer
@export var level_controller: LevelController

var player: Player

func _ready() -> void:
    player = level_controller.player

func _physics_process(_delta: float) -> void:
    var gun_pivot: Node2D = player.get_node("GunPivot")
    global_position = gun_pivot.position

    look_at(get_global_mouse_position())
    flip_v = player.animated_sprite_2d.flip_h
