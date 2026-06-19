# Godot 4: Pixel-Perfect Low-Resolution Rendering with a Smooth Camera

> Reference notes for implementing strict pixel-art rendering alongside a fluid, non-jittery camera in Godot 4.x.
> Source: [notkey.studio — Pixel-Perfect Low-Resolution Rendering and Smooth Camera](https://notkey.studio/en/tutorials/godot-low-res-pixel-perfect-rendering-and-smooth-camera/)

## Summary

Render the actual gameplay at a fixed low resolution inside a `SubViewport`, snapping everything to whole pixels. Display that `SubViewport` at high resolution through a `SubViewportContainer`, and drive a **second** camera that points at that container. The second camera is free to move with full floating-point precision — it never touches the low-res game world directly — so it can glide smoothly while the underlying art stays perfectly crisp.

## The problems this solves

A naive "low-res viewport + single camera" setup tends to break down for a few reasons:

- **Sub-pixel positions**: engine coordinates are floats, but pixel art only exists at integer positions. Without snapping, sprites get blurred by anti-aliasing or distorted unevenly.
- **Refresh-rate mismatches**: physics runs on a fixed tick (60/sec by default) while rendering runs as fast as the monitor allows. On high-refresh-rate displays (165 Hz+), the renderer ends up drawing in between physics steps, producing ghosting/duplication artifacts. This is easy to miss if you only test on a 60 Hz screen.
- **Rigid vs. floaty camera, pick one**: if the camera snaps to the pixel grid like the rest of the world, movement looks stiff and "notched." If it moves freely, the background appears to vibrate because it's no longer aligned to the grid the art was drawn for.
- **Physics/render desync (jitter)**: moving a camera in `_process` while physics runs in `_physics_process` causes the camera to occasionally overshoot or lag the tracked object, producing visible micro-stutter.

Built-in options like _Project Settings → Rendering → 2D → Snap → Snap 2D Transforms to Pixel_ don't reliably fix this once a smooth-moving camera is involved.

## Architecture

The fix is a deliberate split between the low-res _simulation_ and the high-res _presentation_, using two separate cameras:

```
Root (Node2D)
├─ SubViewportContainer
│  └─ SubViewport
│     └─ LowResGame (Node2D)
│        ├─ LowResCamera (Camera2D)
│        ├─ Player (CharacterBody2D)
│        └─ TileMapLayer
└─ HighResCamera (Camera2D)
```

| Node                   | Role                                                                                                                            |
| ---------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| `Root`                 | Top-level scene loaded at game start.                                                                                           |
| `SubViewportContainer` | Displays and positions the `SubViewport`'s output.                                                                              |
| `SubViewport`          | Renders the game at the fixed low resolution.                                                                                   |
| `LowResGame`           | Container for all actual gameplay nodes.                                                                                        |
| `LowResCamera`         | Rigid camera, locked to the player, used **only** for the low-res render.                                                       |
| `Player`               | The player character.                                                                                                           |
| `TileMapLayer`         | The game world/level geometry.                                                                                                  |
| `HighResCamera`        | The camera that actually appears on screen. Looks at the `SubViewportContainer` and is the only thing allowed to move smoothly. |

Key idea: `LowResCamera` never needs to be smooth — it just has to be exactly aligned with the player at all times. `HighResCamera` never needs to be pixel-perfect — it's looking at an already-rendered, already-snapped image, so it can move with full float precision without breaking anything.

## 1. Choose your resolutions

Pick two numbers up front, since everything downstream depends on them:

- **Internal/low resolution** — the "true" pixel grid of the game (e.g. `320×180`).
- **Final/display resolution** — the resolution the window actually renders at (e.g. `1920×1080`).

The display resolution **must be an exact integer multiple** of the internal resolution. `1920 / 320 = 6`, so this example uses a clean **6x** scale factor. Pick resolutions that divide evenly — fractional scale factors reintroduce the sub-pixel blurring problem you're trying to avoid. (Worth reading up separately on resolution choice for pixel-art games if you haven't settled on a base resolution yet.)

## 2. Project settings

**Project Settings → Rendering → Textures → Canvas Texture**

- Default Texture Filter: `Nearest`

This stops texture interpolation so pixel edges stay sharp.

**Project Settings → Display → Window**

- Viewport Width / Height: set to the **final** resolution (e.g. `1920 × 1080`), not the low-res one — this setup runs the project at full resolution from the start.
- Mode: `Windowed` (optional, your call)
- Stretch → Mode: `viewport`
- Stretch → Appearance: `keep`
- Stretch → Scale Mode: `integer`

These guarantee the game is only ever scaled by whole-number factors, with no fractional pixels, regardless of the player's screen.

## 3. Player script

Add a single line at the end of `_physics_process` to force the player's position onto the integer grid:

```gdscript
global_position = global_position.round()
```

This keeps the player snapped to the pixel grid and prevents ghosting once the rest of the system is in place.

## 4. LowResCamera (rigid camera)

This camera must be as dumb and rigid as possible — no smoothing, no delay. Its only job is to track the player exactly.

```gdscript
# low_res_camera2d.gd
extends Camera2D

@export var follow_target: Node2D

func _process(_delta: float) -> void:
	global_position = follow_target.global_position.round()
```

Assign `Player` as `follow_target`. The extra `.round()` here is a belt-and-suspenders safeguard even though the player already rounds its own position. This is also the right place to add a fixed vertical offset if your gameplay needs one (e.g. looking slightly above the player).

At this point you can test the `LowResGame` scene in isolation — you should see a grid-aligned character, an instantly-tracking (rigid) camera, and a very zoomed-in view, since you're looking at the raw low-res render.

## 5. SubViewport / SubViewportContainer settings

**SubViewport**

- Size → final resolution (e.g. `1920 × 1080`)
- Render Target → Update Mode → `Always`
- Viewport → Disable 3D → `On` (if your game is 2D-only)
- Canvas Items → Default Texture Filter → `Nearest`
- Audio Listener → Enable 2D → `On`

**SubViewportContainer**

- Layout → Anchors Preset → `Full Rect`

The container just needs to fill the screen and stay centered; the `SubViewport` handles the actual low-res rendering and texture filtering.

## 6. HighResCamera (smooth camera)

First, set the camera's zoom to exactly match your scale factor (zoom `6.0 / 6.0` for the example above). With just the zoom set, the game already looks correct (sharp, pixel-perfect) but the camera is still rigid — that's expected at this stage.

Then attach the smoothing script:

```gdscript
# high_res_camera2d.gd
extends Camera2D

@export var player: CharacterBody2D
@export var sub_viewport_container: SubViewportContainer
@export var smooth_speed := 3.0
@export var velocity_influence := 0.2

func _physics_process(delta: float) -> void:
	var center_pos := sub_viewport_container.global_position + (sub_viewport_container.size / 2)

	var target_offset := player.velocity * velocity_influence

	var max_offset := 50.0
	target_offset.x = clamp(target_offset.x, -max_offset, max_offset)
	target_offset.y = clamp(target_offset.y, -max_offset, max_offset)

	var target_pos = center_pos + target_offset

	global_position = global_position.lerp(target_pos, smooth_speed * delta)
```

How it works:

1. **Center point**: `center_pos` is the middle of the `SubViewportContainer` — the natural "neutral" point the camera should rest on, since that's where the low-res render is anchored on screen.
2. **Velocity-based offset, not position-based**: the camera follows the player's _velocity_, not their raw position. The player can wander far across the level; the camera must stay locked to the small frame of the `SubViewportContainer`. Velocity only encodes direction/intensity of movement, which is enough to produce natural lookahead without ever losing that frame of reference.
3. **Clamping**: `target_offset` is clamped to `max_offset` so the camera can't drift far enough to expose the edges of the rendered frame or lose the character.
4. **Lerp**: the clamped offset is added to the center point, and the camera eases toward that target with `lerp()`, which is what produces the smooth motion.
5. **`_physics_process`, not `_process`**: this keeps the camera in step with the same tick as the rest of the physics/movement code, avoiding desync jitter. (`_process` reportedly also works in testing — `_physics_process` was chosen mainly for consistency with the rest of the system, not because it's strictly required.)

Tune `smooth_speed` (how fast the camera catches up) and `velocity_influence` / `max_offset` (how far it's allowed to lead the player) to taste.

## Core rules to keep this working

- Use a **whole-number** scale factor between low-res and final resolution. No exceptions.
- Always `round()` the player's (and other tracked entities') `global_position` to stay grid-aligned.
- Keep the in-world camera (`LowResCamera`) perfectly rigid — no smoothing logic belongs there.
- Render gameplay into a `SubViewport` displayed through a `SubViewportContainer`; never render gameplay directly to the root viewport.
- Keep all smoothing/easing logic on the second camera (`HighResCamera`), which only ever looks at the already-rendered container — never at world-space coordinates directly.

## Extension ideas

- Attach a HUD/UI to `HighResCamera` (or otherwise outside the `SubViewport`) to get crisp, non-pixelated interface elements.
- Resize the final resolution dynamically based on the player's display or settings menu.
- Layer non-pixel-perfect effects (particles, post-processing, screen shake) on top of, or attached to, the `HighResCamera` side without disturbing the pixel-perfect render underneath.
- Extend `HighResCamera` with zoom, shake, or rotation effects — since it's decoupled from the pixel grid, none of this risks breaking pixel-perfect rendering.

## Known caveats

- This pattern is the author's own solution, arrived at after several standard approaches (shader-based snapping, tick-rate changes, moving the camera in `_physics_process` alone) failed to produce reliable results across different refresh rates. It isn't claimed to be the "official" or only correct approach — just one that has worked reliably in production.
- Tested primarily in 2D; the `SubViewport` has `Disable 3D` enabled in this setup.
