# Mortal Portal — Refactor Migration Roadmap

Approved 2026-06-03. Strategic sequencing for migrating eight subsystems from the
`prerefactor` branch into `full-refactor`. Each system gets its own spec -> plan ->
implementation cycle. This document is the ordering contract only.

Architectural contract: `docs/refactor-architecture.md`

---

## Context

The `full-refactor` branch is a clean slate: only `docs/`, `addons/`, and `project.godot`
exist. The ordering below validates the two highest-risk architectural bets first:

1. **The main scene tree** -- SubViewport + dual-camera + resolution pipeline (the part
   `refactor-attempt-0` got wrong via `process_mode = ALWAYS`).
2. **Host-agnostic `PortalMovementComponent`** -- composition replacing the old
   `PortalEntity` base class.

Source of truth for behavior: `../mortalportal-prerefactor/` (read-only).
Reference for what was tried (ask before reusing): `../mortalportal-refactor-attempt-0/`.

---

## Working convention: scripts vs scenes

- **I write** `.gd` scripts (logic, `class_name`, `@export` declarations, signals).
- **The user builds** `.tscn` scenes and does all Inspector wiring (node tree, `@export`
  assignments, SubViewport settings, scene instancing) in the Godot editor.
- Scene authoring is fully manual. The Godot MCP tools were evaluated and rejected:
  no script attachment, no `@export` NodePath wiring, no scene instancing.
- Every phase splits work into **Scripts (I write)** and **Scenes + wiring (user builds)**
  so no implementation session stalls waiting on an unbuilt scene.

Each phase ends at a **runnable checkpoint** verified in the editor before the next phase.

---

## Dependency graph

```
                 +------------------------------------------+
                 | PHASE 1  Core gameplay slice              |
                 |  Player -- PortalMovementComponent --+    |
                 |     |            |                   |    |
                 |  Level (LevelBase) -- Portal ---------+   |
                 |     |                                     |
                 |  Cameras (LowRes/HighRes) + PortalArm     |
                 |  inside the Main/SubViewport tree         |
                 +----------------+--------------------------+
                                  | provides: runnable level, player, portal component
         +-----------------------+------------------------+------------------+
         v                       v                        v                  v
   PHASE 2 Enemies         PHASE 3 SceneLoader      PHASE 4 SaveManager  PHASE 5 UI/menus
   (reuses PortalMove-     (level/scene             (persist group on    (needs SceneLoader
    mentComponent +          transitions)             LevelController)     to start game,
    Hitbox pattern)              |                         |               SaveManager for
         |                       +------------+------------+               saves menu)
         |                                    v                                  ^
         +-----------------------------------+---------------------------------+
```

- Phase 1 is the foundation; nothing else can run without the main scene tree.
- Phase 2 (Enemies) depends only on Phase 1; it is the early test of the host-agnostic
  component bet.
- Phase 3 (SceneLoader) and Phase 4 (SaveManager) are independent of each other but both
  depend on level management (Phase 1).
- Phase 5 (UI) depends on SceneLoader (menu -> game) and SaveManager (saves menu).

---

## Phase 1 -- Core gameplay slice (Player + Portal + Level + Cameras)

**Goal:** A single runnable level where the player moves, shoots a portal, traverses it,
and dies/resets within world bounds. No autoloads required.

**Internal order:**

1. Folder scaffolding + `project.godot`: domain folders per `refactor-architecture.md`;
   input map (read prerefactor, drop all mobile actions per `project-no-mobile` memory).
2. Main scene tree (user builds): `Main -> SubViewportContainer -> SubViewport ->
   {Player, LevelController, LowResCamera}`, plus sibling `HighResCamera` and `PortalArm`.
   Apply SubViewport settings table from `refactor-architecture.md` Scene Rules #7 --
   note `process_mode = Inherit` (the r-a-0 fix).
3. Player: plain `CharacterBody2D`, no inherited base; 5-method `_physics_process`
   decomposition; jump buffer + coyote time + gather state; `Hitbox` for enemy contact;
   `died` signal.
4. Portal: single `Portal` scene with `@export var palette_index: int`; no separate
   PackedScenes per variant. `PortalMovementComponent` child node on Player,
   `@export var body: CharacterBody2D`, owns its `"portal_travelers"` group registration.
5. Level: `LevelBase` contract (`@export var player_spawn: Node2D`, `level_completed`
   signal); one concrete level; `WorldBounds` child of the level; `player.died.connect(
   _reset_lvl, CONNECT_DEFERRED)` in `LevelController._ready`; `player.set_portal_container()` /
   `player.reset_portals()` methods (no reaching into `gun_pivot`).
6. Cameras: `LowResCamera.follow_target: Node2D`; `HighResCamera @export var player:
   Player` injected directly; `PortalArm` high-res gun overlay.

**Scripts I write:**
`player.gd`, `gun_pivot.gd`, `portal_arm.gd`, `portal.gd`,
`portal_movement_component.gd`, `level_base.gd`, `level_controller.gd`,
`world_bounds.gd`, `low_res_camera.gd`, `high_res_camera.gd`

**Scenes + wiring user builds:**
`Main.tscn` (+ SubViewport settings), `Player.tscn` (+ component/hitbox children,
`@export` wiring), `Portal.tscn`, one `Level*.tscn` (spawn + WorldBounds + portal
surfaces), camera nodes.

**Keep / fix / drop:** governed by `refactor-architecture.md` "Prohibited Patterns" table
-- reference it directly. Notable drops: `PortalEntity` base, dual portal PackedScenes,
`get_node("PlayerSpawn")`, `owner.level_controller`, all mobile aiming.

**Autoloads needed:** none.

---

## Phase 2 -- Enemies

**Validates:** `PortalMovementComponent` is genuinely host-agnostic (attach to an enemy
`CharacterBody2D` with zero inheritance changes) and the `Hitbox` + `body_entered`
contact pattern replaces the old `get_nodes_in_group("enemies")` distance loop.

**Own spec required.** Spec must: read enemy types in `prerefactor`; map each to a
`CharacterBody2D` + components; identify which gain portal traversal via
`PortalMovementComponent`; define the enemy public interface and which behaviors are
components vs. logic on the enemy script.

**Scripts I write:** per-enemy `.gd` under `characters/enemies/[type]/`.
**Scenes + wiring user builds:** per-enemy `.tscn`, placed as children of levels.

---

## Phase 3 -- SceneLoader

**Purpose:** Level/menu scene transitions.

`prerefactor` has a threaded SceneLoader autoload with a progress overlay; not present
in r-a-0.

**Own spec required.** Spec must: analyze the prerefactor threaded loader + progress
overlay; decide what to keep vs. simplify under the autoload rules (genuinely global +
stateful qualifies); define the minimal public interface (e.g. `SceneLoader.load_scene(path)`).

**Autoload created here:** `SceneLoader` -- not front-loaded into Phase 1.

---

## Phase 4 -- SaveManager

**Purpose:** Persistence (slot-based save files).

`prerefactor` SaveManager is fully implemented (slot-based JSON, atomic writes, `persist`
group pattern); not in r-a-0.

**Own spec required.** Spec must: analyze the prerefactor implementation; keep the
`persist`-group contract (`refactor-architecture.md` Event Communication Rules #4); wire
`LevelController` (and other persistors) into the `"persist"` group; define save/load
hooks; confirm the atomic-write + slot model survives the new structure.

**Autoload created here:** `SaveManager` -- not front-loaded.

---

## Phase 5 -- UI / menus

**Purpose:** Front-end that ties SceneLoader + SaveManager together.

**Own spec required.** Spec must: analyze prerefactor menus (main menu, saves menu, pause
overlay); main menu uses SceneLoader to start the game; saves menu uses SaveManager;
pause overlay is built around the running gameplay tree. Lives under `ui/`.

**Scenes + wiring user builds:** menu `.tscn`s.

---

## Deferred / out of scope

Do not pull these into any phase without an explicit decision:

- **Runtime resolution picker** (`project-resolution-settings` memory): in-game picker
  updating SubViewport size + HighResCamera zoom + PortalArm scale at runtime. Designed
  separately after Phase 1, not inside the camera step.
- **Mobile support** (`project-no-mobile` memory): joystick, `mobile_mode`,
  `buttons_android/` -- dropped entirely. PC only.
