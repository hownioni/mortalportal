extends Control


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    get_tree().paused = true

func _on_start_button_pressed() -> void:
    get_tree().paused = false
    get_tree().change_scene_to_file("res://scenes/GUI/menu_saves/saves_menu.tscn")
    
func _on_options_button_pressed() -> void:
    pass # Replace with function body.

func _on_exit_button_pressed() -> void:
    get_tree().quit()

func _on_continue_button_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/GUI/menu_continue/continue_menu.tscn")
