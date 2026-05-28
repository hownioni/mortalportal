class_name LevelController extends Node

@export var player: Player
@export var levels: Array[PackedScene]

var _curr_lvl: int = 0
var _insted_lvl: LevelBase
var _player_spawn: Node2D


func _ready() -> void:
    player.died.connect(_reset_lvl, CONNECT_DEFERRED)
    _create_lvl(0)
    player.global_position = _player_spawn.global_position


func _input(event: InputEvent) -> void:
    if event.is_action_pressed("inc_lvl_test"):
        _curr_lvl = mini(_curr_lvl + 1, levels.size() - 1)
        _reset_lvl()


func _create_lvl(lvl_num: int) -> void:
    _insted_lvl = levels[lvl_num].instantiate() as LevelBase
    add_child(_insted_lvl)
    _player_spawn = _insted_lvl.player_spawn


func _remove_lvl() -> void:
    _insted_lvl.queue_free()
    for portal in get_tree().get_nodes_in_group("portals"):
        portal.queue_free()


func _reset_lvl() -> void:
    _remove_lvl()
    _create_lvl(_curr_lvl)
    player.respawn(_player_spawn.global_position)
