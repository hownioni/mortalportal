# Mortal Portal — Refactor Architecture

Derived from comparative analysis of `prerefactor` and `refactor-attempt-0` branches.
Covers: portal system, player system, level management, camera/resolution system.

---

## Folder Structure

```
res://
├── portal/
│   ├── portal.gd
│   ├── portal_movement_component.gd
│   └── assets/
│
├── characters/
│   ├── player/
│   │   ├── player.gd
│   │   ├── gun_pivot.gd
│   │   ├── portal_arm.gd
│   │   └── assets/
│   └── enemies/
│       └── [enemy-type]/
│           ├── [enemy].gd
│           └── assets/
│
├── world/
│   ├── level_controller.gd
│   ├── cameras/
│   │   ├── high_res_camera.gd
│   │   └── low_res_camera.gd
│   └── levels/
│       ├── level_base.gd
│       └── [level scenes]
│
├── core/
│   └── [autoloads: SaveManager, EventBus, AudioManager]
│
├── ui/
│   └── [menus, HUD]
│
└── assets/
    └── [mirrors domain structure]
```

**Domain rationale:**

- `portal/` — the portal mechanic is independent of who uses it. `PortalMovementComponent` can attach to any `CharacterBody2D`. `Portal` is a world object. Neither belongs exclusively under `characters/` or `world/`.
- `gun_pivot.gd` lives in `characters/player/` because it is the player's weapon and always a child of the Player scene. Its dependency on `portal.gd` is injected via `@export`.
- `world/` holds level infrastructure — the controller, level base class, and cameras. These define how the world is structured and rendered, not the entities within it.
- `core/` holds only things that are genuinely stateful and global across the entire scene tree.

---

## Dependency Rules

**1. All cross-scene dependencies are injected via `@export`.**

No `get_node("/root/...")`, no `get_tree().find_child()`, no `get_tree().get_first_node_in_group()` for wiring dependencies.

```gdscript
# Correct
@export var player: Player
@export var portal_container: Node2D

# Forbidden
var player = get_tree().get_first_node_in_group("player")
var joystick = get_tree().root.find_child("AimJoystick", true, false)
```

**2. Use the most specific type available.**

`Portal` not `Area2D`. `LevelBase` not `Node`. `Node2D` is acceptable only when the dependency is genuinely type-agnostic (e.g., `LowResCamera.follow_target: Node2D`).

**3. Never reach through an injected node to its children.**

If `LevelController` needs to configure `GunPivot`, it does so through a method on `Player`.

```gdscript
# Correct
player.set_portal_container(_insted_lvl)

# Forbidden
player.gun_pivot.portal_container = _insted_lvl
```

**4. Components receive their host via `@export`, not `get_parent()`.**

`PortalMovementComponent` declares `@export var body: CharacterBody2D`. The Player scene wires it in the Inspector.

**5. Autoloads only for systems that are stateful and global across the entire scene tree.**

Sanctioned: `SaveManager`, `EventBus`, `AudioManager`. Nothing else. A script that needs the player gets it via `@export`, not from a global.

---

## Component Rules

**1. Add behavior by adding a child node.**

Portal-aware movement is `PortalMovementComponent` — a child `Node` on any `CharacterBody2D`. Not a base class. Adding it to an enemy grants portal traversal with zero inheritance changes.

**2. Maximum 2 levels of class inheritance from project classes.**

Godot built-ins (`CharacterBody2D`, `Area2D`, `Node`) are level 0. A project class extending one is level 1. Another extending that is level 2. A third level requires composition instead.

**3. Components own their group registration.**

`PortalMovementComponent._ready()` calls `body.add_to_group("portal_travelers")`. The host script does not do this. The component encapsulates what it needs to function.

**4. A component should be host-agnostic.**

`PortalMovementComponent` works with any `CharacterBody2D`. `LowResCamera` follows any `Node2D`. Components are not coupled to a specific class unless there is a genuine behavioral requirement.

**5. Don't extract a component to reduce line count.**

`WorldBounds` is a 4-line script. That is fine — it earns its existence as a named scene boundary with a signal connection, not because it saves lines.

---

## Scene Rules

**1. A scene's internal nodes are private.**

No external script may call `get_node()` on an instance of another scene.

```gdscript
# Correct
_player_spawn = _insted_lvl.player_spawn

# Forbidden
_player_spawn = _insted_lvl.get_node("PlayerSpawn")
```

**2. A scene's public interface is: `@export` vars, signals, and `class_name` methods.**

If something outside the scene needs to know about it, it goes on the interface. Everything else is private.

**3. Level scenes implement the `LevelBase` contract.**

Every level inherits `LevelBase` and wires `@export var player_spawn: Node2D`. `LevelController` depends only on this contract.

**4. Elements that belong to a level are children of the level.**

`WorldBounds`, enemies, portal surfaces, and portals placed by the player all live as children of the level instance. They free automatically when the level frees. No external cleanup loops.

**5. Player and LevelController are siblings, not parent/child.**

Both are children of the SubViewport. LevelController does not own Player.

**6. Main scene tree shape:**

```
Main (Node2D)
  SubViewportContainer           [full-screen anchors]
    SubViewport                  [pixel-art resolution; nearest-neighbor; process_mode=Inherit]
      Player
      LevelController
      LowResCamera
  HighResCamera                  [zoom = screen_width / subviewport_width]
  PortalArm                      [high-res gun overlay]
```

**7. SubViewport required settings:**

| Setting | Value | Why |
|---|---|---|
| `canvas_item_default_texture_filter` | `0` (Nearest) | No blurring on pixel art scale-up |
| `handle_input_locally` | `false` | Input must reach the main scene |
| `disable_3d` | `true` | 2D game |
| `audio_listener_enable_2d` | `true` | Audio positioned in world space |
| `render_target_update_mode` | `4` (Always) | Render every frame |
| `process_mode` | default (Inherit) | Pauses when tree pauses |

---

## Event Communication Rules

**1. Signals for "something happened" events that cross scene boundaries.**

`player.died`, `LevelBase.level_completed`. The emitter does not know who is listening. The receiver connects in its own `_ready`.

**2. Direct method calls for requests within a known dependency.**

`player.respawn(pos)`, `player.set_portal_container(level)`, `gun_pivot.reset()`. Synchronous requests where the caller knows the callee.

**3. Use `CONNECT_DEFERRED` when a signal is emitted from a physics callback.**

```gdscript
player.died.connect(_reset_lvl, CONNECT_DEFERRED)
```

Required when `die()` is triggered from `body_entered` or `_physics_process`. Prevents scene tree modification inside a physics step.

**4. Groups are opt-in type tags, not lookup mechanisms.**

| Group | Purpose | Who adds | Who reads |
|---|---|---|---|
| `"portal_travelers"` | Eligible for portal teleportation | `PortalMovementComponent._ready` | `Portal._physics_process` |
| `"persist"` | Participates in save/load | Nodes that implement the contract, in `_ready` | `SaveManager` |

`get_tree().get_nodes_in_group()` is only valid for these group-pattern uses. Never used to locate a specific dependency.

**5. `EventBus` for game-wide broadcasts with no clear ownership.**

Nothing in the systems analyzed so far requires it. Use it for future events that need to reach systems with no direct dependency path (e.g., `game_paused`). If a signal can be connected directly, connect it directly.

---

## Prohibited Patterns

Derived directly from prerefactor code smells.

| Prerefactor pattern | Rule violated | Correct form |
|---|---|---|
| `_insted_lvl.get_node("PlayerSpawn")` | Scene internals are private | `_insted_lvl.player_spawn` |
| `player = level_controller.player` in HighResCamera `_ready` | No reaching through injected nodes | `@export var player: Player` |
| `get_tree().root.find_child("AimJoystick", ...)` | No tree searches for dependencies | `@export var aim_joystick: Node2D` |
| `get_tree().get_nodes_in_group("enemies")` distance loop | Groups are not lookup mechanisms | Physics `Hitbox` + `body_entered` signal |
| `extends PortalEntity` for portal traversal | Prefer composition; max 2 inheritance levels | `PortalMovementComponent` child |
| `owner.level_controller` in GunPivot | No implicit structural coupling | `@export var portal_container: Node2D` |
| Two separate portal PackedScenes for visual variants | Visual variants are data | Single scene, `@export var palette_index: int` |
| Group loop to free portals on reset | Elements belong to their level scene | Portals as level children; freed automatically |
| Mobile aiming, `buttons_android/`, `mobile_mode` flag | Out of scope | PC only |
