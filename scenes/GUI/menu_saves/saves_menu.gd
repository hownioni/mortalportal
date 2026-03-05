extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    get_tree().paused = true

func _on_exit_button_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/GUI/menu_main/main_menu.tscn")


func _on_s_1_button_pressed() -> void:
    get_tree().paused = false
    var _curr_save = 1
    SaveManager.curr_save_file = _curr_save
    SaveManager.reset_game(_curr_save)
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_s_2_button_pressed() -> void:
    get_tree().paused = false
    var _curr_save = 2
    SaveManager.curr_save_file = _curr_save
    SaveManager.reset_game(_curr_save)
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_s_3_button_pressed() -> void:
    get_tree().paused = false
    var _curr_save = 3
    SaveManager.curr_save_file = _curr_save
    SaveManager.reset_game(_curr_save)
    get_tree().change_scene_to_file("res://scenes/main.tscn")
