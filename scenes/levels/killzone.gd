extends Area2D

signal body_angered

@onready var timer: Timer = $Timer

func _on_body_entered(_body: Node2D) -> void:
    timer.start()


func _on_timer_timeout() -> void:
    body_angered.emit()
