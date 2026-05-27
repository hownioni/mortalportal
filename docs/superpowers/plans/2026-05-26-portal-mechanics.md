# Portal Mechanics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement portal-aware movement and teleportation as two composable scripts in `portal/`.

**Architecture:** `PortalMovementComponent` is a `Node` child that drives a `CharacterBody2D` via `move_and_collide`, intercepting portal collisions before applying the slide response. `Portal` is an `Area2D` that teleports any body in the `"portal_travelers"` group. Opt-in to teleportation is handled by group membership; `PortalMovementComponent` registers its body into that group automatically.

**Tech Stack:** Godot 4.x, GDScript, no external libraries.

**Spec:** `docs/superpowers/specs/2026-05-26-portal-mechanics-design.md`

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `portal/portal_movement_component.gd` | Portal-aware `move_and_collide` wrapper for `CharacterBody2D` |
| Create | `portal/portal.gd` | Area2D teleporter for any `"portal_travelers"` body |
| Modify | `project.godot` | Register `"portal_travelers"` as a global group |

---

## Task 1: Register the `portal_travelers` global group

**Files:**
- Modify: `project.godot`

The `portals` group is already registered. Add `portal_travelers` so the editor knows about it.

- [ ] **Step 1: Add group to project.godot**

Open `project.godot` and find the `[global_group]` section. Add one line:

```ini
[global_group]

portals=""
portal_travelers=""
```

- [ ] **Step 2: Verify**

Open the project in the Godot editor (or run `godot --headless --path . --quit`). No errors expected. The group will appear in Project > Project Settings > Groups.

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "Register portal_travelers global group"
```

---

## Task 2: Create `PortalMovementComponent`

**Files:**
- Create: `portal/portal_movement_component.gd`

This component replaces the old `PortalEntity` base class. It is a `Node` child added to any `CharacterBody2D` that needs portal-aware movement.

- [ ] **Step 1: Create the file**

`portal/portal_movement_component.gd`:

```gdscript
class_name PortalMovementComponent extends Node

const _DEG_45 := PI / 4

@export var body: CharacterBody2D

var is_grounded := false


func _ready() -> void:
	if body:
		body.add_to_group("portal_travelers")


func tick(delta: float) -> void:
	is_grounded = false
	var collision := body.move_and_collide(body.velocity * delta)
	if not collision:
		return
	if collision.get_normal().dot(Vector2.UP) > _DEG_45:
		is_grounded = true
	if _find_portal_at_collision(collision):
		return
	body.velocity = body.velocity.slide(collision.get_normal())
	var remainder: Vector2 = collision.get_remainder()
	var slide_collision := body.move_and_collide(remainder.slide(collision.get_normal()))
	if slide_collision and slide_collision.get_normal().dot(Vector2.UP) > _DEG_45:
		is_grounded = true


func _find_portal_at_collision(collision: KinematicCollision2D) -> Area2D:
	var space_state := body.get_world_2d().direct_space_state
	var query := PhysicsPointQueryParameters2D.new()
	query.position = collision.get_position() + collision.get_normal() * -2.0
	query.collide_with_areas = true
	query.collide_with_bodies = false
	for result in space_state.intersect_point(query):
		if result.collider.is_in_group("portals"):
			return result.collider
	return null
```

- [ ] **Step 2: Verify parse**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -i error
```

Expected: no output (no errors). If errors appear, they will name the file and line.

- [ ] **Step 3: Commit**

```bash
git add portal/portal_movement_component.gd
git commit -m "Add PortalMovementComponent"
```

---

## Task 3: Create `Portal`

**Files:**
- Create: `portal/portal.gd`

The `Area2D` teleporter. Checks `"portal_travelers"` group as the opt-in. For Part 1, all portal travelers are `CharacterBody2D` — the type check guards against anything else that might accidentally join the group.

- [ ] **Step 1: Create the file**

`portal/portal.gd`:

```gdscript
class_name Portal extends Area2D

const EXIT_BUFFER := 40

@export var linked_portal: Area2D


func _ready() -> void:
	add_to_group("portals")


func _physics_process(_delta: float) -> void:
	for body in get_overlapping_bodies():
		if body is CharacterBody2D and body.is_in_group("portal_travelers"):
			_teleport(body)


func _teleport(body: CharacterBody2D) -> void:
	if not linked_portal:
		return
	var current_speed: float = minf(20000.0, body.velocity.length() * 1.1)
	var push_direction := Vector2.RIGHT.rotated(linked_portal.global_rotation)
	body.velocity = push_direction * current_speed
	body.global_position = linked_portal.global_position + push_direction * EXIT_BUFFER
```

- [ ] **Step 2: Verify parse**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -i error
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add portal/portal.gd
git commit -m "Add Portal teleporter"
```

---

## Notes for next session

- Neither script has a `.tscn` scene yet. Create them in the Godot editor:
  - `portal/portal_1.tscn` — `Area2D` root with `Portal` script, `CollisionShape2D` child (capsule rotated 90°), `AnimatedSprite2D` child using `portal/assets/portal_1.png`
  - `portal/portal_2.tscn` — same structure, `portal/assets/portal_2.png`
  - Set `linked_portal` exports in each scene's sub-resource or leave for the level scene to wire
- The player scene (not yet built) will add `PortalMovementComponent` as a child, set `body` export to the `CharacterBody2D` root, and call `portal_movement.tick(delta)` from `_physics_process` instead of `move_and_slide`
