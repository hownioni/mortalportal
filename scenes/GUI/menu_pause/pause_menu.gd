extends Control
class_name PauseMenu

func _ready() -> void:
    SceneManager.game_paused.connect(_on_scene_manager_game_paused)
    
func _on_scene_manager_game_paused() -> void:
    self.visible = true

func _on_continue_button_pressed() -> void:
    self.visible = false
    SceneManager.pause_game(false)


func _on_exit_button_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/GUI/menu_main/main_menu.tscn")
