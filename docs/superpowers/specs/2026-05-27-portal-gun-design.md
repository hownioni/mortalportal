# Portal Gun — Design Spec
Date: 2026-05-27
Scope: Part 2 — portal gun (follows portal-mechanics Part 1)

---

## What we're building

Two new scripts:

- `portal/gun_pivot.gd` — logic node, child of Player inside SubViewport
- `characters/player/portal_arm.gd` — visual sync node in the main scene (HighRes world)

No changes to `portal.gd`, `portal_movement_component.gd`, or `player.gd`.

---

## Architecture

### GunPivot

`class_name GunPivot extends Node2D`
Location: `portal/gun_pivot.gd`
Scene placement: child of Player inside the SubViewport. No sprite.

**Interface:**
- `@export var portal_scene: PackedScene` — the Portal scene to instance
- `@export var portal_container: Node` — node to parent spawned portals into (must be in the SubViewport world; set to the level root or a dedicated portals container in the editor)
- `@export var portal_surface_mask: int` — physics layer mask for portal-able surfaces

**Constants:**
- `SHOOT_RANGE: float` — max raycast distance
- `SURFACE_OFFSET: float` — small offset to place portal slightly off the wall

**State:**
- `_portal_a: Portal` — currently placed A portal (left click); null if not yet placed
- `_portal_b: Portal` — currently placed B portal (right click); null if not yet placed

**Behavior:**

`_physics_process`:
- Rotates to face mouse: `rotation = (get_global_mouse_position() - global_position).angle()`
- Checks for `MOUSE_BUTTON_LEFT` and `MOUSE_BUTTON_RIGHT` press events via `Input.is_action_just_pressed`

`_fire(slot: int)`:
- Casts a ray from `global_position` in `Vector2.RIGHT.rotated(rotation)` direction, distance `SHOOT_RANGE`, collision mask = `portal_surface_mask`
- On miss: no-op
- On hit: queue_free the existing portal in that slot (if any), unlink the other portal, spawn a new Portal instance at `hit_position + hit_normal * SURFACE_OFFSET`, set `portal.global_rotation = hit_normal.angle()`, add it as a child of `portal_container`
- After placement: if both slots are filled, link bidirectionally (`_portal_a.linked_portal = _portal_b` and `_portal_b.linked_portal = _portal_a`)

**Portal orientation:**
The existing teleport math uses `Vector2.RIGHT.rotated(portal.global_rotation)` as the exit direction. Setting `portal.global_rotation = hit_normal.angle()` makes the exit direction equal to the surface normal — i.e. the body exits perpendicular to the surface, pointing into the room. This is correct for walls, floors, and ceilings.

**Linking invariant:**
Both portals are linked or neither is. When a portal is replaced or freed, its partner's `linked_portal` is set to null until the new one is placed.

---

### PortalArm

`class_name PortalArm extends Node2D`
Location: `characters/player/portal_arm.gd`
Scene placement: main scene (HighRes world), alongside the SubViewportContainer and HighResCamera.

**Interface:**
- `@export var player: Player` — reference to Player node inside SubViewport
- `@export var gun_pivot: GunPivot` — reference to GunPivot inside SubViewport

**Children:**
- `_sprite: Sprite2D` (or `AnimatedSprite2D`) — the arm/gun art (`portal_arm.png`)

**Behavior:**

`_process`:
- `global_position = player.global_position`
- `rotation = gun_pivot.rotation`
- `_sprite.flip_v = gun_pivot.rotation > PI / 2 or gun_pivot.rotation < -PI / 2` — flips arm vertically when aiming left so it renders on the correct side of the body

No physics, no input, no game logic.

---

## Portal-able surfaces

Portal-able surfaces use a dedicated physics collision layer (distinct from the player's layer 3 and the default solid layer 1). The exact layer number is confirmed during implementation from the project's physics layer assignments. Surfaces that accept portals are placed on both their normal solid layer and this portal-surface layer.

The raycast in GunPivot checks only the portal-surface layer via `portal_surface_mask`. This prevents portals from being placed on enemy bodies, hazards, or other non-wall geometry.

---

## What is NOT in scope

- Portal arm animations (shoot, idle) — deferred until art is ready
- Portal placement sound/VFX — deferred
- RigidBody2D boxes being teleported — deferred (tracked in portal-mechanics spec)
- Max portal range visual indicator — deferred
