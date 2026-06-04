# Phase 1 Task B — Portal System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement host-agnostic portal traversal as composition — `PortalMovementComponent` (child node) + `Portal` (Area2D) — replacing the prerefactor `PortalEntity` base class.

**Architecture:** Two scripts in `portal/`. The component ports `custom_move_and_slide` and registers its host in `"portal_travelers"`. `Portal` teleports any overlapping traveler and renders a palette variant via shader. Detection is group-based, not type-based. Full design: `docs/specs/2026-06-03-phase-1-portal.md`.

**Tech Stack:** Godot 4.6, GDScript, GL Compatibility renderer, Jolt Physics.

---

## Verification model (read first)

This project has **no test framework** (GUT is not installed) and portal traversal cannot be
unit-tested in isolation: teleport needs a traveler body (the Player, Task C) inside an
assembled scene. So Task B verification is:

1. **Per-script parse/type check** — `godot --headless --check-only --script <path>`, expect
   exit 0 and no `SCRIPT ERROR` / `Parse Error` output. (Both scripts in this plan were
   pre-verified against Godot v4.6.3 with exit 0.)
2. **Functional teleport playtest** — deferred to Task C, when a `CharacterBody2D` traveler
   with this component exists. Noted explicitly; do not fake it here.

> Do NOT run the full `godot --headless --import` for verification: it exits 134 (SIGABRT)
> from the `godot-git-plugin` VCS extension failing in headless mode. Use `--check-only
> --script` on the specific file instead.

**Commits:** This project's owner commits only on request. Each task ends with a commit step,
but at execution time confirm before running `git commit`.

---

## File structure

- Create: `portal/portal_movement_component.gd` — the movement component (`class_name PortalMovementComponent`).
- Create: `portal/portal.gd` — the portal world object (`class_name Portal`).
- Create (copy): `portal/assets/portal.png` — portal sprite frame (from refactor-attempt-0).
- Create (user, in editor): `portal/portal.tscn` — the assembled Portal scene.

Already present from Task A: `portal/assets/palette_swap.gdshader`, `portal/assets/palettes.png`.

---

## Task 1: Copy the portal sprite asset

The `AnimatedSprite2D` in `Portal.tscn` needs a texture. We follow r-a-0's single-scene
palette approach, so we use its single `portal.png` (not prerefactor's two-variant textures).
Per project convention, `.import` files are not copied — Godot regenerates them on import.

**Files:**
- Create: `portal/assets/portal.png` (copied from `../mortalportal-refactor-attempt-0/portal/assets/portal.png`)

- [ ] **Step 1: Copy the texture (not the `.import`)**

```bash
cp /home/migu/repos/GitHub/mortalportal-refactor-attempt-0/portal/assets/portal.png \
   /home/migu/repos/GitHub/mortalportal/portal/assets/portal.png
```

- [ ] **Step 2: Verify it landed**

Run: `ls -1 portal/assets/`
Expected: `palette_swap.gdshader`, `palette_swap.gdshader.uid`, `palettes.png`, `portal.png`
(plus any untracked `*.import` files, which are not committed).

- [ ] **Step 3: Commit**

```bash
git add portal/assets/portal.png
git commit -m "Phase 1 Task B: add portal sprite asset"
```

---

## Task 2: PortalMovementComponent

Ports prerefactor `portal_entity.gd::custom_move_and_slide` into a composition component.
The ground threshold is the corrected `cos(PI/4)` (true 45°), not the prerefactor's bare
`PI/4` (~38°) — see spec.

**Files:**
- Create: `portal/portal_movement_component.gd`

- [ ] **Step 1: Write the component**

```gdscript
class_name PortalMovementComponent extends Node

const GROUND_DOT_THRESHOLD := cos(PI / 4)
const WALL_QUERY_OFFSET := -2.0

@export var body: CharacterBody2D

var is_grounded := false


func _ready() -> void:
	body.add_to_group("portal_travelers")


func move(delta: float) -> void:
	is_grounded = false
	var collision := body.move_and_collide(body.velocity * delta)
	if not collision:
		return
	if collision.get_normal().dot(Vector2.UP) > GROUND_DOT_THRESHOLD:
		is_grounded = true
	if _find_portal_at_collision(collision):
		return
	body.velocity = body.velocity.slide(collision.get_normal())
	var remainder := collision.get_remainder()
	var slide_collision := body.move_and_collide(remainder.slide(collision.get_normal()))
	if slide_collision and slide_collision.get_normal().dot(Vector2.UP) > GROUND_DOT_THRESHOLD:
		is_grounded = true


func _find_portal_at_collision(collision: KinematicCollision2D) -> Area2D:
	var space_state := body.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = collision.get_position() + collision.get_normal() * WALL_QUERY_OFFSET
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in space_state.intersect_point(query):
		if result.collider.is_in_group("portals"):
			return result.collider
	return null
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --check-only --script portal/portal_movement_component.gd 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output** (grep prints nothing → no parse/type errors). Do not gate on the
shell exit code here — that reflects grep, not godot.

- [ ] **Step 3: Commit**

```bash
git add portal/portal_movement_component.gd
git commit -m "Phase 1 Task B: PortalMovementComponent"
```

---

## Task 3: Portal

Ports prerefactor `portal.gd` with group-based detection, single-scene palette variant, and
named constants.

**Files:**
- Create: `portal/portal.gd`

- [ ] **Step 1: Write the portal**

```gdscript
class_name Portal extends Area2D

const EXIT_BUFFER := 40
const MAX_TELEPORT_SPEED := 20000.0
const EXIT_SPEED_BOOST := 1.1

@export var linked_portal: Portal
@export var palette_index: int = 0

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D


func _ready() -> void:
	add_to_group("portals")
	if _sprite.material:
		_sprite.material = _sprite.material.duplicate()
		_sprite.material.set_shader_parameter("palette_index", palette_index)


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body.is_in_group("portal_travelers"):
			_teleport(body)


func _teleport(body: CharacterBody2D) -> void:
	if not linked_portal:
		return
	var current_speed := minf(MAX_TELEPORT_SPEED, body.velocity.length() * EXIT_SPEED_BOOST)
	var push_direction := Vector2.RIGHT.rotated(linked_portal.global_rotation)
	body.velocity = push_direction * current_speed
	body.global_position = linked_portal.global_position + push_direction * EXIT_BUFFER
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --check-only --script portal/portal.gd 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output** (grep prints nothing → no parse/type errors). Do not gate on the
shell exit code here — that reflects grep, not godot.

- [ ] **Step 3: Commit**

```bash
git add portal/portal.gd
git commit -m "Phase 1 Task B: Portal"
```

---

## Task 4: Assemble `Portal.tscn` (user, in the Godot editor)

Scene creation is the user's responsibility. This is the step-by-step editor guide. The
result mirrors r-a-0's `portal.tscn` structure, adapted to this project's layer names.

**File:** `portal/portal.tscn`

- [ ] **Step 1: Create the scene root**
  - Scene > New Scene > Other Node > `Area2D`.
  - Rename the root node to `Portal`.

- [ ] **Step 2: Attach the script**
  - Select `Portal`, attach script `res://portal/portal.gd` (use the existing file, do not
    let the editor generate a new one).

- [ ] **Step 3: Set collision layers/masks** (Inspector > Collision, on the `Portal` Area2D)
  - **Layer:** check only **PortalSurface** (layer 5). Numeric value `16`. This is the layer
    the movement component's point query looks for; leaving it on the default Walls (1) is
    semantically wrong.
  - **Mask:** check **Player** (layer 3) and **PortalEntities** (layer 4). Numeric value
    `12`. This is what `get_overlapping_bodies()` detects — the travelers.

- [ ] **Step 4: Add the sprite**
  - Add child node `AnimatedSprite2D`.
  - **sprite_frames:** in the Inspector, create a new `SpriteFrames`. In the SpriteFrames
    panel, keep the `default` animation, set **Speed = 5.0**, **Loop = on**, and add one frame
    using `res://portal/assets/portal.png`.
  - **material:** create a new `ShaderMaterial`. Set:
    - `shader` = `res://portal/assets/palette_swap.gdshader`
    - shader param `palette_tex` = `res://portal/assets/palettes.png`
    - shader param `palette_index` = `0` (the script overrides this at runtime from the
      `Portal.palette_index` export; the scene value is just the editor preview).

- [ ] **Step 5: Add the collision shape**
  - Add child node `CollisionShape2D`.
  - **shape:** new `RectangleShape2D`, **size = (8, 26)**.
  - **position = (2, 0)** (matches both reference scenes).

- [ ] **Step 6: Save**
  - Save as `res://portal/portal.tscn`.

- [ ] **Step 7: Import sanity check**
  - Reopen the project (or let it reimport). Confirm the `Portal` node shows no script errors
    and the sprite renders. `linked_portal` and `palette_index` appear as exports in the
    Inspector — they are wired per-instance later (placed portals get linked in the level,
    Task D).

- [ ] **Step 8: Commit (user)**

```bash
git add portal/portal.tscn
git commit -m "Phase 1 Task B: Portal scene"
```

---

## Done criteria

- `portal/portal_movement_component.gd` and `portal/portal.gd` both parse-check with exit 0.
- `portal/assets/portal.png` present.
- `portal/portal.tscn` assembled with layer 16 / mask 12, sprite frames, palette ShaderMaterial, and an 8x26 collision shape.
- Functional teleport playtest is deferred to Task C (needs a traveler). This is expected — Task B has no in-isolation runtime test.
