# Camera System Design

**Date:** 2026-05-27
**Branch:** composition_refactor

---

## Problem

Without a SubViewport, the temporary Camera2D in the main scene fails in windowed mode. Godot's integer-scale stretch enforces the 1920x1080 viewport at 1:1 minimum, which means the window clips the viewport instead of scaling it. The SubViewport approach encapsulates game content so the SubViewportContainer always fills the window regardless of size.

---

## Approach

Two-camera system as described in the notkey.studio pixel-perfect tutorial, ported to the new codebase architecture.

- **LowResCamera** (inside SubViewport): Camera2D that pixel-snaps to the player's integer position every visual frame.
- **HighResCamera** (in main scene, outside SubViewport): Camera2D with smooth lerp and velocity lead-ahead. `zoom = Vector2(3, 3)` gives an effective visible area of 640x360 (1920/3 × 1080/3), matching the original game design resolution.

Player.gd already rounds `global_position` at the end of `_physics_process`, so no changes to the player script are needed.

---

## project.godot

No changes. The current file already has:
- `textures/canvas_textures/default_texture_filter=0` (nearest neighbor)
- `window/stretch/mode="viewport"` + `window/stretch/scale_mode="integer"`

---

## Scene Structure

User assembles in editor. `world/main.tscn` becomes:

```
Main (Node2D)
├── SubViewportContainer       anchored full-rect, handle_input_locally=false
│   └── SubViewport            size=1920x1080, canvas_item_default_texture_filter=nearest,
│                              audio_listener_enable_2d=true, render_target_update_mode=always
│       ├── Player
│       ├── LevelController    @export player = Player
│       └── LowResCamera       @export follow_target = Player
└── HighResCamera              zoom=(3,3), @export sub_viewport_container + player
```

`handle_input_locally = false` on SubViewportContainer is required so mouse input (portal gun aiming) passes through to the game correctly.

---

## Scripts

### `world/cameras/low_res_camera.gd`

```gdscript
class_name LowResCamera extends Camera2D

@export var follow_target: Player

func _process(_delta: float) -> void:
    global_position = follow_target.global_position.round()
```

### `world/cameras/high_res_camera.gd`

```gdscript
class_name HighResCamera extends Camera2D

@export var sub_viewport_container: SubViewportContainer
@export var player: Player
@export var smooth_speed: float = 3.0
@export var velocity_influence: float = 0.2

const MAX_OFFSET := 50.0

func _physics_process(delta: float) -> void:
    var center_pos := sub_viewport_container.global_position + Vector2(sub_viewport_container.size) / 2.0
    var target_offset := player.velocity * velocity_influence
    target_offset.x = clamp(target_offset.x, -MAX_OFFSET, MAX_OFFSET)
    target_offset.y = clamp(target_offset.y, -MAX_OFFSET, MAX_OFFSET)
    global_position = global_position.lerp(center_pos + target_offset, smooth_speed * delta)
```

---

## What is not in scope

- GUI / HUD nodes: remain outside SubViewport as a CanvasLayer sibling of SubViewportContainer.
- Camera bounds / level limits: not part of this system.
- project.godot window size settings: no change needed.
