extends Sprite2D

var player = null


func _ready():

	var players = get_tree().get_nodes_in_group("characters")

	if players.size() > 0:
		player = players[0]


func _process(_delta):

	if player == null:
		return

	global_position = player.gun_pivot.global_position
	global_rotation = player.gun_pivot.global_rotation
	flip_v = player.animated_sprite_2d.flip_h
