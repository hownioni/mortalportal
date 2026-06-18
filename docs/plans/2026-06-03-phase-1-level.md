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

## Task 4: Assemble `level_base.tscn` + `level_1.tscn` (user, in the Godot editor)

Scene creation is the user's responsibility. Uses **scene inheritance** (matches r-a-0):
`level_base.tscn` is the shared template; concrete levels inherit it and override geometry.
The signal wiring and collision masks are set once in the base and inherited by all levels.

**Files:** `world/levels/level_base.tscn`, `world/levels/level_1.tscn`

### Sub-task A: Create `level_base.tscn` (the template)

- [ ] **Step 1: Create the scene root**
  - Scene > New Scene > Other Node > `Node2D`.
  - Attach the **existing** script `res://world/levels/level_base.gd` (do not generate a new one).
  - Rename the root to `LevelBase`.
  - Save as `res://world/levels/level_base.tscn`.

- [ ] **Step 2: Add TileMapLayer**
  - Add child `TileMapLayer`, leave it named `TileMapLayer`.
  - Leave tile set and tile data empty — configured per concrete level.

- [ ] **Step 3: Add PlayerSpawn and wire the export**
  - Add child `Node2D`, rename to `PlayerSpawn`.
  - Select the `LevelBase` root > Inspector > **player_spawn** = drag `PlayerSpawn` in.
    (Position left at origin — each concrete level overrides it.)

- [ ] **Step 4: Add the WorldBounds kill volume**
  - Add child `Area2D`, rename to `WorldBounds`.
  - Attach the **existing** script `res://world/levels/world_bounds.gd`.
  - **Collision layer:** `0`. **Collision mask:** `12` (layers 3+4: Player + PortalEntities).
  - Add a `CollisionShape2D` child — leave the shape **empty** here; sized per concrete level.
  - **Wire the signal:** select `WorldBounds`, Node panel > Signals > `body_entered` > Connect
    to `WorldBounds._on_body_entered` (method already exists — do not generate a new one).
    Leave "Deferred" unchecked; the script defers `die()` via `call_deferred`.

- [ ] **Step 5: Save** (`Ctrl+S`).

### Sub-task B: Create `level_1.tscn` (inheriting from the template)

- [ ] **Step 6: Create inherited scene**
  - Scene > New Inherited Scene > pick `res://world/levels/level_base.tscn`.
  - Rename root to `Level1`.
  - Save as `res://world/levels/level_1.tscn`.

- [ ] **Step 7: Configure the TileMapLayer (floor + walls)**
  - Select the inherited `TileMapLayer`.
  - Assign (or create) a `TileSet` in the Inspector. The TileSet needs two physics layers:
    - Physics layer 0: collision_layer `1`, mask `0` (player walks on it)
    - Physics layer 1: collision_layer `17`, mask `0` (portal gun ray can place portals)
  - Paint the floor and walls using the tile atlas.

- [ ] **Step 8: Position PlayerSpawn**
  - Select `PlayerSpawn`, move it above the floor.

- [ ] **Step 9: Size the WorldBounds kill volume**
  - Select `WorldBounds/CollisionShape2D`, assign a wide `RectangleShape2D` positioned
    **below** the floor so falling players enter it.

- [ ] **Step 10: Save** (`Ctrl+S`).

- [ ] **Step 11: Sanity check**
  - No script errors on `Level1` or `WorldBounds`.
  - `Level1` root shows **player_spawn** populated in Inspector (inherited from base).

- [ ] **Step 12: Commit (user)**

```bash
git add world/levels/level_base.tscn world/levels/level_1.tscn
git commit -m "Phase 1 Task D: LevelBase template + Level1 scene"
```

---

## Done criteria

- `world/levels/level_base.gd`, `world/levels/world_bounds.gd`, `world/level_controller.gd` all
  pass the project-wide `--import` parse check with no `SCRIPT ERROR` / `Parse Error` output.
- `world/levels/level_base.tscn` has `TileMapLayer` + `PlayerSpawn` + `WorldBounds` (mask 12, signal wired).
- `world/levels/level_1.tscn` inherits `level_base.tscn`, positions `PlayerSpawn`, sizes
  `WorldBounds` kill volume below the floor, and has a `TileMapLayer` with a TileSet
  configured for collision_layer 17 (portal-placeable).
- Functional death/reset, out-of-bounds kill, and level cycling are verified at the Phase 1
  checkpoint (end of Task E), not here — `Main.tscn` and the `LevelController` wiring do not
  exist until Task E. This is expected.
