# Phase 1 Task C — Player Design

Date: 2026-06-16
Scope: Plain `CharacterBody2D` player with portal movement, mouse aim, jump feel, crouch
dodge, portal gun, and enemy-contact death. Three scripts in `characters/player/`. No scenes.

Behavior source: prerefactor `player.gd`, `gun_pivot.gd`, `portal_gun.gd` (facing only).
Reference implementation: refactor-attempt-0 `player.gd`, `gun_pivot.gd` (user-approved reuse).

---

## Goal

The player entity: composition over inheritance (no `PortalEntity` base), portal movement
delegated to the `PortalMovementComponent` shipped in Task B, mouse aim, a buffer+coyote+gather
jump, a grounded crouch-dodge, a portal gun, and death on enemy contact. Exposes a small public
interface so Task D (LevelController) and Task E (cameras, PortalArm) never reach into internals.

## Decided scope

**Rich port of refactor-attempt-0's game-feel**, reconciled to the Task C contract interface.
This extends the contract's locked "buffer + coyote" jump decision with r-a-0's gather windup
and adds the `fall` anim and per-animation gun bobbing.

---

## `characters/player/player.gd`

`class_name Player extends CharacterBody2D`

### Interface

- `signal died`
- `@export var movement: PortalMovementComponent`
- `func die() -> void`
- `func respawn(pos: Vector2) -> void`
- `func set_portal_container(c: Node2D) -> void` — forwards to `gun_pivot.portal_container`
- `func reset_portals() -> void` — calls `gun_pivot.reset()`
- `func is_facing_left() -> bool` — returns `_sprite.flip_h`
- `func get_gun_global_position() -> Vector2` — returns `gun_pivot.global_position`
- `func get_gun_global_rotation() -> float` — returns `gun_pivot.global_rotation`

Position and rotation are exposed **separately, never as a `Transform2D`** — Task E's PortalArm
is a high-res sprite with its own scale and must not inherit the in-world pivot's transform.

### Constants (ported from r-a-0)

`RUN_SPEED 400.0`, `ACCEL 1000.0`, `FRICTION 1000.0`, `GRAVITY 1500.0`, `JUMP_FORCE -400.0`,
`MAX_FALL_SPEED 2000.0`, `JUMP_BUFFER_TIME 0.15`, `COYOTE_TIME 0.10`, `GATHER_TIME 0.05`,
`ANIM_JUMP_THRESHOLD 50.0`, `ANIM_RUN_THRESHOLD 35.0`. Named consts, not a Resource (Phase 1
scope; Resource extraction deferred).

### Node references

- `@export var movement: PortalMovementComponent` (per contract; `movement.body → Player`
  wired in the Inspector)
- `@onready var _sprite: AnimatedSprite2D = $AnimatedSprite2D`
- `@onready var gun_pivot: GunPivot = $GunPivot`
- `@onready var _hitbox: Hitbox = $Hitbox`

### `_ready`

`add_to_group("player")`; connect `_hitbox.hit → die` with `CONNECT_DEFERRED`.

### `_physics_process(delta)` pipeline

Ordered; preserves the one-frame-stale `is_grounded` contract (read `movement.is_grounded` at
the top, call `movement.move()` last):

1. `_apply_gravity(delta)` — `velocity.y = minf(velocity.y + GRAVITY*delta, MAX_FALL_SPEED)`
   only when `not movement.is_grounded`.
2. `_handle_jump(delta)` — coyote timer, jump buffer, gather windup (see below).
3. `_handle_crouch()` — see §Crouch.
4. `_apply_horizontal(delta)` — if `_crouching`, `velocity.x = 0`; else `move_toward` toward
   `move_dir * RUN_SPEED` with `ACCEL`, decaying to 0 with `FRICTION` when no input.
5. `_update_facing()` — `_sprite.flip_h = get_global_mouse_position().x < global_position.x`.
6. `_update_visual_state()` — pick anim + set `gun_pivot.position_offset` bob.
7. `movement.move(delta)`.
8. `global_position = global_position.round()`.

### Jump (buffer + coyote + gather)

State: `_jump_buffer`, `_coyote_timer`, `_gathering`, `_gather_timer`.

- Grounded refills `_coyote_timer = COYOTE_TIME`; airborne decays it.
- `jump` just-pressed sets `_jump_buffer = JUMP_BUFFER_TIME`; otherwise it decays.
- When `not _gathering and _jump_buffer > 0 and (is_grounded or _coyote_timer > 0)`: start the
  gather (`_gathering = true`, `_gather_timer = GATHER_TIME`, clear buffer + coyote).
- While gathering, decay `_gather_timer`; at 0, `_gathering = false` and `velocity.y = JUMP_FORCE`.

### Crouch (grounded dodge — differs from r-a-0)

`_handle_crouch()`: `_crouching = movement.is_grounded and Input.is_action_pressed("down")
and not _gathering`.

- Driven by `down` (Task A dropped the `crouch` action).
- **Movement hard-locked:** `_apply_horizontal` sets `velocity.x = 0` while `_crouching` (not
  friction decay — friction would let the player drift for several frames).
- **Hurtbox-only shrink:** `_hitbox.set_crouched(_crouching)` shrinks the damageable area so
  high projectiles pass over. Body collision is untouched (a single constant `BodyShape`).
- **Grounded-only**, so it reads as a bullet dodge.
- **Jump cancels crouch:** pressing jump starts the gather (`_gathering = true`), which
  suppresses `_crouching` the same frame via the `not _gathering` guard.

r-a-0 allowed running while crouched and never locked movement or restricted to grounded — these
are the deliberate changes. The body-collision shrink (true low-gap traversal) is reserved for a
future "ball" upgrade and is **out of scope** here.

### `_update_visual_state()`

Anim + `gun_pivot.position_offset` per state (priority order):

| State                                         | Anim     | Gun offset |
| --------------------------------------------- | -------- | ---------- |
| `_gathering`                                  | `gather` | `(0, 11)`  |
| airborne, `velocity.y < -ANIM_JUMP_THRESHOLD` | `jump`   | `(0, -2)`  |
| airborne, `velocity.y > ANIM_JUMP_THRESHOLD`  | `fall`   | `(0, -2)`  |
| `_crouching`                                  | `crouch` | `(0, 8)`   |
| `abs(velocity.x) > ANIM_RUN_THRESHOLD`        | `run`    | `(2, 0)`   |
| else                                          | `idle`   | `(0, 0)`   |

`_play_anim(name)` guards against replaying the current animation.

### `die` / `respawn` (ported)

- `die()`: if already dead, return; set dead, hide sprite, `process_mode =
PROCESS_MODE_DISABLED`, `died.emit()`.
- `respawn(pos)`: if alive, return; set alive, set position, zero velocity, show sprite,
  `process_mode = PROCESS_MODE_INHERIT`.

---

## `characters/player/gun_pivot.gd`

`class_name GunPivot extends Node2D`

A pivot that aims at the mouse and fires the two palette-distinct portals.

### Interface

- `@export var portal_scene: PackedScene`
- `@export var portal_container: Node2D` — where placed portals are parented; injected at
  runtime via `Player.set_portal_container`.
- `var position_offset: Vector2` — set by Player each frame for animation bob.
- `func reset() -> void` — frees both placed portals and clears their references.

### Constants

`SHOOT_RANGE 1000.0`, `SURFACE_OFFSET -2.0`, `PORTAL_SURFACE_MASK 16` (collision layer 5,
PortalSurface).

### Behavior

- `_ready`: cache base position (`_base_position_x/y`) for the bob/flip math.
- `_physics_process`: `rotation = (get_global_mouse_position() - global_position).angle()`;
  flip `position.x` by `-1.0 if cos(rotation) < 0.0 else 1.0` so the muzzle stays on the aimed
  side (a ternary, not `sign()`, which would zero the offset at exactly +/-90 deg), applying
  `position_offset`; `_fire(0)` on `fire_one`, `_fire(1)` on `fire_two`.
- `_fire(slot)`: raycast from `global_position` along `Vector2.RIGHT.rotated(rotation) *
SHOOT_RANGE` with `collision_mask = PORTAL_SURFACE_MASK`. On hit, `_place_portal`.
- `_place_portal(slot, hit_position, hit_normal)`: free the existing portal in that slot (and
  unlink its partner), instantiate `Portal` with `palette_index = slot`, add to
  `portal_container`, set `global_position = hit_position + hit_normal * SURFACE_OFFSET` and
  `global_rotation = hit_normal.angle()`, link the pair if both exist, store the slot ref.

### Notes

- Drops prerefactor's two portal PackedScenes (`portal_1_scene`/`portal_2_scene`) in favor of
  a single `portal_scene` + `palette_index` (Task B decision).
- **AimLine is scene-only** — a static `Line2D` child set in the Inspector, inheriting this
  node's rotation. No script reference (a debug placeholder; the real aim indicator is a later
  decision).

---

## `characters/player/hitbox.gd`

`class_name Hitbox extends Area2D`

An enemy-contact detector that owns its standing/crouch shapes. Generic by composition; the
single user today is the Player.

### Interface

- `signal hit`
- `func set_crouched(crouched: bool) -> void` — toggles `StandingShape`/`CrouchShape`.

### Node references

- `@onready var _standing_shape: CollisionShape2D = $StandingShape`
- `@onready var _crouch_shape: CollisionShape2D = $CrouchShape`

### Behavior

- `_ready`: `body_entered.connect(_on_body_entered)`.
- `_on_body_entered(body)`: if `body.is_in_group("enemies")`, `hit.emit()`.
- `set_crouched(crouched)`: `_standing_shape.set_deferred("disabled", crouched)`;
  `_crouch_shape.set_deferred("disabled", not crouched)`.

### Notes

- Emits a neutral `hit` rather than calling `die()` (r-a-0 fused them) — detection is decoupled
  from response; Player maps `hit → die`.
- The detected group is hardcoded `"enemies"`. A `target_group` `@export` for reuse by enemy
  hurtboxes is **deferred to Phase 2** (no second user yet — YAGNI).
- `collision_mask` is wired in Phase 2 (enemies layer).

---

## Resolved divergences from refactor-attempt-0

| Decision                | Choice                                                        | Why                                                                                  |
| ----------------------- | ------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| Movement method         | `movement.move(delta)`                                        | Task B contract. r-a-0 called `tick`.                                                |
| Crouch movement         | hard `velocity.x = 0`                                         | Friction decay is unreliable (multi-frame drift). r-a-0 let you run while crouched.  |
| Crouch trigger          | `down`                                                        | Task A dropped the `crouch` action. r-a-0 used `crouch`.                             |
| Crouch effect           | hurtbox shrink only                                           | Crouch is a dodge now; body-shrink (traversal) is the future ball upgrade.           |
| Crouch state            | grounded-only                                                 | Reads as a bullet dodge. r-a-0 allowed it anywhere.                                  |
| Hitbox                  | extracted `class_name Hitbox` + `signal hit` + `set_crouched` | Owns the crouch shapes cleanly; decouples detection from response. r-a-0 inlined it. |
| Portal container        | `set_portal_container` setter                                 | Injected at runtime by Task D. r-a-0 set `@export` once in `_ready`.                 |
| Gun position interface  | separate `get_gun_global_position/rotation`                   | PortalArm is high-res with its own scale — never a `Transform2D`.                    |
| `gun_pivot.gd` location | `characters/player/`                                          | Player-owned weapon; this task owns it. r-a-0 placed it in `portal/`.                |

---

## Out of scope

- `Player.tscn` and all Inspector wiring — user builds in the Godot editor (see below).
- Body-collision shrink / low-gap traversal ("ball" upgrade) — later phase.
- `Hitbox` `target_group` generalization — Phase 2 (when enemy hurtboxes exist).
- Real aim indicator — later; AimLine is a scene-only debug placeholder.
- Constants as a `.tres` Resource — deferred.

---

## Scene (user builds)

`Player.tscn`:

```
Player (CharacterBody2D)   [collision_layer = 12, collision_mask = 3]
  AnimatedSprite2D         [anims: idle, run, jump, fall, crouch, gather]
  BodyShape (CollisionShape2D)        [constant; body world/portal collision]
  GunPivot (Node2D)        [script gun_pivot.gd]
    AimLine (Line2D)       [static, Inspector-set points; debug placeholder]
  PortalMovementComponent  [script from Task B; body -> Player]
  Hitbox (Area2D)          [script hitbox.gd; collision_mask set in Phase 2]
    StandingShape (CollisionShape2D)
    CrouchShape (CollisionShape2D)    [disabled by default]
```

Wiring: `PortalMovementComponent.body → Player`; Player `movement →` the component;
`GunPivot.portal_scene → Portal.tscn`.

---

## Validates

Composition over the `PortalEntity` base: the player is a plain `CharacterBody2D` whose portal
behavior, hurtbox, and weapon are all child components, and whose public interface is consumed
by Task D and Task E without reaching into internals.
