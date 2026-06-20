extends GutTest

func test_overlay_position_unit_scale_zero_offset() -> void:
	var result := ViewportMath.overlay_position(
		Vector2.ZERO, Vector2(1920, 1080), Vector2(1920, 1080), Vector2.ZERO,
	)
	assert_eq(result, Vector2(960, 540))

func test_overlay_position_applies_offset() -> void:
	var result := ViewportMath.overlay_position(
		Vector2.ZERO, Vector2(1920, 1080), Vector2(1920, 1080), Vector2(10, -5),
	)
	assert_eq(result, Vector2(970, 535))

func test_overlay_position_scales_by_container_subviewport_ratio() -> void:
	var result := ViewportMath.overlay_position(
		Vector2.ZERO, Vector2(1920, 1080), Vector2(960, 540), Vector2(10, 5),
	)
	assert_eq(result, Vector2(980, 550))

func test_overlay_position_respects_container_origin() -> void:
	var result := ViewportMath.overlay_position(
		Vector2(100, 50), Vector2(1920, 1080), Vector2(1920, 1080), Vector2.ZERO,
	)
	assert_eq(result, Vector2(1060, 590))
