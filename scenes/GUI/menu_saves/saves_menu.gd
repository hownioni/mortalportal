extends Control

@onready var partida: Label = $VBoxContainer/Partida

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    get_tree().paused = true
    SaveManager.current_slot_id = 1
    if SaveManager.list_slots().is_empty():
        SaveManager.save_current_slot()
    _refresh()

func _refresh() -> void:
    if SaveManager.current_slot_id > SaveManager.list_slots().size():
        SaveManager.save_current_slot()
    partida.text = SaveManager.list_slots()[SaveManager.current_slot_id - 1]["title"]

func _on_exit_button_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/GUI/menu_main/main_menu.tscn")

func _on_load_pressed() -> void:
    get_tree().paused = false
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_previous_pressed() -> void:
    SaveManager.current_slot_id = max(1, SaveManager.current_slot_id - 1)
    _refresh()

func _on_next_pressed() -> void:
    SaveManager.current_slot_id = min(3, SaveManager.current_slot_id + 1)
    _refresh()
