# Phase 1 — Core Gameplay Slice: Task Contract

**What this is:** The ordered task index for Phase 1, decomposed into 5 sub-system tasks.
Each task is handled in its own session running the full cycle — **brainstorming (mini-spec)
→ writing-plans (mini-plan) → implement** — so design happens per task, not up front. This
document is the sequencing + interface contract those sessions share; it deliberately
contains no implementation code.

**Goal of Phase 1:** A single runnable level where the player moves, shoots palette-distinct
portals, traverses them, and dies/resets within world bounds — built on the SubViewport
dual-camera tree and a host-agnostic `PortalMovementComponent`. No autoloads.

**Contracts:** `docs/refactor-roadmap.md` (sequencing), `docs/refactor-architecture.md`
(dependency/component/scene/event rules + Prohibited Patterns table). Branch references
(structure vs behavior, richer-wins per feature): CLAUDE.md "Reference policy".

---

## Per-task session process

Each task below runs in its own session:

1. **brainstorming** → write the task spec to `docs/specs/2026-06-03-phase-1-<task>.md`.
   Read the named prerefactor sources first; design the public interface from the boundary in.
2. **writing-plans** → bite-sized implementation plan.
3. **implement** → I write `.gd`; the user builds `.tscn` + wiring; parse-check; commit.

(The scaffolding task has no design surface and may skip brainstorming.)

## Working convention

- **I write** `.gd` scripts. **The user builds** `.tscn` scenes + all Inspector wiring
  (node trees, `@export` assignments, SubViewport settings) in the Godot editor.
- No unit-test framework (no GUT). Per-script verification is a project-wide parse check;
  full verification is the in-editor runnable checkpoint.

### Parse-check command

```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | grep -iE "SCRIPT ERROR|Parse Error"
```

`--import` registers all `class_name` globals (needed for cross-file types; `--check-only
--script` does NOT and gives false "Could not find type" errors). Clean = no output. Exit
code is unreliable (Godot returns 0 on parse errors) — judge by grep output.

## Locked decisions

- **Jump:** buffer + coyote time (new game-feel), driven by the component's single `is_grounded`.
- **Levels:** keep the multi-level array + `_curr_lvl` + `inc_lvl_test` debug key. All
  persistence stripped to Phase 4.
- **Hitbox:** Player gets an enemy-contact `Hitbox` child now (mask wired in Phase 2).
- **Portal palette:** reuse `palette_swap.gdshader` + `palettes.png` from `refactor-attempt-0`
  (user-approved). `palette_index` is an `int` shader uniform. Single Portal scene,
  `collision_mask = 12`.

## Shared facts (used across tasks)

- **Player physics layers:** `collision_layer = 12`, `collision_mask = 3` (ported). Every
  Area2D that must detect the player (Portal, WorldBounds) needs `collision_mask = 12`.
- **Group type-tags** (opt-in tags, never lookup): `"portal_travelers"` (added by
  `PortalMovementComponent._ready`, read by `Portal`), `"portals"` (added by `Portal._ready`,
  read by the movement component's collision point-query), `"enemies"` (read by `Hitbox`,
  populated Phase 2), `"player"` (added by `Player._ready`).
- **Folder layout** (architecture doc): `portal/`, `characters/player/`, `world/{cameras/, levels/}`.

---

## Task A — Scaffolding & shared assets

**Goal:** Project ready for code: folders, input map, palette assets. No game logic.
**Depends on:** nothing (do first). **Brainstorming:** skip.

- Copy `palette_swap.gdshader` + `palettes.png` (+ `.import`) from r-a-0 into `portal/assets/`.
- `project.godot` input map (PC-only): `left`=A, `right`=D, `jump`=Space, `down`=S,
  `fire_one`=Q, `fire_two`=E, `pause`=Esc, `inc_lvl_test`=Ctrl+X.
  **Drop:** `up` (unused), `crouch` (dead duplicate of `down`), `save_test` (Phase 4), all mobile.

---

## Task B — Portal system (the crux bet)

**Goal:** Host-agnostic portal traversal as composition, replacing the `PortalEntity` base.
**Scripts:** `portal/portal_movement_component.gd`, `portal/portal.gd`.
**Depends on:** Task A. **Behavior source:** prerefactor `portal.gd`, `portal_entity.gd`.

**Public interface:**
- `PortalMovementComponent extends Node` — `@export var body: CharacterBody2D`;
  `var is_grounded: bool` (read by host at top of frame); `move(delta)` (ports
  `custom_move_and_slide`: move-and-collide, sets `is_grounded`, returns early on portal
  collisions, slides otherwise); `_ready` registers `body` in `"portal_travelers"`. Owns
  `find_portal_at_collision` (point query against `"portals"`).
- `Portal extends Area2D` (`class_name Portal`) — `@export var linked_portal: Portal`,
  `@export var palette_index: int`; teleports overlapping `"portal_travelers"` bodies with
  exit-speed boost; `_ready` adds `"portals"` + applies the palette shader param.

**Keep/Fix/Drop:** drop `extends PortalEntity` (→ component), drop two portal PackedScenes
(→ `palette_index`), detection by group not `is` type. **Preserve** the one-frame-stale
`is_grounded` ordering exactly. **Fix** the ground-normal dot threshold to a true 45°:
use `cos(PI/4)` (= 0.7071), not bare `PI/4` (= 0.785, ~38.2°). The prerefactor compared a
dot product against `PI/4` radians — a unit error; bare `PI/4` is ~38°, not 45°. `cos(PI/4)`
is the minimal correction (the original intent was 45°, the `cos` was just missing).

**Scene (user):** `Portal.tscn` — Area2D (`collision_mask = 12`) + AnimatedSprite2D (palette
ShaderMaterial: `palette_tex` = `palettes.png`) + CollisionShape2D (~8x26).

**Validates:** the host-agnostic bet — Phase 2 attaches this component to an enemy unchanged.

---

## Task C — Player

**Goal:** Plain `CharacterBody2D` player with portal movement, mouse aim, jump feel, death.
**Scripts:** `characters/player/player.gd`, `gun_pivot.gd`, `hitbox.gd`.
**Depends on:** Task B. **Behavior source:** prerefactor `player.gd`, `gun_pivot.gd`,
`portal_gun.gd` (facing only).

**Public interface:**
- `Player extends CharacterBody2D` (`class_name Player`) — `signal died`; accesses its
  `PortalMovementComponent` via `%` unique name (not an owner-side export); methods
  `die()`, `respawn(pos: Vector2)`,
  `set_portal_container(c: Node2D)`, `reset_portals()`, `is_facing_left() -> bool`,
  `get_gun_global_position() -> Vector2`, `get_gun_global_rotation() -> float`.
  `_physics_process` decomposed into ~5 methods (gather/gravity/jump/horizontal/aim +
  animation); jump buffer + coyote replace the old `can_jump`/cooldown/`test_move`.
- `GunPivot extends Node2D` (`class_name GunPivot`) — `@export var portal_scene: PackedScene`,
  `@export var portal_container: Node2D`; `reset()`; raycast portal placement + linking on
  `fire_one`/`fire_two` (palette 0/1).
- `Hitbox extends Area2D` (`class_name Hitbox`) — `signal hit`; self-wires `body_entered`,
  emits on `"enemies"` contact. Player connects `hit → die` (`CONNECT_DEFERRED`).

**Keep/Fix/Drop:** drop `extends PortalEntity`, `mobile_mode`/`aim_joystick`/mobile aim
branch, the `get_nodes_in_group("enemies")` distance loop, `owner.level_controller` coupling
(→ injected `portal_container`), dual PackedScenes. **Position interface exposes
position+rotation separately** (PortalArm is high-res with its own scale — never a `Transform2D`).

**Scene (user):** `Player.tscn` — CharacterBody2D (`collision_layer = 12`, `collision_mask =
3`) → AnimatedSprite2D (`idle`/`run`/`jump`/`crouch`), GunPivot (+ AimLine Line2D),
PortalMovementComponent, Hitbox. Wire `PortalMovementComponent.body → Player`,
`GunPivot.portal_scene → Portal.tscn`. (`Hitbox.collision_mask` set in Phase 2.)

---

## Task D — Level management

**Goal:** Load a level from the array, reset on death, kill on out-of-bounds. No persistence.
**Scripts:** `world/levels/level_base.gd`, `world/levels/world_bounds.gd`,
`world/level_controller.gd`. **Depends on:** Task C. **Behavior source:** prerefactor
`level_controller.gd`, `killzone.gd`.

**Public interface:**
- `LevelBase extends Node2D` (`class_name LevelBase`) — `@export var player_spawn: Node2D`,
  `signal level_completed`. Concrete levels extend it.
- `WorldBounds extends Area2D` — `body_entered` → `if body is Player: body.call_deferred("die")`.
  Self-contained, no player ref, frees with its level.
- `LevelController extends Node` (`class_name LevelController`) — `@export var levels:
  Array[PackedScene]`, `@export var player: Player`. `_ready` connects `player.died →
  _reset_lvl` (`CONNECT_DEFERRED`) + loads `_curr_lvl`. `_create_lvl` reads
  `_insted_lvl.player_spawn` (no `get_node`), positions player, `player.set_portal_container`.
  Reset: free old level → create new → `player.respawn` → `player.reset_portals`.
  `inc_lvl_test` increments `_curr_lvl` and reloads.

**Keep/Fix/Drop:** drop `get_node("PlayerSpawn")`/`("WorldBoundSpawn")` (→ `player_spawn`
export), the `Killzone`/`WorldBoundSpawn` reposition hack (bounds live per-level), the
`"persist"` group + `Debug.Save.*` + `save_to_state`/`load_from_state` + `save_test`
(Phase 4), the group-loop portal cleanup (portals are level children, free automatically).
**Keep** `levels` array + `_curr_lvl` + `inc_lvl_test`. Reset reorders respawn after
`_create_lvl` (uses new spawn) — deliberate; `inc_lvl_test` reloads immediately — deliberate.

**Scene (user):** `Level*.tscn` extending `LevelBase` — `PlayerSpawn` Node2D (→ `player_spawn`),
`WorldBounds` (`collision_mask = 12`) below the level, portal-surface StaticBodies on layer 1.

---

## Task E — Cameras & high-res overlay (+ Main scene tree)

**Goal:** The SubViewport dual-camera pipeline and the high-res gun overlay; first full run.
**Scripts:** `world/cameras/low_res_camera.gd`, `world/cameras/high_res_camera.gd`,
`characters/player/portal_arm.gd`. **Depends on:** Task C. **Behavior source:** prerefactor
`low_res_camera.gd`, `high_res_camera.gd`, `portal_gun.gd`.

**Public interface:**
- `LowResCamera extends Camera2D` — `@export var follow_target: Node2D`; snaps to
  `follow_target.global_position.round()`. (In-SubViewport.)
- `HighResCamera extends Camera2D` — `@export var player: Player`, `@export var
  sub_viewport_container: SubViewportContainer`, `smooth_speed`, `velocity_influence`;
  velocity-influenced lerp toward the container center.
- `PortalArm extends Sprite2D` — `@export var player: Player`; mirrors the gun via
  `player.get_gun_global_position()` + `get_gun_global_rotation()` + `is_facing_left()`.

**Keep/Fix/Drop:** drop HighResCamera's `level_controller.player` reach-through (→ `@export
var player`); drop PortalArm's `get_nodes_in_group("characters")` + `player.gun_pivot.*` /
`player.animated_sprite_2d.*` reach-through (→ Player public interface).

**Scene (user):** `Main.tscn` per `refactor-architecture.md` Scene Rules #6:
```
Main (Node2D)
  SubViewportContainer       [full-screen anchors]
    SubViewport              [Scene Rules #7 settings; process_mode = Inherit — NOT ALWAYS]
      Player                 (instance)
      LevelController
      LowResCamera
  HighResCamera              [zoom = screen_width / subviewport_width]
  PortalArm
```
Wiring: `LowResCamera.follow_target → Player`; `HighResCamera.player → Player`,
`.sub_viewport_container → SubViewportContainer`; `PortalArm.player → Player`;
`LevelController.player → Player`, `.levels → [Level1.tscn]`. Set `Main.tscn` as main scene.

---

## Sequencing

`A → B → C → {D, E}` (D and E both depend only on C). E builds `Main.tscn`, so the first
integrated run happens at the end of E (with a Level from D). Each task parse-checks its
scripts; the full slice is verified at the Phase 1 checkpoint.

## Phase 1 runnable checkpoint (after all tasks + scenes)

Run `Main.tscn` and confirm: player moves (A/D) and jumps (Space) with buffer+coyote feel,
faces the mouse, gun aims; Q/E place two palette-distinct portals; entering one teleports out
the other with the speed boost; falling into `WorldBounds` kills + respawns at spawn and
clears placed portals; `Ctrl+X` cycles levels; pixel art is crisp (nearest-neighbor); the
high-res overlay tracks the in-world gun; the camera follows with velocity smoothing; no
console errors (no autoloads required).

## Deferred (do not pull in)

- Runtime resolution picker (`project-resolution-settings` memory) — after Phase 1.
- Mobile support (`project-no-mobile` memory) — dropped entirely.
- SceneLoader (Phase 3), SaveManager (Phase 4), UI/menus (Phase 5), Enemies (Phase 2).
