class_name Hitbox extends Area2D

signal hit

@onready var _standing_shape: CollisionShape2D = $StandingShape
@onready var _crouch_shape: CollisionShape2D = $CrouchShape


func _ready() -> void:
    body_entered.connect(_on_body_entered)


func set_crouched(crouched: bool) -> void:
    _standing_shape.set_deferred("disabled", crouched)
    _crouch_shape.set_deferred("disabled", not crouched)


func _on_body_entered(body: Node2D) -> void:
    if body.is_in_group("enemies"):
        hit.emit()
