# Portal Gun Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a portal gun that lets the player shoot two portals (left/right click) onto explicitly marked surfaces via raycasts, with a high-res arm sprite that mirrors the gun direction.

**Architecture:** `GunPivot` (Node2D, child of Player inside SubViewport) handles aim rotation, raycasting, and portal spawning/linking. `PortalArm` (Node2D in the main scene) mirrors `player.global_position` and `gun_pivot.rotation` for high-res rendering. Portal-able surfaces use a dedicated physics layer (layer 5, PortalSurface, bitmask `16`).

**Tech Stack:** GDScript 4, Godot 4 physics (`PhysicsRayQueryParameters2D`, `direct_space_state`), existing `Portal` class (`portal/portal.gd`).

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `project.godot` | Modify | Add layer 5 "PortalSurface" |
| `portal/gun_pivot.gd` | Create | Aim rotation, raycast, portal spawning, bidirectional linking |
| `characters/player/portal_arm.gd` | Create | Mirror player position + gun rotation for the HighRes arm sprite |

Scene wiring (done by user in the Godot editor — see Task 4):
- `GunPivot` Node2D added to `characters/player/player.tscn` as a child of Player
- `PortalArm` Node2D added to `world/main.tscn` as a sibling of SubViewportContainer

---

### Task 1: Add PortalSurface physics layer

**Files:**
- Modify: `project.godot`

- [ ] **Step 1: Add layer 5 to the `[layer_names]` section**

Open `project.godot`. Find the `[layer_names]` block and append the new entry:

```ini
[layer_names]

2d_physics/layer_1="Walls"
2d_physics/layer_2="Damage"
2d_physics/layer_3="Player"
2d_physics/layer_4="PortalEntities"
2d_physics/layer_5="PortalSurface"
```

Layer 5 bitmask value = `2^(5-1)` = `16`. The GunPivot raycast will use `collision_mask = 16` to detect only portal-able surfaces.

- [ ] **Step 2: Verify no parse errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error"
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add project.godot
git commit -m "Add PortalSurface physics layer (layer 5, mask 16)"
```

---

### Task 2: Implement GunPivot

**Files:**
- Create: `portal/gun_pivot.gd`

- [ ] **Step 1: Create `portal/gun_pivot.gd`**

```gdscript
class_name GunPivot extends Node2D

const SHOOT_RANGE: float = 1000.0
const SURFACE_OFFSET: float = 2.0

@export var portal_scene: PackedScene
@export var portal_container: Node
@export var portal_surface_mask: int = 16

var _portal_a: Portal
var _portal_b: Portal


func _physics_process(_delta: float) -> void:
	rotation = (get_global_mouse_position() - global_position).angle()
	if Input.is_action_just_pressed("fire_one"):
		_fire(0)
	elif Input.is_action_just_pressed("fire_two"):
		_fire(1)


func _fire(slot: int) -> void:
	var space_state := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.new()
	query.from = global_position
	query.to = global_position + Vector2.RIGHT.rotated(rotation) * SHOOT_RANGE
	query.collision_mask = portal_surface_mask
	var result := space_state.intersect_ray(query)
	if result.is_empty():
		return
	_place_portal(slot, result["position"], result["normal"])


func _place_portal(slot: int, hit_position: Vector2, hit_normal: Vector2) -> void:
	if slot == 0:
		if _portal_a:
			_portal_a.queue_free()
			if _portal_b:
				_portal_b.linked_portal = null
		_portal_a = portal_scene.instantiate() as Portal
		_portal_a.palette_index = 0
		portal_container.add_child(_portal_a)
		_portal_a.global_position = hit_position + hit_normal * SURFACE_OFFSET
		_portal_a.global_rotation = hit_normal.angle()
		if _portal_b:
			_portal_a.linked_portal = _portal_b
			_portal_b.linked_portal = _portal_a
	else:
		if _portal_b:
			_portal_b.queue_free()
			if _portal_a:
				_portal_a.linked_portal = null
		_portal_b = portal_scene.instantiate() as Portal
		_portal_b.palette_index = 1
		portal_container.add_child(_portal_b)
		_portal_b.global_position = hit_position + hit_normal * SURFACE_OFFSET
		_portal_b.global_rotation = hit_normal.angle()
		if _portal_a:
			_portal_b.linked_portal = _portal_a
			_portal_a.linked_portal = _portal_b
```

Design notes:
- `palette_index` is set **before** `add_child` so it is available when `Portal._ready()` runs and configures the shader.
- `portal.global_rotation = hit_normal.angle()` makes the exit direction equal to the surface normal: the existing teleport math `Vector2.RIGHT.rotated(portal.global_rotation)` = `hit_normal`, so the player exits perpendicular to the surface pointing into the room.
- Raycast uses `collision_mask = portal_surface_mask` (default `16`), so it only hits layer 5 surfaces — never the player (layer 3) or portals (layer 4).
- Unlink before replacing: if a portal is replaced, its partner's `linked_portal` is set to null first so the partner never points to a freed node.

- [ ] **Step 2: Verify no parse errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error"
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add portal/gun_pivot.gd
git commit -m "Add GunPivot script"
```

---

### Task 3: Implement PortalArm

**Files:**
- Create: `characters/player/portal_arm.gd`

- [ ] **Step 1: Create `characters/player/portal_arm.gd`**

```gdscript
class_name PortalArm extends Node2D

@export var player: Player
@export var gun_pivot: GunPivot

@onready var _sprite: Sprite2D = $Sprite2D


func _process(_delta: float) -> void:
	global_position = player.global_position
	rotation = gun_pivot.rotation
	_sprite.flip_v = rotation > PI / 2.0 or rotation < -PI / 2.0
```

Design note: `flip_v` mirrors the arm vertically when aiming left (rotation past ±90°), so the arm draws on the correct side of the body regardless of aim direction. This matches the same flip condition used by `player.gd` to flip `_sprite.flip_h`.

- [ ] **Step 2: Verify no parse errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1 | grep -E "ERROR|SCRIPT ERROR|Parse Error"
```

Expected: no output.

- [ ] **Step 3: Commit**

```bash
git add characters/player/portal_arm.gd
git commit -m "Add PortalArm script"
```

---

### Task 4: Editor setup

All steps in this task are done in the Godot editor. No code is written.

- [ ] **Step 1: Add GunPivot to player.tscn**

Open `characters/player/player.tscn`:
1. Add a child `Node2D` to the root Player node. Name it `GunPivot`.
2. Attach `portal/gun_pivot.gd` as its script.
3. In the Inspector, set `Portal Scene` to `portal/portal.tscn`.
4. Leave `Portal Container` blank for now — set it in the next step.

- [ ] **Step 2: Add PortalArm to main.tscn**

Open `world/main.tscn`:
1. Add a child `Node2D` to Main (same level as SubViewportContainer and HighResCamera). Name it `PortalArm`.
2. Attach `characters/player/portal_arm.gd` as its script.
3. Add a `Sprite2D` child to PortalArm. Set its `Texture` to `characters/player/assets/portal_arm.png`.
4. In PortalArm's Inspector:
   - `Player`: drag `SubViewportContainer/SubViewport/Player`
   - `Gun Pivot`: drag `SubViewportContainer/SubViewport/Player/GunPivot`

- [ ] **Step 3: Wire portal_container on GunPivot**

Still in `world/main.tscn`, select `SubViewportContainer/SubViewport/Player/GunPivot` and set:
- `Portal Container`: drag the `SubViewportContainer/SubViewport` node

Portals spawned by the gun will be children of the SubViewport root — in the correct physics world, not attached to the player, so they stay in place when the player moves.

- [ ] **Step 4: Mark portal-able surfaces in the TileSet**

Open the TileSet resource used by the level TileMap (found in `world/levels/level_0.tscn`):
1. In the TileSet inspector, click **Add Element** under Physics Layers. Set the new layer's `Collision Layer` to `16` (PortalSurface, layer 5).
2. In the tile editor, for each tile that should accept portals, select it and draw a collision polygon on the PortalSurface physics layer.
3. Tiles with no polygon on that layer will not be portal-able — the raycast will pass through them.

- [ ] **Step 5: Verify in-game**

Run the project and check:
- The arm sprite rotates smoothly to follow the mouse.
- The arm sprite flips vertically when aiming left (past 90° from center).
- Left click on a marked wall places a portal (palette 0 color).
- Right click on a marked wall places a portal (palette 1 color).
- A second left/right click replaces the existing portal of that color; the surviving portal becomes unlinked until the pair is re-established.
- With both portals placed, walking into one teleports the player out of the other.
- Clicking on an unmarked surface does nothing.
