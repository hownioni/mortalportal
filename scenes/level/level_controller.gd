extends Node
class_name LevelController

@export var levels: Array[PackedScene]

@onready var player: Player = $Player
@onready var world_bound: CollisionShape2D = $Killzone/WorldBound
@onready var killzone: Area2D = $Killzone

var _player_spawn: Node2D
var _world_bound_spawn: Node2D
var _curr_lvl := 1
var _insted_lvl: Node

func _ready() -> void:
    add_to_group("persist")
    Debug.Save.load_current_slot()

    _create_lvl(_curr_lvl)

func save_to_state(state: Dictionary) -> void:
    state["level"] = {
        "current_level": _curr_lvl
    }

func load_from_state(state: Dictionary) -> void:
    var l: Dictionary = state.get("level", {})
    _curr_lvl = l.get("current_level", 1)

func _create_lvl(lvl_num: int) -> void:
    _insted_lvl = levels[lvl_num - 1].instantiate()
    add_child(_insted_lvl)
    _player_spawn = _insted_lvl.get_node("PlayerSpawn")
    _world_bound_spawn = _insted_lvl.get_node("WorldBoundSpawn")

    player.global_position = _player_spawn.global_position
    world_bound.global_position = _world_bound_spawn.global_position

func _remove_lvl() -> void:
    _insted_lvl.queue_free()

func _reset_lvl() -> void:
    player.respawn(_player_spawn.global_position)
    _remove_lvl()
    _create_lvl(_curr_lvl)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("save_test"):
        Debug.Save.save_current_slot()
    if event.is_action_pressed("inc_lvl_test"):
        _curr_lvl = min(_curr_lvl + 1, levels.size())
