# Phase 1 Task D — Level Management Design

Date: 2026-06-03
Scope: Load a level from an array, reset on death, kill on out-of-bounds. Three scripts in
`world/`. No persistence. No scenes (user builds `Level*.tscn`).

Behavior source: prerefactor `level_controller.gd`, `killzone.gd`.
Reference implementation: refactor-attempt-0 `level_controller.gd`, `world/levels/level_base.gd`,
`world/world_bounds.gd`.

---

## Goal

A `LevelController` that instantiates the current level from a `PackedScene` array, positions
the player at the level's spawn, resets the level on `player.died`, and cycles levels via the
`inc_lvl_test` debug key. Levels are self-contained `LevelBase` scenes; out-of-bounds death is
owned by a per-level `WorldBounds` Area2D. No save/load (deferred to Phase 4).

---

## `world/levels/level_base.gd`

`class_name LevelBase extends Node2D`

The boundary contract every concrete level satisfies. Identical to refactor-attempt-0.

### Interface

- `@export var player_spawn: Node2D` — where `LevelController` places the player. Concrete
  `Level*.tscn` extend `LevelBase` and wire this in the Inspector.

No `signal level_completed` — deferred. Phase 1 has no level-completion trigger (level cycling
is the `inc_lvl_test` debug key, not a completion mechanic). Add the signal when a real
completion mechanic exists.

---

## `world/levels/world_bounds.gd`

`class_name WorldBounds extends Area2D`

A per-level kill volume below the playable area. Self-contained: no player reference, frees
automatically with its level (Scene Rule 4).

### Behavior

```gdscript
func _on_body_entered(body: Node2D) -> void:
    if body is Player:
        body.call_deferred("die")
```

- `body_entered → _on_body_entered` is wired in the editor (`.tscn`), per Event Rule 6 — both
  the Area2D and its handler exist at edit time.
- `is Player` guard, then `call_deferred("die")`: death is triggered from a physics callback,
  so the actual `die()` (which disables processing) must be deferred to avoid mutating the
  scene tree mid-physics-step (Event Rule 3).

---

## `world/level_controller.gd`

`class_name LevelController extends Node`

Owns the level lifecycle. Structured on refactor-attempt-0 (0-based index, no `-1` offset).

### Interface

- `@export var levels: Array[PackedScene]` — the ordered level list.
- `@export var player: Player` — the player to position and reset (sibling in `Main.tscn`).

### State

- `var _curr_lvl: int = 0`
- `var _insted_lvl: LevelBase`
- `var _player_spawn: Node2D`

### Behavior

- `_ready()`:
  1. `player.died.connect(_reset_lvl, CONNECT_DEFERRED)` — `died` is emitted from a deferred
     death path; the connection stays deferred per Event Rule 3.
  2. `_create_lvl(_curr_lvl)`.
  3. `player.global_position = _player_spawn.global_position` (initial placement; reset has its
     own placement path).

- `_input(event)`: on `inc_lvl_test`, `_curr_lvl = mini(_curr_lvl + 1, levels.size() - 1)` then
  `_reset_lvl()` (reloads immediately — deliberate).

- `_create_lvl(n)`:
  1. `_insted_lvl = levels[n].instantiate() as LevelBase`.
  2. `add_child(_insted_lvl)`.
  3. `_player_spawn = _insted_lvl.player_spawn` (Scene Rule 1 — read the export, never
     `get_node("PlayerSpawn")`).
  4. `player.set_portal_container(_insted_lvl)` — placed portals become children of the level,
     so they free automatically when the level frees (Scene Rule 4).

- `_remove_lvl()`: `_insted_lvl.queue_free()`. Nothing else — the portal group-cleanup loop is
  dropped (portals are level children).

- `_reset_lvl()`: free old → create new → reposition → clear portals, in this order:
  1. `_remove_lvl()`
  2. `_create_lvl(_curr_lvl)`
  3. `player.respawn(_player_spawn.global_position)` — after `_create_lvl` so it uses the new
     level's spawn (deliberate ordering).
  4. `player.reset_portals()` — clears `GunPivot`'s slot tracking and linked-portal state. The
     old level's portal children are already freeing from step 1; `GunPivot.reset()` guards
     each slot, so re-freeing freed instances is a no-op.

---

## Resolved divergences

| Decision | Choice | Why |
| --- | --- | --- |
| Level index base | 0-based (`levels[n]`, `_curr_lvl := 0`) | refactor-attempt-0 structural model; drops prerefactor's `lvl_num - 1` offset. |
| `WorldBounds` death | `is Player` guard + `call_deferred("die")` | prerefactor's safer behavior; r-a-0's typed-param `body.die()` lacks the deferral and the guard. Contract mandates this form. |
| `level_completed` signal | deferred | Nothing in Phase 1 emits or connects it; no-speculative-features. |
| Portal cleanup on reset | none in `LevelController` | Portals are level children (Scene Rule 4) + `player.reset_portals()` resets `GunPivot`. Drops the prerefactor/r-a-0 `"portals"` group loop. |
| Player placement on reset | `respawn` after `_create_lvl` | Uses the newly instanced level's spawn, not the freed level's. |

---

## Dropped from prerefactor

- `add_to_group("persist")`, `Debug.Save.load_current_slot()`, `save_to_state` /
  `load_from_state`, the `save_test` input branch — all Phase 4.
- `@onready var world_bound`/`killzone` + `_world_bound_spawn` + the
  `world_bound.global_position = _world_bound_spawn.global_position` reposition hack — bounds
  now live per-level as `WorldBounds` children, no repositioning.
- `_insted_lvl.get_node("PlayerSpawn")` / `get_node("WorldBoundSpawn")` — replaced by the
  `LevelBase.player_spawn` export (Scene Rule 1).
- The `get_tree().get_nodes_in_group("portals")` free loop in `_remove_lvl` — portals free with
  the level.

---

## Out of scope (user builds in the Godot editor)

- `Level*.tscn` extending `LevelBase`: `PlayerSpawn` Node2D (→ `player_spawn`), `WorldBounds`
  (`collision_mask = 12`) below the level, portal-surface StaticBodies on layer 1.
- `Main.tscn` wiring (`LevelController.player`, `.levels`) — Task E.
- Save/load, multiple shipped levels — later phases.

---

## Verification

Parse-check (no scenes exist yet for runtime):

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"
```

Clean = no output. Full runtime verification happens at the Phase 1 checkpoint (end of Task E,
when `Main.tscn` exists).
