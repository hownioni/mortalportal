# Portal Mechanics — Design Spec
Date: 2026-05-26
Scope: Part 1 — teleportation mechanics only (no portal gun)

---

## What we're building

Two scripts in `portal/`:

- `portal/portal_movement_component.gd` — a Node component that gives a `CharacterBody2D` portal-aware movement
- `portal/portal.gd` — an Area2D that teleports any body in the `"portal_travelers"` group

---

## Architecture

### PortalMovementComponent

`class_name PortalMovementComponent extends Node`

Follows the composition pattern established in aviones: the entity (player, enemy) is a plain `CharacterBody2D`; portal-aware movement is a child node.

**Interface:**
- `@export var body: CharacterBody2D` — set in editor, the entity this component drives
- `var is_grounded: bool` — read by the owner in `_physics_process`
- `func tick(delta: float) -> void` — called by the owner instead of `move_and_slide`

**Behavior:**
- Calls `body.move_and_collide(body.velocity * delta)`
- On collision: checks the surface normal to set `is_grounded` (normal dot Vector2.UP > PI/4)
- Does a `PhysicsPointQueryParameters2D` point query just inside the collision surface to check if a portal Area2D (group `"portals"`) is present
- If a portal is found: returns early without sliding — the portal's own teleportation will take over
- If no portal: applies standard velocity slide and a second `move_and_collide` on the remainder

**Group side-effect:**
- `_ready()` calls `body.add_to_group("portal_travelers")` — this is the only way a body gets into that group via this component

**Type constraint:** `@export var body: CharacterBody2D` is intentional. `move_and_collide` is a `CharacterBody2D`-only method and does not exist on `RigidBody2D` or `PhysicsBody2D`. A `RigidBody2D` entity (e.g. a physics box) does not need this component — it adds itself to `"portal_travelers"` directly and is teleported by `portal.gd`.

---

### Portal

`class_name Portal extends Area2D`

**Interface:**
- `@export var linked_portal: Area2D` — set in editor to the exit portal

**Behavior:**
- `_ready()`: adds self to group `"portals"`
- `_physics_process`: iterates `get_overlapping_bodies()`; teleports any body that `is_in_group("portal_travelers")`
- Teleportation: caps entry speed at 20000, multiplies by 1.1, pushes the body in the direction the exit portal faces (`Vector2.RIGHT.rotated(linked_portal.global_rotation)`), offsets by `EXIT_BUFFER = 40` px

**RigidBody2D note:** Teleportation sets `body.global_position` and the velocity property directly. This works safely for `CharacterBody2D` (`body.velocity`). For `RigidBody2D` bodies, direct position/velocity writes outside `_integrate_forces` can cause physics jitter — that case is out of scope for Part 1 and will be addressed when a box entity is built.

---

## Opt-in contract

| Want to...                          | Do this                                                              |
|-------------------------------------|----------------------------------------------------------------------|
| Player/enemy with portal movement   | Add `PortalMovementComponent` child, set `body` export, call `tick` |
| Physics box that can be teleported  | `add_to_group("portal_travelers")` in entity's `_ready()`           |
| Non-teleportable body               | Nothing — absence from group = ignored by portals                   |

---

## What is NOT in scope (Part 1)

- Portal gun (`gun_pivot.gd`, portal arm sprite) — deferred until player and LevelController exist
- Portal scenes (`.tscn`) — created in the Godot editor after scripts are written
- RigidBody2D teleportation via `_integrate_forces` — deferred until a physics box entity is built
