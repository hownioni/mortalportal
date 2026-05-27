extends Area2D


func _on_body_entered(body):

	if body.name == "Player":

		var level_controller = (
			get_tree()
			.get_first_node_in_group("persist")
		)

		level_controller.call_deferred("next_level")
