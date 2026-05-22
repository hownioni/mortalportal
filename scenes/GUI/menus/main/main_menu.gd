extends Control

func _ready() -> void:
	await SceneLoader.load_finished
	get_tree().paused = true

func _on_start_button_pressed() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file(ScenePaths.MENUS.SAVES)

func _on_options_button_pressed() -> void:

	get_tree().change_scene_to_file("res://scenes/tutorial_main.tscn")

func _on_exit_button_pressed() -> void:
	get_tree().quit()
