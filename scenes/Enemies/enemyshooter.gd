extends PortalEntity

@export var speed := 100.0
@export var detection_range := 250.0

@onready var animated_sprite = $AnimatedSprite2D

const GRAVITY := 1500.0

var player = null


func _physics_process(delta):

    # =========================
    # BUSCAR PLAYER
    # =========================
    if player == null:

        player = get_tree().get_first_node_in_group("characters")

        return


    # =========================
    # GRAVEDAD
    # =========================
    if not is_on_floor():

        velocity.y += GRAVITY * delta


    var distance = (
        player.global_position.x
        - global_position.x
    )


    # =========================
    # IA
    # =========================
    if abs(distance) < detection_range:

        if distance > 0:

            velocity.x = speed

            animated_sprite.flip_h = true

        else:

            velocity.x = -speed

            animated_sprite.flip_h = false

    else:

        velocity.x = 0


    move_and_slide()


    # =========================
    # ANIMACIONES
    # =========================
    if abs(velocity.x) > 1:

        if animated_sprite.animation != "run":

            animated_sprite.play("run")

    else:

        if animated_sprite.animation != "default":

            animated_sprite.play("default")
