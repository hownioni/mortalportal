extends GutTest

const PocNode := preload("res://test/integration/_poc_node.gd")

func test_node_sets_position_after_one_physics_frame() -> void:
	var node: Node2D = PocNode.new()
	add_child_autofree(node)
	await wait_physics_frames(1)
	assert_eq(node.global_position, Vector2(10.0, 20.0))
