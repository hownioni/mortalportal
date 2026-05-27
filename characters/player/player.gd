class_name Player extends CharacterBody2D

signal died

const RUN_SPEED: float = 400.0
const ACCEL: float = 1000.0
const FRICTION: float = 1000.0
const GRAVITY: float = 1500.0
const JUMP_FORCE: float = -400.0
const MAX_FALL_SPEED: float = 2000.0
const JUMP_BUFFER_TIME: float = 0.15
const COYOTE_TIME: float = 0.10

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _movement: PortalMovementComponent = $PortalMovementComponent

var _alive: bool = true
var _jump_buffer: float = 0.0
var _coyote_timer: float = 0.0


func _ready() -> void:
	add_to_group("player")
