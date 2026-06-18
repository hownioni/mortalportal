# Phase 1 Task D — Level Management Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement level lifecycle management — `LevelBase` (boundary contract), `WorldBounds` (per-level kill volume), and `LevelController` (loads/resets/cycles levels) — replacing the prerefactor `level_controller.gd` + `killzone.gd` with no persistence.

**Architecture:** Three scripts in `world/`. `LevelController` instantiates the current level from a `PackedScene` array, places the player at the level's `player_spawn`, and resets on `player.died`. Placed portals become children of the instanced level so they free with it. Full design: `docs/specs/2026-06-03-phase-1-level.md`.

**Tech Stack:** Godot 4.6, GDScript, GL Compatibility renderer, Jolt Physics.

---

## Verification model (read first)

This project has **no test framework** (GUT is not installed). Level management cannot be
unit-tested in isolation: it needs the Player and assembled scenes. So Task D verification is:

1. **Project-wide parse/type check** — `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`, expect **no output**.
   `--import` registers all `class_name` globals (needed because `LevelController` references
   the cross-file types `Player` and `LevelBase`). `--check-only --script` does NOT register a
   newly-added `class_name` and gives false "Could not find type" errors — do not use it for
   the new types here. Exit code is unreliable (Godot can return non-zero from the VCS plugin
   in headless mode); **judge only by grep output**.
2. **Functional playtest** — deferred to the Phase 1 checkpoint (end of Task E, when `Main.tscn`
   exists and wires `LevelController.player` / `.levels`). Death/reset, out-of-bounds kill, and
   `Ctrl+X` level cycling are verified there. Noted explicitly; do not fake it here.

**Commits:** This project's owner commits only on request. Each task ends with a commit step,
but at execution time confirm before running `git commit`.

---

## File structure

- Create: `world/levels/level_base.gd` — boundary contract (`class_name LevelBase`).
- Create: `world/levels/world_bounds.gd` — per-level kill volume (`class_name WorldBounds`).
- Create: `world/level_controller.gd` — level lifecycle owner (`class_name LevelController`).
- Create (user, in editor): `world/levels/level_1.tscn` — first concrete level extending `LevelBase`.

`Main.tscn` and the `LevelController` wiring are Task E, not this plan.

---

## Task 1: LevelBase

The boundary contract every concrete level satisfies. Identical to refactor-attempt-0. No
`level_completed` signal (deferred — nothing in Phase 1 emits or connects it).

**Files:**
- Create: `world/levels/level_base.gd`

- [ ] **Step 1: Create the folder**

```bash
mkdir -p /home/migu/repos/GitHub/mortalportal/world/levels
```

- [ ] **Step 2: Write the script**

```gdscript
class_name LevelBase extends Node2D

@export var player_spawn: Node2D
```

- [ ] **Step 3: Parse/type check**

Run: `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output** (grep prints nothing → no parse/type errors). Do not gate on the
shell exit code — judge by grep output only.

- [ ] **Step 4: Commit**

```bash
git add world/levels/level_base.gd
git commit -m "Phase 1 Task D: LevelBase contract"
```

---

## Task 2: WorldBounds

A per-level kill volume below the playable area. Self-contained: no player reference, frees
with its level. The `is Player` guard + `call_deferred("die")` is the safer prerefactor
behavior (death is triggered from a physics callback). The `body_entered` signal is wired to
`_on_body_entered` in the editor (Task 4), per Event Rule 6 — both exist at edit time.

**Files:**
- Create: `world/levels/world_bounds.gd`

- [ ] **Step 1: Write the script**

```gdscript
class_name WorldBounds extends Area2D


func _on_body_entered(body: Node2D) -> void:
	if body is Player:
		body.call_deferred("die")
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output**. Judge by grep output only.

- [ ] **Step 3: Commit**

```bash
git add world/levels/world_bounds.gd
git commit -m "Phase 1 Task D: WorldBounds kill volume"
```

---

## Task 3: LevelController

Owns the level lifecycle. Structured on refactor-attempt-0 (0-based index, no `-1` offset).
Connects `player.died` deferred, places the player, sets the level as the portal container so
placed portals free with the level, and resets/cycles. All prerefactor `Debug.Save` /
`persist` / `save_test` / `get_node` / world-bound-reposition code is dropped (see spec).

**Files:**
- Create: `world/level_controller.gd`

- [ ] **Step 1: Write the script**

```gdscript
class_name LevelController extends Node

@export var levels: Array[PackedScene]
@export var player: Player

var _curr_lvl: int = 0
var _insted_lvl: LevelBase
var _player_spawn: Node2D


func _ready() -> void:
	player.died.connect(_reset_lvl, CONNECT_DEFERRED)
	_create_lvl(_curr_lvl)
	player.global_position = _player_spawn.global_position


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inc_lvl_test"):
		_curr_lvl = mini(_curr_lvl + 1, levels.size() - 1)
		_reset_lvl()


func _create_lvl(lvl_num: int) -> void:
	_insted_lvl = levels[lvl_num].instantiate() as LevelBase
	add_child(_insted_lvl)
	_player_spawn = _insted_lvl.player_spawn
	player.set_portal_container(_insted_lvl)


func _remove_lvl() -> void:
	_insted_lvl.queue_free()


func _reset_lvl() -> void:
	_remove_lvl()
	_create_lvl(_curr_lvl)
	player.respawn(_player_spawn.global_position)
	player.reset_portals()
```

- [ ] **Step 2: Parse/type check**

Run: `godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"`
Expected: **no output**. This is the task where the check matters most — `LevelController`
references `Player` and `LevelBase`, so a missed `--import` would give false type errors.
Judge by grep output only.

- [ ] **Step 3: Commit**

```bash
git add world/level_controller.gd
git commit -m "Phase 1 Task D: LevelController lifecycle"
```

---

## Task 4: Assemble `Level1.tscn` (user, in the Godot editor)

Scene creation is the user's responsibility. This is the step-by-step editor guide for the
first concrete level. It extends `LevelBase` and contains the spawn, the kill volume, and at
least one portal-placeable surface so the Phase 1 checkpoint can place portals.

**File:** `world/levels/level_1.tscn`

- [ ] **Step 1: Create the scene root**
  - Scene > New Scene > Other Node > `Node2D`.
  - Attach the **existing** script `res://world/levels/level_base.gd` to the root (do not let
    the editor generate a new one). The root is now a `LevelBase`.
  - Rename the root to `Level1`.
  - Save as `res://world/levels/level_1.tscn`.

- [ ] **Step 2: Add the player spawn**
  - Add child `Node2D`, rename to `PlayerSpawn`.
  - Position it where the player should start (somewhere above the floor).
  - Select the `Level1` root, and in the Inspector set **player_spawn** = the `PlayerSpawn`
    node (drag it into the export slot). This satisfies the `LevelBase` contract.

- [ ] **Step 3: Add a floor / portal-placeable surface**
  - Add child `StaticBody2D`, rename to e.g. `Floor`.
  - **Collision layer:** check **layer 1** (player collision) **and layer 5** (PortalSurface).
    Numeric value **17**. Layer 1 lets the player walk on it (player `collision_mask = 3`);
    layer 5 (value 16) lets the portal gun ray (`PORTAL_SURFACE_MASK = 16`) place portals on
    it. A bare layer 1 would be walkable but **portals could not be placed** — this matches
    r-a-0's `level_0.tscn` floor (`collision_layer = 17`), not the contract's loose "layer 1".
  - **Collision mask:** `0` (a static floor detects nothing).
  - Add a `CollisionShape2D` child with a `RectangleShape2D` sized to the floor.
  - Add walls the same way if desired (same layer 17 so they are portal-placeable).

- [ ] **Step 4: Add the world bounds (kill volume)**
  - Add child `Area2D`, rename to `WorldBounds`.
  - Attach the **existing** script `res://world/levels/world_bounds.gd`.
  - **Collision layer:** `0`. **Collision mask:** check **Player (layer 3)** and
    **PortalEntities (layer 4)**. Numeric value **12** — this is what detects the falling
    player (whose `collision_layer = 12`).
  - Add a `CollisionShape2D` child, a wide `RectangleShape2D`, positioned **below** the floor
    so falling out of the level enters it.
  - **Wire the signal:** select `WorldBounds`, Node panel > Signals > `body_entered` >
    Connect, target the `WorldBounds` node's own `_on_body_entered` method (it already exists
    in the attached script — do not generate a new method). Leave "Deferred" unchecked; the
    script already defers `die()` via `call_deferred`.

- [ ] **Step 5: Save**
  - Save the scene (`Ctrl+S`).

- [ ] **Step 6: Import sanity check**
  - Confirm no script errors on `Level1`, `WorldBounds`, or `Floor`. Confirm the `Level1` root
    shows **player_spawn** populated in the Inspector.

- [ ] **Step 7: Commit (user)**

```bash
git add world/levels/level_1.tscn
git commit -m "Phase 1 Task D: Level1 scene"
```

---

## Done criteria

- `world/levels/level_base.gd`, `world/levels/world_bounds.gd`, `world/level_controller.gd` all
  pass the project-wide `--import` parse check with no `SCRIPT ERROR` / `Parse Error` output.
- `world/levels/level_1.tscn` extends `LevelBase`, wires `player_spawn`, has a portal-placeable
  floor (layer 17), and a `WorldBounds` kill volume (mask 12) below it with `body_entered`
  wired to `_on_body_entered`.
- Functional death/reset, out-of-bounds kill, and level cycling are verified at the Phase 1
  checkpoint (end of Task E), not here — `Main.tscn` and the `LevelController` wiring do not
  exist until Task E. This is expected.
