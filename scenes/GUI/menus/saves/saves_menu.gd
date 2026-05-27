extends Control

@onready var slot: Label = $VBoxContainer/PanelContainer/Slot

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
    get_tree().paused = true
    SaveManager.current_slot_id = 1
    if SaveManager.list_slots().is_empty():
        Debug.Save.save_current_slot()
    _refresh()

func _refresh() -> void:
    var slots: Array[Dictionary] = SaveManager.list_slots()

    if SaveManager.current_slot_id > slots.size():
        Debug.Save.save_current_slot()
        slots = SaveManager.list_slots()

    var current_slot_meta: Dictionary = {}
    for slot_meta in slots:
        if slot_meta.get("slot_id", 1) == SaveManager.current_slot_id:
            current_slot_meta = slot_meta
            break

    if current_slot_meta:
        var title: String = current_slot_meta.get("title", "Slot %d" % SaveManager.current_slot_id)
        var last_level: String = current_slot_meta.get("last_level", "Desconocido")
        slot.text = "%s\nNivel: %s" % [title, last_level]
    else:
        slot.text = "Archivo vacío %d" % SaveManager.current_slot_id

func _on_exit_button_pressed() -> void:
    get_tree().change_scene_to_file(ScenePaths.MENUS.MAIN)

func _on_load_pressed() -> void:
    get_tree().paused = false
    SceneLoader.load_scene(ScenePaths.PACKED.GAME_WORLD)

func _on_previous_pressed() -> void:
    SaveManager.current_slot_id = max(1, SaveManager.current_slot_id - 1)
    _refresh()

func _on_next_pressed() -> void:
    SaveManager.current_slot_id = min(3, SaveManager.current_slot_id + 1)
    _refresh()

func _on_reset_pressed() -> void:
    Debug.Save.reset_current_slot()
    _refresh()
