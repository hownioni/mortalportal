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

func test_overlay_flip_v_aiming_right() -> void:
    assert_false(ViewportMath.overlay_flip_v(0.0))

func test_overlay_flip_v_aiming_left() -> void:
    assert_true(ViewportMath.overlay_flip_v(PI))

func test_overlay_flip_v_below_threshold() -> void:
    assert_false(ViewportMath.overlay_flip_v(PI / 2.0 - 0.01))

func test_overlay_flip_v_above_threshold() -> void:
    assert_true(ViewportMath.overlay_flip_v(PI / 2.0 + 0.01))

func test_camera_target_zero_velocity() -> void:
    var result := ViewportMath.camera_target_position(
        Vector2.ZERO, Vector2(1920, 1080), Vector2.ZERO, 0.2, 50.0,
    )
    assert_eq(result, Vector2(960, 540))

func test_camera_target_below_clamp() -> void:
    var result := ViewportMath.camera_target_position(
        Vector2.ZERO, Vector2(1920, 1080), Vector2(100, 0), 0.2, 50.0,
    )
    assert_eq(result, Vector2(980, 540))

func test_camera_target_above_clamp() -> void:
    var result := ViewportMath.camera_target_position(
        Vector2.ZERO, Vector2(1920, 1080), Vector2(1000, -1000), 0.2, 50.0,
    )
    assert_eq(result, Vector2(1010, 490))
