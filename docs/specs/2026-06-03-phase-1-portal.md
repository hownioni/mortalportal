# Phase 1 Task B — Portal System Design

Date: 2026-06-03
Scope: Portal traversal as composition. Two scripts in `portal/`. No portal gun, no scenes.

Behavior source: prerefactor `portal.gd`, `portal_entity.gd`.
Reference implementation: refactor-attempt-0 `portal.gd`, `portal_movement_component.gd`.

---

## Goal

Host-agnostic portal traversal as a child component, replacing the `PortalEntity` base
class. The same `PortalMovementComponent` attaches to any `CharacterBody2D` (player now,
enemies in Phase 2) with zero inheritance changes. This is the crux bet of Phase 1.

---

## `portal/portal_movement_component.gd`

`class_name PortalMovementComponent extends Node`

A child `Node` that gives its host `CharacterBody2D` portal-aware movement. Ports the
prerefactor `custom_move_and_slide`.

### Interface

- `@export var body: CharacterBody2D` — the host, wired in the Inspector.
- `var is_grounded: bool` — read by the host at the top of its frame (see ordering note).
- `func move(delta: float) -> void` — called by the host in place of `move_and_slide`.

### Constants

- `const GROUND_DOT_THRESHOLD := cos(PI / 4)` — true 45° slope limit (= 0.7071).
- `const WALL_QUERY_OFFSET := -2.0` — point-query nudge just inside the collision surface.

### Behavior (`move`)

1. Reset `is_grounded = false`.
2. `var collision := body.move_and_collide(body.velocity * delta)`.
3. If no collision, return.
4. If `collision.get_normal().dot(Vector2.UP) > GROUND_DOT_THRESHOLD`, set `is_grounded = true`.
5. If `_find_portal_at_collision(collision)` returns a portal, return early (no slide — the
   portal's own teleport takes over this frame).
6. Otherwise slide: `body.velocity = body.velocity.slide(collision.get_normal())`, then a
   second `move_and_collide` on `collision.get_remainder().slide(...)`. If that second
   collision is also an up-facing surface, set `is_grounded = true`.

### `_find_portal_at_collision(collision) -> Area2D` (private)

`PhysicsPointQueryParameters2D` point query at `collision.get_position() + normal *
WALL_QUERY_OFFSET`, `collide_with_areas = true`, `collide_with_bodies = false`. Returns the
first result in group `"portals"`, else `null`.

### Group registration

`_ready()` calls `body.add_to_group("portal_travelers")`. The component owns this; the host
does not. Absence from the group = ignored by portals.

---

## `portal/portal.gd`

`class_name Portal extends Area2D`

A world object that teleports overlapping travelers and renders with a palette variant.

### Interface

- `@export var linked_portal: Portal` — the exit portal.
- `@export var palette_index: int = 0` — selects the palette row in the swap shader.

### Constants

- `const EXIT_BUFFER := 40` — exit offset in px along the exit portal's facing.
- `const MAX_TELEPORT_SPEED := 20000.0` — entry-speed cap.
- `const EXIT_SPEED_BOOST := 1.1` — exit-speed multiplier.

### Behavior

- `_ready()`: `add_to_group("portals")`; duplicate the sprite's `ShaderMaterial` and set
  `palette_index` so each instance is independent.
- `_physics_process(_delta)`: for each body in `get_overlapping_bodies()` that
  `is_in_group("portal_travelers")`, call `_teleport(body)`.
- `_teleport(body)`: if no `linked_portal`, return. Cap entry speed at `MAX_TELEPORT_SPEED`,
  multiply by `EXIT_SPEED_BOOST`. Push direction =
  `Vector2.RIGHT.rotated(linked_portal.global_rotation)`. Set `body.velocity = dir * speed`
  and `body.global_position = linked_portal.global_position + dir * EXIT_BUFFER`.

---

## Resolved divergences from refactor-attempt-0

| Decision                 | Choice                              | Why                                                                                                                                                                                                                                     |
| ------------------------ | ----------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ground threshold         | `cos(PI/4)` (true 45°, 0.7071)      | Fixes the prerefactor unit error (bare `PI/4` = ~38°, not 45°). r-a-0's spec said PI/4 but meant 45°; its code used a bare `0.707` literal. `cos(PI/4)` is the minimal honest correction and self-documents. Contract updated to match. |
| Public move method       | `move(delta)`                       | Contract. r-a-0 used `tick`.                                                                                                                                                                                                            |
| Portal finder visibility | private `_find_portal_at_collision` | Module depth — no external caller in either source.                                                                                                                                                                                     |
| Traveler detection       | group-only                          | Contract: "detection by group not `is` type." Drops r-a-0's redundant `is CharacterBody2D` guard.                                                                                                                                       |
| Magic numbers            | named consts                        | r-a-0's pattern; obeys no-magic-numbers rule.                                                                                                                                                                                           |

---

## Notes carried forward

1. **`is_grounded` one-frame-stale ordering (preserve exactly).** The component only updates
   `is_grounded` inside `move()`, which the host calls _last_ in its `_physics_process`. The
   host reads `is_grounded` at the _top_ of the same frame for gravity/jump decisions, so it
   sees the previous frame's result. This one-tick lag is the established jump/gravity feel.
   The component cannot enforce this — Task C's player must keep read-top / `move()`-bottom
   ordering.

2. **`body.velocity` in `_teleport` is CharacterBody2D-only** (`RigidBody2D` uses
   `linear_velocity`). Dropping the type guard is correct; no RigidBody2D handling is added —
   the only in-scope traveler is a `CharacterBody2D`. Physics-box teleport is deferred
   (contract + r-a-0 spec both defer it).

---

## Out of scope

- `Portal.tscn` — user creates in the Godot editor: Area2D (`collision_mask = 12`) +
  AnimatedSprite2D (palette `ShaderMaterial`, `palette_tex` = `palettes.png`) +
  CollisionShape2D (~8x26).
- Portal gun, `gun_pivot.gd`, portal arm — Task C / later.
- RigidBody2D teleportation — deferred until a physics-box entity exists.

---

## Validates

The host-agnostic bet: Phase 2 attaches `PortalMovementComponent` to an enemy unchanged.
