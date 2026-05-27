# LevelController Design

Date: 2026-05-26
Branch: composition_refactor

## Scope

Port LevelController from the prerefactor as a minimal level orchestrator. Manages level instantiation, player spawning, and death/reset loop. No save system (deferred).

## File layout

```
world/
├── level_controller.gd       (class_name LevelController extends Node)
├── level_controller.tscn     (user creates in editor)
├── world_bounds.gd           (class_name WorldBounds extends Area2D)
└── levels/
    ├── level_base.tscn       (base scene — all levels inherit from this)
    ├── level_0.tscn
    └── level_1.tscn
```

## Level authoring

All levels inherit from `level_base.tscn`. The base scene defines the required structure:

```
Node2D  (level_base.tscn)
├── TileMapLayer
├── PlayerSpawn       (Node2D — marks player spawn position)
└── WorldBounds       (Area2D — large shape covering the void below/around the level)
    └── CollisionShape2D
```

`WorldBounds` has `world_bounds.gd` attached. Its `body_entered` signal is connected to `_on_body_entered` in the base scene. Each inherited level resizes the `CollisionShape2D` to fit its layout.

To create a new level: inherit from `level_base.tscn` in the editor, place tiles and enemies, resize `WorldBounds` to cover the void.

## world_bounds.gd

```gdscript
class_name WorldBounds extends Area2D

func _on_body_entered(body: Node2D) -> void:
    if body.is_in_group("player"):
        body.die()
```

## level_controller.gd

```gdscript
class_name LevelController extends Node

@export var player: Player
@export var levels: Array[PackedScene]

var _curr_lvl: int = 0
var _insted_lvl: Node
var _player_spawn: Node2D
```

### Methods

- `_ready` - connects `player.died` to `_reset_lvl`, calls `_create_lvl(0)`, sets `player.global_position = _player_spawn.global_position`
- `_create_lvl(lvl_num: int)` - instantiates `levels[lvl_num]`, adds as child, caches `PlayerSpawn` node into `_player_spawn`
- `_remove_lvl()` - `queue_free`s the current level instance, clears all nodes in the "portals" group
- `_reset_lvl()` - calls `_remove_lvl`, then `_create_lvl(_curr_lvl)`, then `player.respawn(_player_spawn.global_position)`
- `_input(event)` - `inc_lvl_test` increments `_curr_lvl` (clamped to `levels.size() - 1`), calls `_reset_lvl`

### Level indexing

0-based throughout. `levels[0]` is level 1, files are named `level_0.tscn`, `level_1.tscn`. Any player-facing display of the level number uses `_curr_lvl + 1`.

## Death/reset loop

1. Player contacts an enemy or enters `WorldBounds`
2. `player.die()` is called - hides sprite, disables processing, emits `died`
3. LevelController receives `died`, calls `_reset_lvl`
4. Old level instance and all portals are freed
5. Level is re-instantiated, player is repositioned and re-enabled via `respawn`

## Public interface

LevelController exposes no public methods or signals to other systems. It is wired entirely in the editor: `player` and `levels` set via `@export`.

## Out of scope

- Save/load (`save_to_state`/`load_from_state`) - deferred
- Camera - separate system, not part of this port
- Portal gun - unblocked once this is built
