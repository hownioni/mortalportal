# LevelController Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Port LevelController as a minimal level orchestrator that loads levels, spawns the player, and resets on death.

**Architecture:** Two new scripts (`world_bounds.gd`, `level_controller.gd`). LevelController holds an `@export var player: Player` reference and an `@export var levels: Array[PackedScene]`, connects to `player.died` to drive the reset loop. WorldBounds lives in each level scene and calls `body.die()` on contact with the player group. Scene files (`level_base.tscn`, `level_controller.tscn`) are created by the user in the Godot editor after the scripts are written.

**Tech Stack:** Godot 4.x, GDScript

---

## File Map

| Action | Path | Responsibility |
|--------|------|----------------|
| Create | `world/world_bounds.gd` | Kills player on void contact |
| Create | `world/level_controller.gd` | Instantiates levels, manages spawn and reset |
| User (editor) | `world/levels/level_base.tscn` | Base scene all levels inherit from |
| User (editor) | `world/levels/level_0.tscn` | First level (inherits level_base) |
| User (editor) | `world/level_controller.tscn` | Scene root wiring player + levels exports |

---

## Task 1: WorldBounds script

**Files:**
- Create: `world/world_bounds.gd`

- [ ] **Step 1: Create the script**

```gdscript
class_name WorldBounds extends Area2D

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		body.die()
```

Save to `world/world_bounds.gd`.

- [ ] **Step 2: Validate — no parse errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1
```

Expected: only `"Can't run project: no main scene defined"`. No `ERROR` or `SCRIPT ERROR` lines.

- [ ] **Step 3: Commit**

```bash
git add world/world_bounds.gd
git commit -m "Add WorldBounds script"
```

---

## Task 2: LevelController script

**Files:**
- Create: `world/level_controller.gd`

- [ ] **Step 1: Create the script**

```gdscript
class_name LevelController extends Node

@export var player: Player
@export var levels: Array[PackedScene]

var _curr_lvl: int = 0
var _insted_lvl: Node
var _player_spawn: Node2D


func _ready() -> void:
	player.died.connect(_reset_lvl)
	_create_lvl(0)
	player.global_position = _player_spawn.global_position


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("inc_lvl_test"):
		_curr_lvl = mini(_curr_lvl + 1, levels.size() - 1)
		_reset_lvl()


func _create_lvl(lvl_num: int) -> void:
	_insted_lvl = levels[lvl_num].instantiate()
	add_child(_insted_lvl)
	_player_spawn = _insted_lvl.get_node("PlayerSpawn")


func _remove_lvl() -> void:
	_insted_lvl.queue_free()
	for portal in get_tree().get_nodes_in_group("portals"):
		portal.queue_free()


func _reset_lvl() -> void:
	_remove_lvl()
	_create_lvl(_curr_lvl)
	player.respawn(_player_spawn.global_position)
```

Save to `world/level_controller.gd`.

- [ ] **Step 2: Validate — no parse errors**

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --quit 2>&1
```

Expected: only `"Can't run project: no main scene defined"`. No `ERROR` or `SCRIPT ERROR` lines.

- [ ] **Step 3: Commit**

```bash
git add world/level_controller.gd
git commit -m "Add LevelController script"
```

---

## Task 3: Scene setup (user, in Godot editor)

These cannot be automated — the user creates them in the editor.

**Step 1: Create `world/levels/level_base.tscn`**

Scene tree:
```
Node2D                          (root, no script)
├── TileMapLayer
├── PlayerSpawn                 (Node2D)
└── WorldBounds                 (Area2D, script = world/world_bounds.gd)
    └── CollisionShape2D        (large rectangle covering the void below/around the level)
```

In the WorldBounds node: connect the `body_entered` signal to `_on_body_entered` (on the WorldBounds node itself).

**Step 2: Create `world/levels/level_0.tscn`**

In the FileSystem dock: right-click `level_base.tscn` → "New Inherited Scene". Save as `world/levels/level_0.tscn`. Place tiles in TileMapLayer. Resize `WorldBounds/CollisionShape2D` to cover the area below the floor.

**Step 3: Create `world/level_controller.tscn`**

Scene tree:
```
Node                            (root, script = world/level_controller.gd)
└── (Player scene is a separate scene — wire via @export, not as a child here)
```

The LevelController scene does not own the Player node. In whatever root game scene you use, add both the Player scene and LevelController as children, then set the `player` export on LevelController to point to the Player node, and populate the `levels` array with `level_0.tscn` (and others as they are created).

**Step 4: Set the main scene**

In Project Settings → Application → Run → Main Scene, point to your root game scene (the one containing both Player and LevelController). This clears the `"no main scene"` headless warning.

---

## Manual verification

Once scenes are wired:

1. Run the project — player should appear at `PlayerSpawn` position.
2. Walk the player off the level edge into `WorldBounds` — player should disappear and reappear at spawn (reset loop working).
3. Press `Ctrl+X` (`inc_lvl_test`) — level should reload (or advance if `levels` array has more than one entry).
4. Touch an enemy — player should die and reset the same way as falling out of bounds.
