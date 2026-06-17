# Phase 1 Task C — Player Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the player as a plain `CharacterBody2D` whose portal movement, hurtbox, and weapon are child components — buffer+coyote+gather jump, grounded crouch-dodge, mouse aim, portal gun, and death on enemy contact.

**Architecture:** Three scripts in `characters/player/`. `Player` orchestrates a decomposed `_physics_process` and delegates movement to Task B's `PortalMovementComponent`. `GunPivot` aims and fires the two palette-distinct portals. `Hitbox` self-wires enemy-contact detection and owns the crouch shapes, emitting a neutral `hit` signal. Communication is signals + injected refs; nothing reaches into another scene's internals. Full design: `docs/specs/2026-06-03-phase-1-player.md`.

**Tech Stack:** Godot 4.6, GDScript, GL Compatibility renderer, Jolt Physics.

---

## Verification model (read first)

This project has **no test framework** (GUT is not installed), and the player cannot be
runtime-tested in isolation: it needs an assembled `Player.tscn` plus a level (Tasks D/E). So
per-task verification here is a **project-wide parse/type check**:

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"
```

Expected: **no output** (grep prints nothing → no parse/type errors). Verified working in this
environment against Godot v4.6.3.stable (exit 0, no SIGABRT).

> Use `--import`, **not** `--check-only --script <file>`. `--import` rescans the whole project
> and registers every `class_name` global, so cross-file types resolve. `player.gd` references
> `PortalMovementComponent`, `GunPivot`, and `Hitbox`; `--check-only --script` does not register
> globals and would emit false "Could not find type" errors. (Task B's plan warned `--import`
> SIGABRTs from a git plugin — that no longer reproduces here; `--import` is the correct command
> for Task C either way.)

**Task ordering matters.** `hitbox.gd` and `gun_pivot.gd` have no unmet `class_name`
dependencies (GunPivot references `Portal`, which already exists from Task B). `player.gd`
references all three of `PortalMovementComponent`, `GunPivot`, `Hitbox`, so it must be written
**last**, after the other two class names are registered.

**Indentation:** Godot GDScript uses **tabs**, not spaces. Write all `.gd` files with tab
indentation (Task B's `portal.gd` needed a tab-fixup linter pass — avoid that here).

**Commits:** This project's owner commits on request. Each task ends with a commit step; the
user already asked for the spec + plan, but confirm before committing the implementation tasks.

---

## File structure

- Create: `characters/player/hitbox.gd` — `class_name Hitbox extends Area2D`. Enemy-contact
  detection + crouch shape ownership. No cross-file deps.
- Create: `characters/player/gun_pivot.gd` — `class_name GunPivot extends Node2D`. Mouse aim +
  portal firing. Depends on `Portal` (Task B).
- Create: `characters/player/player.gd` — `class_name Player extends CharacterBody2D`. The
  player orchestrator. Depends on `PortalMovementComponent`, `GunPivot`, `Hitbox`.
- Create (user, in editor): `characters/player/player.tscn` — the assembled Player scene.

Note: node references in `player.gd` are all private (`_sprite`, `_gun_pivot`, `_hitbox`) — the
spec wrote `gun_pivot` without the underscore informally; private is used here for consistency
and because nothing external touches the pivot (Task E uses the public getter methods).

---

## Task 1: Hitbox

Enemy-contact detector that owns its standing/crouch shapes. Emits a neutral `hit` (Player maps
`hit → die`), decoupling detection from response. The detected group is hardcoded `"enemies"`;
a `target_group` export for enemy hurtboxes is deferred to Phase 2 (no second user yet).

**Files:**
- Create: `characters/player/hitbox.gd`

- [ ] **Step 1: Write the hitbox**

```gdscript
class_name Hitbox extends Area2D

signal hit

@onready var _standing_shape: CollisionShape2D = $StandingShape
@onready var _crouch_shape: CollisionShape2D = $CrouchShape


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func set_crouched(crouched: bool) -> void:
	_standing_shape.set_deferred("disabled", crouched)
	_crouch_shape.set_deferred("disabled", not crouched)


func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("enemies"):
		hit.emit()
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output**. (Do not gate on shell exit code — that reflects grep, not godot.)

- [ ] **Step 3: Commit**

```bash
git add characters/player/hitbox.gd
git commit -m "Phase 1 Task C: Hitbox"
```

---

## Task 2: GunPivot

Aims at the mouse and fires the two palette-distinct portals. Ports r-a-0's `gun_pivot.gd`:
single `portal_scene` + `palette_index` (drops prerefactor's two PackedScenes), named constants,
runtime-injected `portal_container`, public `position_offset` for the animation bob, and a new
`reset()` that frees both placed portals.

**Files:**
- Create: `characters/player/gun_pivot.gd`

- [ ] **Step 1: Write the gun pivot**

```gdscript
class_name GunPivot extends Node2D

const SHOOT_RANGE := 1000.0
const SURFACE_OFFSET := -2.0
const PORTAL_SURFACE_MASK := 16

@export var portal_scene: PackedScene
@export var portal_container: Node2D

var position_offset := Vector2.ZERO

var _portal_a: Portal
var _portal_b: Portal
var _base_position_x: float
var _base_position_y: float


func _ready() -> void:
	_base_position_x = position.x
	_base_position_y = position.y


func _physics_process(_delta: float) -> void:
	rotation = (get_global_mouse_position() - global_position).angle()
	var flip := -1.0 if cos(rotation) < 0.0 else 1.0
	position.x = (_base_position_x + position_offset.x) * flip
	position.y = _base_position_y + position_offset.y
	if Input.is_action_just_pressed("fire_one"):
		_fire(0)
	elif Input.is_action_just_pressed("fire_two"):
		_fire(1)


func reset() -> void:
	if _portal_a:
		_portal_a.queue_free()
		_portal_a = null
	if _portal_b:
		_portal_b.queue_free()
		_portal_b = null


func _fire(slot: int) -> void:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = global_position + Vector2.RIGHT.rotated(rotation) * SHOOT_RANGE
	query.collision_mask = PORTAL_SURFACE_MASK
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	_place_portal(slot, result["position"], result["normal"])


func _place_portal(slot: int, hit_position: Vector2, hit_normal: Vector2) -> void:
	var existing: Portal = _portal_a if slot == 0 else _portal_b
	var other: Portal = _portal_b if slot == 0 else _portal_a
	if existing:
		existing.queue_free()
		if other:
			other.linked_portal = null
	var new_portal := portal_scene.instantiate() as Portal
	new_portal.palette_index = slot
	portal_container.add_child(new_portal)
	new_portal.global_position = hit_position + hit_normal * SURFACE_OFFSET
	new_portal.global_rotation = hit_normal.angle()
	if other:
		new_portal.linked_portal = other
		other.linked_portal = new_portal
	if slot == 0:
		_portal_a = new_portal
	else:
		_portal_b = new_portal
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output**.

- [ ] **Step 3: Commit**

```bash
git add characters/player/gun_pivot.gd
git commit -m "Phase 1 Task C: GunPivot"
```

---

## Task 3: Player

The orchestrator. Plain `CharacterBody2D` (no `PortalEntity` base). Decomposed
`_physics_process`, buffer+coyote+gather jump, grounded crouch-dodge with hard movement lock,
mouse-facing, gun bob, and the public interface for Tasks D/E. Preserves the one-frame-stale
`is_grounded` ordering (read top, `movement.move()` last).

**Files:**
- Create: `characters/player/player.gd`

- [ ] **Step 1: Write the player**

```gdscript
class_name Player extends CharacterBody2D

signal died

const RUN_SPEED := 400.0
const ACCEL := 1000.0
const FRICTION := 1000.0
const GRAVITY := 1500.0
const JUMP_FORCE := -400.0
const MAX_FALL_SPEED := 2000.0
const JUMP_BUFFER_TIME := 0.15
const COYOTE_TIME := 0.10
const GATHER_TIME := 0.05
const ANIM_JUMP_THRESHOLD := 50.0
const ANIM_RUN_THRESHOLD := 35.0

@export var movement: PortalMovementComponent

@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var _gun_pivot: GunPivot = $GunPivot
@onready var _hitbox: Hitbox = $Hitbox

var _alive := true
var _jump_buffer := 0.0
var _coyote_timer := 0.0
var _gathering := false
var _gather_timer := 0.0
var _crouching := false


func _ready() -> void:
	add_to_group("player")
	_hitbox.hit.connect(die, CONNECT_DEFERRED)


func _physics_process(delta: float) -> void:
	_apply_gravity(delta)
	_handle_jump(delta)
	_handle_crouch()
	_apply_horizontal(delta)
	_update_facing()
	_update_visual_state()
	movement.move(delta)
	global_position = global_position.round()


func _apply_gravity(delta: float) -> void:
	if not movement.is_grounded:
		velocity.y = minf(velocity.y + GRAVITY * delta, MAX_FALL_SPEED)


func _handle_jump(delta: float) -> void:
	if movement.is_grounded:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if not _gathering and _jump_buffer > 0.0 and (movement.is_grounded or _coyote_timer > 0.0):
		_gathering = true
		_gather_timer = GATHER_TIME
		_jump_buffer = 0.0
		_coyote_timer = 0.0
	if _gathering:
		_gather_timer = maxf(0.0, _gather_timer - delta)
		if _gather_timer == 0.0:
			_gathering = false
			velocity.y = JUMP_FORCE


func _handle_crouch() -> void:
	_crouching = movement.is_grounded and Input.is_action_pressed("down") and not _gathering
	_hitbox.set_crouched(_crouching)


func _apply_horizontal(delta: float) -> void:
	if _crouching:
		velocity.x = 0.0
		return
	var move_dir := Input.get_axis("left", "right")
	if move_dir:
		velocity.x = move_toward(velocity.x, move_dir * RUN_SPEED, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, FRICTION * delta)


func _update_facing() -> void:
	_sprite.flip_h = get_global_mouse_position().x < global_position.x


func _update_visual_state() -> void:
	if _gathering:
		_play_anim("gather")
		_gun_pivot.position_offset = Vector2(0, 11)
	elif not movement.is_grounded and velocity.y < -ANIM_JUMP_THRESHOLD:
		_play_anim("jump")
		_gun_pivot.position_offset = Vector2(0, -2)
	elif not movement.is_grounded and velocity.y > ANIM_JUMP_THRESHOLD:
		_play_anim("fall")
		_gun_pivot.position_offset = Vector2(0, -2)
	elif _crouching:
		_play_anim("crouch")
		_gun_pivot.position_offset = Vector2(0, 8)
	elif absf(velocity.x) > ANIM_RUN_THRESHOLD:
		_play_anim("run")
		_gun_pivot.position_offset = Vector2(2, 0)
	else:
		_play_anim("idle")
		_gun_pivot.position_offset = Vector2.ZERO


func _play_anim(anim_name: String) -> void:
	if _sprite.animation != anim_name:
		_sprite.play(anim_name)


func die() -> void:
	if not _alive:
		return
	_alive = false
	_sprite.visible = false
	process_mode = Node.PROCESS_MODE_DISABLED
	died.emit()


func respawn(pos: Vector2) -> void:
	if _alive:
		return
	_alive = true
	global_position = pos
	velocity = Vector2.ZERO
	_sprite.visible = true
	process_mode = Node.PROCESS_MODE_INHERIT


func set_portal_container(c: Node2D) -> void:
	_gun_pivot.portal_container = c


func reset_portals() -> void:
	_gun_pivot.reset()


func is_facing_left() -> bool:
	return _sprite.flip_h


func get_gun_global_position() -> Vector2:
	return _gun_pivot.global_position


func get_gun_global_rotation() -> float:
	return _gun_pivot.global_rotation
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output**. (All three `class_name` types — `PortalMovementComponent`, `GunPivot`,
`Hitbox` — now exist, so cross-file references resolve.)

- [ ] **Step 3: Commit**

```bash
git add characters/player/player.gd
git commit -m "Phase 1 Task C: Player"
```

---

## Task 4: Assemble `Player.tscn` (user, in the Godot editor)

Scene creation is the user's responsibility. Step-by-step editor guide; mirrors r-a-0's
`player.tscn` structure adapted to this project's layer names and the rich-feel anim set.

**File:** `characters/player/player.tscn`

- [ ] **Step 1: Create the scene root**
  - Scene > New Scene > Other Node > `CharacterBody2D`. Rename root to `Player`.
  - Attach script `res://characters/player/player.gd` (use the existing file).

- [ ] **Step 2: Set the body's collision layers/masks** (Inspector > Collision, on `Player`)
  - **Layer:** Player (3) + PortalEntities (4). Numeric value **12**.
  - **Mask:** Walls (1) + layer 2. Numeric value **3**. (Ported from prerefactor; this is what
    the body collides with for ground/walls.)

- [ ] **Step 3: Add the sprite**
  - Add child `AnimatedSprite2D`. Create a `SpriteFrames` with **6 animations**:
    `idle`, `run`, `jump`, `fall`, `crouch`, `gather`. Populate each with its frames from the
    player sprite assets. (`fall` and `gather` are new vs prerefactor's 4-anim set — they back
    the rich-feel additions.)

- [ ] **Step 4: Add the body collision shape**
  - Add child `CollisionShape2D`, rename to `BodyShape`. Give it a `RectangleShape2D` sized to
    the standing player. This is a **single constant shape** — it does NOT swap on crouch.

- [ ] **Step 5: Add the GunPivot**
  - Add child `Node2D`, rename to `GunPivot`, attach `res://characters/player/gun_pivot.gd`.
  - In the Inspector set **`portal_scene`** = `res://portal/portal.tscn`. Leave
    **`portal_container`** empty (injected at runtime by the LevelController, Task D).
  - Position the pivot at the player's gun origin (the offset the bob math pivots around).
  - Add a child `Line2D` named `AimLine` under `GunPivot`: set two points (e.g. `(0,0)` and
    `(1000,0)`) and a debug width/color. **No script** — it inherits the pivot's rotation. This
    is a debug placeholder for aim direction.

- [ ] **Step 6: Add the PortalMovementComponent**
  - Add child `Node`, rename to `PortalMovementComponent`, attach
    `res://portal/portal_movement_component.gd`.
  - In the Inspector set its **`body`** export → the `Player` root node.

- [ ] **Step 7: Add the Hitbox**
  - Add child `Area2D`, rename to `Hitbox`, attach `res://characters/player/hitbox.gd`.
  - Leave **`collision_mask`** as-is for now (the enemies layer is wired in Phase 2).
  - Add two children to `Hitbox`:
    - `CollisionShape2D` named **`StandingShape`** — full standing hurtbox. `disabled = false`.
    - `CollisionShape2D` named **`CrouchShape`** — the shorter dodge hurtbox. **`disabled =
      true`** (the script enables it on crouch).

- [ ] **Step 8: Wire the Player's exports** (select the `Player` root)
  - **`movement`** export → the `PortalMovementComponent` child node.

- [ ] **Step 9: Save**
  - Save as `res://characters/player/player.tscn`.

- [ ] **Step 10: Import sanity check**
  - Let the project reimport. Confirm `Player` shows no script errors, all six animations exist
    on the `AnimatedSprite2D`, and the `movement` / `GunPivot.portal_scene` exports are wired.

- [ ] **Step 11: Commit (user)**

```bash
git add characters/player/player.tscn
git commit -m "Phase 1 Task C: Player scene"
```

---

## Done criteria

- `characters/player/hitbox.gd`, `gun_pivot.gd`, `player.gd` all parse-check clean (no
  `SCRIPT ERROR` / `Parse Error` from the `--import` command).
- `Player.tscn` assembled: body layer 12 / mask 3, single `BodyShape`, 6-anim
  `AnimatedSprite2D`, `GunPivot` (+ `AimLine`, `portal_scene` wired), `PortalMovementComponent`
  (`body → Player`), `Hitbox` (`StandingShape` enabled, `CrouchShape` disabled), Player
  `movement` export wired.
- Functional playtest (movement, jump feel, crouch dodge, portal fire/traverse, death) is
  deferred to the Phase 1 checkpoint after Tasks D + E assemble a runnable `Main.tscn` — there
  is no in-isolation runtime test for the player. This is expected.
```
