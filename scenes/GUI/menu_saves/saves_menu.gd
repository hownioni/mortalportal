extends Control

@onready var slot: Label = $VBoxContainer/PanelContainer/Slot

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    get_tree().paused = true
    SaveManager.current_slot_id = 1
    if SaveManager.list_slots().is_empty():
        SaveManager.save_current_slot()
    _refresh()

func _refresh() -> void:
    var slots = SaveManager.list_slots()

    if SaveManager.current_slot_id > slots.size():
        SaveManager.save_current_slot()
        slots = SaveManager.list_slots()

    var current_slot_meta = null
    for slot_meta in slots:
        if slot_meta.get("slot_id", 1) == SaveManager.current_slot_id:
            current_slot_meta = slot_meta
            break

    if current_slot_meta:
        var title = current_slot_meta.get("title", "Slot %d" % SaveManager.current_slot_id)
        var last_level = current_slot_meta.get("last_level", "Desconocido")
        slot.text = "%s\nNivel: %s" % [title, last_level]
    else:
        slot.text = "Archivo vacío %d" % SaveManager.current_slot_id

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

func _on_reset_pressed() -> void:
    SaveManager.reset_current_slot()
    _refresh()
