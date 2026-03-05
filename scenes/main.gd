extends Node2D

@export var levels: Array[PackedScene]
@export var sub_viewport: SubViewport
var player: CharacterBody2D = null

var _curr_lvl := 1
var _time_elapsed := 0.0
var _insted_lvl: Node

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    var dict: Dictionary = SaveManager.load_game(SaveManager.curr_save_file)
    _curr_lvl = dict["level"]
    _create_lvl(_curr_lvl)
    
func _process(delta: float) -> void:
    _time_elapsed += delta

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("save_test"):
        SaveManager.save_game(SaveManager.curr_save_file, {
        "level": _curr_lvl,
        "time_elapsed": _time_elapsed
    })
    if event.is_action_pressed("inc_lvl_test"):
        _curr_lvl += 1
        if _curr_lvl > levels.size():
            _curr_lvl = levels.size()

func _create_lvl(lvl_num: int) -> void:
    _insted_lvl = levels[lvl_num - 1].instantiate()
    sub_viewport.add_child(_insted_lvl)
    player = _insted_lvl.get_node("Player")

func _exit_tree() -> void:
    SaveManager.save_game(SaveManager.curr_save_file, {
        "level": _curr_lvl,
        "time_elapsed": _time_elapsed
    })
