extends Node2D

@export var levels: Array[PackedScene]
@export var sub_viewport: SubViewport

var player: Player = null
var low_res_camera: Camera2D = null

var _curr_lvl := 1
var _insted_lvl: Node

# Called when the node enters the scene tree for the first time.
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
    sub_viewport.add_child(_insted_lvl)
    player = _insted_lvl.get_node("Player")
    #low_res_camera = _insted_lvl.get_node("LowResCamera")
    player.player_died.connect(_reset_lvl)

func _remove_lvl() -> void:
    _insted_lvl.queue_free()

func _reset_lvl() -> void:
    _remove_lvl()
    _create_lvl(_curr_lvl)

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("save_test"):
        Debug.Save.save_current_slot()
    if event.is_action_pressed("inc_lvl_test"):
        _curr_lvl = min(_curr_lvl + 1, levels.size())
