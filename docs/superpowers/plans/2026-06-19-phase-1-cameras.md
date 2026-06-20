# Phase 1 Cameras & High-Res Overlay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the SubViewport dual-camera pipeline and high-res gun overlay as a tested math helper plus three thin node scripts, shipping the fixed `zoom = 2` resolution slice.

**Architecture:** Deterministic coordinate math (overlay mapping, camera target) lives in a `ViewportMath` RefCounted with pure static functions, GUT-tested without a scene tree. Three thin nodes (`LowResCamera`, `HighResCamera`, `PortalArm`) consume it; their wiring is validated by playtest, not unit tests. A fixed `[display]` block sets the 1280x720 root render resolution (640*zoom at zoom 2).

**Tech Stack:** Godot 4.6, GDScript, GUT (`addons/gut/`), GL Compatibility renderer, Jolt Physics.

Spec: `docs/specs/2026-06-03-phase-1-cameras.md`. All work happens in the `task-e-cameras` worktree/branch.

---

## File Structure

- Create: `world/cameras/viewport_math.gd` — `ViewportMath` RefCounted; the three pure static funcs. The only tested file.
- Create: `world/cameras/low_res_camera.gd` — `LowResCamera`; rigid player tracker.
- Create: `world/cameras/high_res_camera.gd` — `HighResCamera`; smooth presentation camera (consumes `ViewportMath`).
- Create: `characters/player/portal_arm.gd` — `PortalArm`; gun overlay (consumes `ViewportMath` + `Player` getters).
- Create: `test/unit/world/cameras/test_viewport_math.gd` — GUT unit tests for `ViewportMath`.
- Modify: `project.godot` — add the `[display]` block before `[rendering]`.

Task order matters: `ViewportMath` (Tasks 1-3) must exist before `HighResCamera`/`PortalArm` (Tasks 5-6), which reference it at parse time.

**Gate commands** (used throughout):
- GUT suite: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
- Parse-check: `godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"`

All GDScript uses **tab** indentation, matching the existing codebase.

---

### Task 1: `ViewportMath.overlay_position`

**Files:**
- Create: `test/unit/world/cameras/test_viewport_math.gd`
- Create: `world/cameras/viewport_math.gd`

- [ ] **Step 1: Write the failing test**

Create `test/unit/world/cameras/test_viewport_math.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: FAIL — GUT reports a parse/compile error on `test_viewport_math.gd` ("Identifier `ViewportMath` not declared" or "Static function `overlay_position` not found"), non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Create `world/cameras/viewport_math.gd`:

```gdscript
class_name ViewportMath extends RefCounted

static func overlay_position(
	container_pos: Vector2, container_size: Vector2,
	subviewport_size: Vector2, gun_offset: Vector2,
) -> Vector2:
	var scale := container_size / subviewport_size
	var center := container_pos + container_size / 2.0
	return center + gun_offset * scale
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: PASS — 4 `overlay_position` tests green (plus the pre-existing capability test), exit 0.

- [ ] **Step 5: Commit**

```bash
git add world/cameras/viewport_math.gd test/unit/world/cameras/test_viewport_math.gd
git commit -m "feat(cameras): add ViewportMath.overlay_position with tests"
```

---

### Task 2: `ViewportMath.overlay_flip_v`

**Files:**
- Modify: `test/unit/world/cameras/test_viewport_math.gd`
- Modify: `world/cameras/viewport_math.gd`

- [ ] **Step 1: Write the failing test**

Append to `test/unit/world/cameras/test_viewport_math.gd`:

```gdscript
func test_overlay_flip_v_aiming_right() -> void:
	assert_false(ViewportMath.overlay_flip_v(0.0))

func test_overlay_flip_v_aiming_left() -> void:
	assert_true(ViewportMath.overlay_flip_v(PI))

func test_overlay_flip_v_below_threshold() -> void:
	assert_false(ViewportMath.overlay_flip_v(PI / 2.0 - 0.01))

func test_overlay_flip_v_above_threshold() -> void:
	assert_true(ViewportMath.overlay_flip_v(PI / 2.0 + 0.01))
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: FAIL — parse error "Static function `overlay_flip_v` not found in base `ViewportMath`", non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Append to `world/cameras/viewport_math.gd`:

```gdscript
static func overlay_flip_v(rotation: float) -> bool:
	return rotation > PI / 2.0 or rotation < -PI / 2.0
```

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: PASS — all `overlay_position` + `overlay_flip_v` tests green, exit 0.

- [ ] **Step 5: Commit**

```bash
git add world/cameras/viewport_math.gd test/unit/world/cameras/test_viewport_math.gd
git commit -m "feat(cameras): add ViewportMath.overlay_flip_v with tests"
```

---

### Task 3: `ViewportMath.camera_target_position`

**Files:**
- Modify: `test/unit/world/cameras/test_viewport_math.gd`
- Modify: `world/cameras/viewport_math.gd`

- [ ] **Step 1: Write the failing test**

Append to `test/unit/world/cameras/test_viewport_math.gd`:

```gdscript
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: FAIL — parse error "Static function `camera_target_position` not found in base `ViewportMath`", non-zero exit.

- [ ] **Step 3: Write minimal implementation**

Append to `world/cameras/viewport_math.gd`:

```gdscript
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

- [ ] **Step 4: Run test to verify it passes**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: PASS — all 11 `ViewportMath` tests green (plus capability test), exit 0.

- [ ] **Step 5: Commit**

```bash
git add world/cameras/viewport_math.gd test/unit/world/cameras/test_viewport_math.gd
git commit -m "feat(cameras): add ViewportMath.camera_target_position with tests"
```

---

### Task 4: `LowResCamera` node

Not unit-tested (`round()` is not a computation; scene wiring is playtest). The gate is the parse-check.

**Files:**
- Create: `world/cameras/low_res_camera.gd`

- [ ] **Step 1: Write the script**

Create `world/cameras/low_res_camera.gd`:

```gdscript
class_name LowResCamera extends Camera2D

@export var follow_target: Node2D

func _process(_delta: float) -> void:
	global_position = follow_target.global_position.round()
```

- [ ] **Step 2: Run the parse-check**

Run: `godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add world/cameras/low_res_camera.gd
git commit -m "feat(cameras): add LowResCamera rigid tracker"
```

---

### Task 5: `HighResCamera` node

Not unit-tested (the deterministic target is covered by Task 3; the `lerp` and feel knobs are perceptual — playtest). Gate is the parse-check. Depends on Task 3 (`ViewportMath`).

**Files:**
- Create: `world/cameras/high_res_camera.gd`

- [ ] **Step 1: Write the script**

Create `world/cameras/high_res_camera.gd`:

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

- [ ] **Step 2: Run the parse-check**

Run: `godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add world/cameras/high_res_camera.gd
git commit -m "feat(cameras): add HighResCamera smooth presentation camera"
```

---

### Task 6: `PortalArm` node

Not unit-tested (overlay math is covered by Tasks 1-2; whether the formula lands the arm on the rendered gun is playtest). Gate is the parse-check. Depends on Tasks 1-2 (`ViewportMath`) and the existing `Player` getters.

**Files:**
- Create: `characters/player/portal_arm.gd`

- [ ] **Step 1: Write the script**

Create `characters/player/portal_arm.gd`:

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

- [ ] **Step 2: Run the parse-check**

Run: `godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add characters/player/portal_arm.gd
git commit -m "feat(player): add PortalArm gun overlay"
```

---

### Task 7: `[display]` block in `project.godot`

Sets the 1280x720 root render resolution (640*zoom at zoom 2) with integer aspect-preserving scaling. Matches r-a-0's proven `project.godot`. Config only — no test; gate is the parse-check.

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Add the `[display]` block**

Insert this block immediately **before** the existing `[rendering]` section line in `project.godot`:

```
[display]

window/size/viewport_width=1280
window/size/viewport_height=720
window/stretch/mode="viewport"
window/stretch/aspect="keep"
window/stretch/scale_mode="integer"

```

(Godot section order is not significant; placing `[display]` before `[rendering]` matches the engine's conventional ordering. `default_texture_filter=0` under `[rendering]` stays as-is.)

- [ ] **Step 2: Run the parse-check**

Run: `godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"`
Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "feat(display): set 1280x720 integer-scaled render resolution"
```

---

### Task 8: Final two-part gate

Confirm the whole task is green before handing off for the editor wiring (out of scope, user-built).

- [ ] **Step 1: Run the GUT suite**

Run: `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
Expected: all tests pass (11 `ViewportMath` tests + the pre-existing capability test), exit 0.

- [ ] **Step 2: Run the parse-check**

Run: `godot --headless --path . --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error"`
Expected: no output.

---

## Out of scope (user builds in the Godot editor, post-plan)

- `Main.tscn` per the spec's architecture tree, with all node wiring (`LowResCamera.follow_target`, `HighResCamera.player`/`.sub_viewport_container`, `PortalArm.player`/`.sub_viewport_container`/`.sub_viewport`, `LevelController.player`/`.levels`). Set `Main.tscn` as the main scene.
- SubViewport settings (size 1280x720, Nearest filter, Always update, Disable 3D, Audio Listener 2D), SubViewportContainer Full Rect, `HighResCamera.zoom = 2`, `LowResCamera.zoom = 1`, `PortalArm` Sprite2D texture (`characters/player/assets/portal_arm.png`) + `offset`.
- Dialing the perceptual knobs (`smooth_speed`, `velocity_influence`, `max_offset`) in the Inspector.
- The Phase 1 runnable playtest checkpoint (player moves/jumps/aims, portals place and teleport, WorldBounds kills + respawns, `Ctrl+X` cycles levels, pixel art crisp, overlay tracks the in-world gun, camera follows with velocity smoothing, no console errors).
- The deferred dynamic-`zoom` resolution system, responsive UI, and resolution picker.
