extends Node

signal game_paused

func pause_game(is_paused: bool) -> void:
    get_tree().paused = is_paused
    
    if is_paused:
        game_paused.emit()
    
