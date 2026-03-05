extends Control

@onready var s_1_button: Button = $VBoxContainer/S1Button
@onready var s_2_button: Button = $VBoxContainer/S2Button
@onready var s_3_button: Button = $VBoxContainer/S3Button

func _process(_delta: float) -> void:
    var saves_data: Array[Dictionary] = []
    for i in range(3):
        saves_data.append(SaveManager.load_game(i+1))
    s_1_button.text = "Partida 1\nNivel: %d\nTiempo jugado: %0.2f" % [saves_data[0]["level"], saves_data[0]["time_elapsed"]]
    s_2_button.text = "Partida 2\nNivel: %d\nTiempo jugado: %0.2f" % [saves_data[1]["level"], saves_data[1]["time_elapsed"]]
    s_3_button.text = "Partida 3\nNivel: %d\nTiempo jugado: %0.2f" % [saves_data[2]["level"], saves_data[2]["time_elapsed"]]
    
func _on_exit_button_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/GUI/menu_main/main_menu.tscn")
    
func _on_s_1_button_pressed() -> void:
    get_tree().paused = false
    SaveManager.curr_save_file = 1
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_s_2_button_pressed() -> void:
    get_tree().paused = false
    SaveManager.curr_save_file = 2
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_s_3_button_pressed() -> void:
    get_tree().paused = false
    SaveManager.curr_save_file = 3
    get_tree().change_scene_to_file("res://scenes/main.tscn")


func _on_delete_1_button_pressed() -> void:
    SaveManager.reset_game(1)
    
func _on_delete_2_button_pressed() -> void:
    SaveManager.reset_game(2)
    
func _on_delete_3_button_pressed() -> void:
    SaveManager.reset_game(3)
