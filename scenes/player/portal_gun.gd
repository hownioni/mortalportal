extends Sprite2D

@export var sub_viewport_container: SubViewportContainer

var player: Player

func _physics_process(delta: float) -> void:
    player = owner.player
    var gun_pivot: Node2D = player.get_node("GunPivot")
    var pivot_pos = gun_pivot.get_global_transform_with_canvas().origin + sub_viewport_container.global_position
    global_position = pivot_pos
