# Phase 1 Task E — Cameras & High-Res Overlay Design

Date: 2026-06-03
Scope: The SubViewport dual-camera pipeline and the high-res gun overlay. One math helper plus
three node scripts, all resolution-agnostic. GUT tests on the deterministic math. A fixed,
forward-compatible `[display]` default. No scenes (user builds `Main.tscn`). First integrated
run happens after this task.

Behavior source: prerefactor `low_res_camera.gd`, `high_res_camera.gd`, `portal_gun.gd`.
Reference implementation: refactor-attempt-0 `world/cameras/low_res_camera.gd`,
`high_res_camera.gd`, `characters/player/portal_arm.gd`, `world/main.tscn`.
Canonical reference: `docs/book-notes/godot-pixel-perfect-rendering.md` (the architecture
prerefactor and r-a-0 were both built from).

---

## Goal

Render gameplay at a fixed low resolution inside a `SubViewport`, snapped to whole pixels, and
present it scaled up through a `SubViewportContainer`. A rigid `LowResCamera` tracks the player
inside the SubViewport; a smooth `HighResCamera` in `Main` space looks at the container and
glides with full float precision (it never touches world coordinates, so the pixel art stays
crisp). A `PortalArm` Sprite2D, also in `Main` space, mirrors the in-world gun so its rotation
is not quantized to the low-res grid.

The deterministic coordinate math (overlay mapping, camera target) is extracted into a tested
helper; the nodes are thin shells. Perceptual feel (`smooth_speed`, `velocity_influence`,
`max_offset`) is `@export` and dialed in-editor. The scripts read sizes at runtime, so they are
**resolution-agnostic** and work under any base/zoom/stretch configuration — static or dynamic.

---

## Resolution model (agreed)

One model, parameterized by an integer `zoom`. Task E ships a fixed `zoom = 2` slice of it.

The single invariant: **the visible world window is always 640x360 world pixels** — the design's
pixel grid, the "base." Everything else scales with `zoom` to keep that window crisp:

- **root viewport = SubViewport = `Vec2(640, 360) * zoom`** (1280x720 at `zoom = 2`). The
  SubViewport renders the world at 1:1 into this buffer; the SubViewport is **not** sized at
  640x360.
- **`HighResCamera.zoom = zoom`.** This magnifies the container so only the central 640x360
  world pixels are shown, scaled up `zoom` times (Nearest filter). It is the SubViewport->screen
  magnification — distinct from `stretch/scale_mode` below.
- **`LowResCamera.zoom = 1`** — it tracks the player at 1:1 inside the buffer; the magnification
  is entirely `HighResCamera`'s job.
- **zoom 1:** root/SubViewport render at 640x360, so the HighRes layer (overlay, UI, shaders)
  also renders at 640x360 — jagged overlay rotation, no two-camera payoff. Acceptable (~360p
  displays are extinct) but not what Task E ships.
- **zoom 2 (this task):** the payoff — the HighRes layer renders at the full 1280x720 (smooth,
  crisp overlay) while the world stays chunky-but-crisp. This is exactly r-a-0's proven config
  (project `viewport = 1280x720`, SubViewport 1280x720, `LowResCamera.zoom = 1`,
  `HighResCamera.zoom = 2`).

`stretch/scale_mode = integer` is a **separate, later** scaling: it floors an oversized/odd OS
window to the largest whole multiple of the `640*zoom` root that fits and black-bars the rest
(aspect kept). It fits the root into the window; it is not the SubViewport magnification.

**Deferred (NOT this task):** making `zoom` *dynamic* — choosing it from the window size and
resizing the root viewport + SubViewport + `HighResCamera.zoom` together at runtime — is the
runtime-resolution feature (`project-resolution-settings`). Task E hard-codes `zoom = 2`. The
r-a-0 menu-clipping failure (MainMenu authored at 1920x1080, controls overflowed when shrunk)
was a responsive-UI bug, not camera math — addressed in Phase 5 UI via the
Control-fits-in-viewport recipe. Both are out of scope here.

---

## Architecture (from the canonical reference)

```
Main (Node2D)
  SubViewportContainer            [Full Rect anchors]
    SubViewport                   [size = root = 640*zoom (1280x720); Nearest; Always update]
      Player                      (instance)
      LevelController
      LowResCamera                [rigid: round(player pos); zoom 1]
  HighResCamera                   [smooth: lerp toward container center + velocity offset; zoom = zoom]
  PortalArm                       [overlay of the gun]
```

The in-world `LowResCamera` only needs exact alignment with the player (never smooth); the
`HighResCamera` only ever looks at an already-snapped rendered image (never needs
pixel-perfection), so it is the only thing allowed to move sub-pixel. The gun arm is the book's
"attach crisp, non-pixelated elements to the HighResCamera side" extension.

---

## `world/cameras/viewport_math.gd`

`class_name ViewportMath extends RefCounted`

Pure static functions, zero node/render dependency, so the SubViewport-to-screen math is
unit-testable without a scene tree (testing-conventions: "extract logic from nodes so it is
assertable"). The two consumers (`PortalArm`, `HighResCamera`) become thin shells.

```gdscript
class_name ViewportMath extends RefCounted

static func overlay_position(
	container_pos: Vector2, container_size: Vector2,
	subviewport_size: Vector2, gun_offset: Vector2,
) -> Vector2:
	var scale := container_size / subviewport_size
	var center := container_pos + container_size / 2.0
	return center + gun_offset * scale

static func overlay_flip_v(rotation: float) -> bool:
	return rotation > PI / 2.0 or rotation < -PI / 2.0

static func camera_target_position(
	container_pos: Vector2, container_size: Vector2,
	player_velocity: Vector2, velocity_influence: float, max_offset: float,
) -> Vector2:
	var center := container_pos + container_size / 2.0
	var offset := player_velocity * velocity_influence
	offset.x = clampf(offset.x, -max_offset, max_offset)
	offset.y = clampf(offset.y, -max_offset, max_offset)
	return center + offset
```

`overlay_position` replicates r-a-0's proven formula
(`center + gun_offset * (container/subviewport)`). When container and SubViewport are the same
size, `scale == 1` and the HighResCamera zoom magnifies arm and world together. The math is
Claude-owned and tested; whether the formula lands the arm on the rendered gun on screen is
validated by playtest (trusting the proven r-a-0 implementation).

---

## `world/cameras/low_res_camera.gd`

`class_name LowResCamera extends Camera2D`

Rigid, dumb tracker. No smoothing belongs here.

```gdscript
class_name LowResCamera extends Camera2D

@export var follow_target: Node2D

func _process(_delta: float) -> void:
	global_position = follow_target.global_position.round()
```

- `follow_target: Node2D` (not `Player`) — it only reads `global_position`; the wider type
  keeps it reusable.
- `.round()` is belt-and-suspenders even though `Player` already rounds itself (book notes §4).
  Single expression — not extracted; a helper here would be ceremony.

---

## `world/cameras/high_res_camera.gd`

`class_name HighResCamera extends Camera2D`

Smooth presentation camera. Deterministic target from the helper; the only perceptual line is
the `lerp`.

```gdscript
class_name HighResCamera extends Camera2D

@export var player: Player
@export var sub_viewport_container: SubViewportContainer
@export var smooth_speed: float = 3.0
@export var velocity_influence: float = 0.2
@export var max_offset: float = 50.0

func _physics_process(delta: float) -> void:
	var target := ViewportMath.camera_target_position(
		sub_viewport_container.global_position,
		sub_viewport_container.size,
		player.velocity,
		velocity_influence,
		max_offset,
	)
	global_position = global_position.lerp(target, smooth_speed * delta)
```

- `@export var player: Player` replaces prerefactor's `level_controller.player` reach-through
  (the `_ready` indirection is gone — direct injection).
- `max_offset` promoted from r-a-0's `const MAX_OFFSET` to an `@export` — it is a feel clamp, so
  it belongs with the other perceptual knobs. Its units are root-space pixels, so the right
  value depends on the chosen `zoom`; dialed in-editor.
- `_physics_process` (not `_process`): keeps the camera on the same tick as movement, avoiding
  render-desync jitter (book notes §6).

---

## `characters/player/portal_arm.gd`

`class_name PortalArm extends Sprite2D`

Overlay of the gun. Sources position/rotation through `Player`'s public interface (no
`gun_pivot` / group reach-through).

```gdscript
class_name PortalArm extends Sprite2D

@export var player: Player
@export var sub_viewport_container: SubViewportContainer
@export var sub_viewport: SubViewport

func _process(_delta: float) -> void:
	var gun_offset := player.get_gun_global_position() - player.global_position
	global_position = ViewportMath.overlay_position(
		sub_viewport_container.global_position,
		sub_viewport_container.size,
		Vector2(sub_viewport.size),
		gun_offset,
	)
	rotation = player.get_gun_global_rotation()
	flip_v = ViewportMath.overlay_flip_v(rotation)
```

- `gun_offset = get_gun_global_position() - player.global_position` recovers the gun's smooth
  local offset. `Player` rounds its own `global_position` each physics frame, so the subtraction
  yields the unrounded (sub-pixel) gun offset — the smooth part the overlay exists to show.
  (Decided this session: reuse existing getters, no new Player method.)
- `extends Sprite2D` (per contract) — `flip_v` is on the node itself, simpler than r-a-0's
  Node2D + child Sprite2D. The small visual arm offset (r-a-0's child at `(5, 0)`) becomes the
  Sprite2D's `offset` in the scene (user-set).
- `Vector2(sub_viewport.size)` — `SubViewport.size` is `Vector2i`; the helper needs float
  `Vector2`. `SubViewportContainer.size` is already `Vector2`.

---

## Tests (the GUT exercise)

`test/unit/world/cameras/test_viewport_math.gd` — pure unit tests, no scene tree, written
test-first (RED before each function exists). Inputs/outputs are exact in float for these clean
numbers, so `assert_eq` is used.

| Function | Case | Input -> Expected |
| --- | --- | --- |
| `overlay_position` | unit scale, zero offset | container 1920x1080 @ origin, sv 1920x1080, off (0,0) -> (960, 540) |
| `overlay_position` | unit scale, applies offset | off (10,-5) -> (970, 535) |
| `overlay_position` | scales by container/sv ratio | sv 960x540 (scale 2), off (10,5) -> (980, 550) |
| `overlay_position` | respects container origin | container @ (100,50), off (0,0) -> (1060, 590) |
| `overlay_flip_v` | aiming right | rotation 0 -> false |
| `overlay_flip_v` | aiming left | rotation PI -> true |
| `overlay_flip_v` | thresholds | PI/2 - 0.01 -> false; PI/2 + 0.01 -> true |
| `camera_target_position` | zero velocity | -> center (960, 540) |
| `camera_target_position` | below clamp | vel (100,0) * 0.2 = 20 -> (980, 540) |
| `camera_target_position` | above clamp | vel (1000,-1000) * 0.2 -> clamped to (1010, 490) |

(The test numbers are abstract geometry, independent of the chosen game resolution.) No test
for `LowResCamera` (`round()` is not a computation) or node wiring (scene wiring is playtest).
The `lerp` smoothing and the three feel knobs are perceptual — untested, dialed in-editor.

---

## project.godot display default (I set; user tunes)

full-refactor already has `textures/canvas_textures/default_texture_filter=0` (Nearest). This
task adds the `[display]` block: the root viewport = the `640*zoom` render resolution (1280x720
at the `zoom = 2` slice), with integer scaling and aspect-preserving black bars. These keys and
values match r-a-0's proven `project.godot`.

```
[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"
```

`viewport_width/height = 1280x720` is the root render resolution for `zoom = 2` (= `640*zoom`),
**not** the 640x360 visible window — that window is the root divided by `HighResCamera.zoom`, and
it is a scene-level consequence, not a project setting. Rendering the root at 1280x720 is what
makes the HighRes overlay smooth; setting it to 640x360 would ship the jagged zoom-1 case. Stretch
`viewport` + `keep` + `integer` then fits this root into an oversized/odd OS window by whole-number
scaling with aspect-preserving black bars. The SubViewport size (1280x720) and `HighResCamera.zoom`
(2) are scene-level and user-owned; making `zoom` (and these three values) dynamic is the deferred
resolution feature.

---

## Resolved divergences

| Decision | Choice | Why |
| --- | --- | --- |
| PortalArm interface | richer (player + container + subviewport) | Slim player-only can't map SubViewport coords to screen. r-a-0's wiring proves the three exports. Contract prose was under-specified. |
| Gun offset source | existing getters (`get_gun_global_position() - player.global_position`) | Honors no-reach-through via methods Task C shipped; no new Player code (decided this session). |
| `max_offset` | `@export` (was r-a-0 `const`) | Perceptual feel clamp; belongs with the other tunables. |
| Resolution numbers | out of code; project.godot default + scene | Scripts read sizes at runtime; forward-compatible with the deferred resolution picker. |
| Resolution slice | fixed `zoom = 2`: root/SubViewport 1280x720, `HighResCamera.zoom = 2`, visible window 640x360 | r-a-0's proven config; the zoom-2 slice is what makes the overlay smooth (zoom 1 would ship it jagged). Dynamic `zoom` is deferred (user-confirmed). |
| Deterministic math | extracted to `ViewportMath` static funcs | Makes overlay/camera math assertable without a scene tree (testing-conventions). |
| LowResCamera target type | `Node2D` | Only reads `global_position`; no Player API needed. |

---

## Dropped from prerefactor / r-a-0

- HighResCamera's `level_controller.player` reach-through + the `_ready` indirection -> direct
  `@export var player: Player`.
- PortalArm's `get_nodes_in_group("characters")` lookup + `player.gun_pivot.*` /
  `player.animated_sprite_2d.*` reach-through -> `Player` public interface.
- r-a-0's PortalArm Node2D + child Sprite2D -> `extends Sprite2D` (contract); arm offset is the
  sprite's `offset` in the scene.

---

## Out of scope (user builds in the Godot editor)

- `Main.tscn` per the architecture tree above, with wiring: `LowResCamera.follow_target ->
  Player`; `HighResCamera.player -> Player`, `.sub_viewport_container -> SubViewportContainer`;
  `PortalArm.player -> Player`, `.sub_viewport_container -> SubViewportContainer`,
  `.sub_viewport -> SubViewport`; `LevelController.player -> Player`, `.levels ->
  [Level1.tscn]`. Set `Main.tscn` as the main scene.
- SubViewport settings (size = root resolution = 1280x720 at `zoom = 2`, Nearest filter, Always
  update, Disable 3D, Audio Listener 2D), SubViewportContainer Full Rect, `HighResCamera.zoom = 2`,
  `LowResCamera.zoom = 1`, `PortalArm` Sprite2D texture + `offset`.
- The dynamic `640*zoom` resolution system, responsive UI, and the resolution picker (deferred;
  resolution-sweep / Control-fits recipes are written there).

---

## Verification

Two-part gate (testing-conventions): GUT suite + parse-check.

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"
```

GUT: expect the new `viewport_math` tests green, exit 0. Parse-check: no output. Full runtime
verification is the Phase 1 runnable checkpoint (player moves/jumps/aims, portals place and
teleport, WorldBounds kills + respawns, `Ctrl+X` cycles levels, pixel art crisp, overlay tracks
the in-world gun, camera follows with velocity smoothing, no console errors) once `Main.tscn`
exists.
