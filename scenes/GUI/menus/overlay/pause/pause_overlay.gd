extends Control
class_name PauseMenu

func _ready() -> void:
    self.visible = false

func _input(event: InputEvent) -> void:
    if event.is_action_pressed("pause") and get_tree().paused == false:
        _pause_game(true)
    elif event.is_action_pressed("pause") and get_tree().paused == true:
        _pause_game(false)

func _pause_game(is_paused: bool) -> void:
    self.visible = is_paused
    get_tree().paused = is_paused

func _on_resume_pressed() -> void:
    _pause_game(false)

func _on_quit_pressed() -> void:
    Debug.Save.save_current_slot()
    SceneLoader.load_scene(ScenePaths.MENUS.MAIN)
    _pause_game(false)
