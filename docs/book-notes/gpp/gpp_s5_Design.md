## Command

### Core Intent

Encapsulate a request as an object, enabling runtime remapping, undo, replay, and actor-agnostic dispatch.

### Problem It Solves

Hard-coded input handlers couple button events directly to actor methods, preventing runtime remapping and forcing AI onto a separate code path from the player. When actions are direct calls, undo requires full game-state snapshots rather than compact per-action state capture.

### Engineering Motivation

Godot's `Callable` natively delivers actor-parameterized fire-and-forget dispatch without a class hierarchy, making the GoF pattern redundant for simple remapping. `RefCounted` command objects remain necessary when `undo()` must capture pre-execution state or when commands must be serialized for deterministic replay.

### When to Use

- Input bindings must be remappable at runtime without modifying scripts.
- Undo, redo, or deterministic action replay is required.
- AI and player-controlled actors share the same action interface.
- Actions must be queued, deferred, or transmitted across an RPC boundary.
- A level editor or tool pipeline requires reversible operations.

### When NOT to Use

- Actions are fire-and-forget with no history requirement; a `Callable` alone is sufficient and adds no overhead.
- The command would capture a global Autoload as its actor, leaving the coupling intact inside the closure.
- Routing all game mutations through commands is impractical given the current codebase structure.

### Main Tradeoffs

| Benefit                                                                         | Cost                                                                                        |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| Runtime remapping via `Callable` binding — no per-action class hierarchy needed | Undo requires all mutations to route through commands; one bypass silently corrupts history |
| Pre-execution state captured in the command object — no global snapshot         | `RefCounted` allocation per push in undo history                                            |
| AI and player share one action interface; actor is a runtime parameter          | History entries hold `Node` references that must be guarded for validity after free         |
| `Callable.bind()` delivers parameter-capturing deferred dispatch for free       | Network replay requires explicit per-command parameter serialization                        |

### Common Misuse

Developers pass a global Autoload as the actor captured inside a `Callable`, then describe the result as "decoupled command architecture" — the global dependency is intact inside the closure, structurally identical to a direct call.

### Failure Mode

An `UndoableCommand` in the history stack holds a raw `Node` reference; the node is freed before `undo()` is invoked, producing a null-access crash that surfaces only when the player undoes past the point of destruction.

### Structural Model

```text
[Callable variant — fire-and-forget, no per-action class]

InputHandler (Node)
    _bindings: Dictionary[StringName, Callable]
    actor: CharacterBody2D  ←── swappable for AI at runtime
    _unhandled_input → _bindings[action].call(actor)

[RefCounted variant — undo/redo, pre-state capture]

UndoableCommand (RefCounted)       MoveCommand extends UndoableCommand
    execute(actor: Node2D)             _to: Vector2
    undo(actor: Node2D)                _from: Vector2  ← captured at execute()

CommandHistory (RefCounted)
    _stack: Array[UndoableCommand]  |  _cursor: int
    push(cmd, actor) | undo(actor) | redo(actor)

InputHandler / AIController ──produces──▶ [cmd0][cmd1][cmd2*][cmd3]
                                                          ↑ _cursor
```

### Game-Specific Lens

Nystrom's actor-parameterized `execute(GameActor&)` form — absent from GoF — is the key game variant: it lets one command drive any entity including AI without modification, unifying both control paths. In Godot, `Callable` already delivers this for stateless commands with no class at all, making the GoF hierarchy necessary only when `undo()` requires pre-execution state.

### Godot Adaptation Notes

- `Callable` and `Callable.bind()` replace stateless `Command` subclass hierarchies entirely for remapping and AI dispatch.
- `InputMap` owns button-to-action binding; script-level code maps action `StringName` keys to callables, not raw buttons.
- `RefCounted` eliminates C++ destructor management and `unique_ptr` ownership concerns for history entries; lifetime is automatic.
- `call_deferred()` converts synchronous command dispatch to next-frame deferred execution without a custom queue.
- For multiplayer, actor mutations route through `@rpc` methods on the actor node; `MultiplayerSynchronizer` handles reconciliation rather than a serialized command stream.
- For editor plugins and `@tool` scripts, `EditorUndoRedoManager` provides full undo infrastructure; never build a custom history stack in that context.
- The cursor-based history list (not a pop stack) is unchanged from the original; Godot provides no built-in game-mode undo infrastructure.

### Gameplay-Level Usage

A turn-based system records one `CommandHistory` per actor per turn and replays turns by re-executing the stored command sequence, providing deterministic replay at no extra cost. A game director or AI system issues commands through the same callable bindings as the player, keeping action logic unified across all control modes.

### Entity-Level Usage

Each controllable character holds a `CommandHistory` instance; reassigning `InputHandler.actor` from the player's node to an AI node transfers full control with zero changes to command or history code. An `UndoableCommand` captures only the state slice it modifies — not a full entity snapshot — keeping history entries small.

### Engine/System-Level Usage

`InputMap` is configured at project startup; a binding layer maps action names to callables that inject the current actor at dispatch time. A `ReplayRecorder` Autoload serializes the per-frame command stream; replay mode substitutes the recorded stream for live input and runs the game loop identically.

### Suggested Script Layout

```text
res://systems/command/
    undoable_command.gd     # RefCounted base — execute()/undo() interface
    move_command.gd         # RefCounted — concrete, captures _from at execute()
    command_history.gd      # RefCounted — cursor-based list, no SceneTree presence
res://entities/player/
    input_handler.gd        # Node — callable bindings, InputMap bridge, actor swap
    player.tscn             # Player ▶ InputHandler ▶ ...
res://autoloads/
    replay_recorder.gd      # Autoload — justified by project-wide frame recording
```

### Godot Performance Notes

**Memory allocation patterns** — `Callable` dispatch allocates nothing at call time; use it unconditionally for real-time input. `RefCounted` commands allocate once on push and are freed when history trims the reference. Set a concrete maximum undo depth and pre-reserve the `Array` at load time to prevent incremental reallocation during gameplay.

**Signal connection overhead** — Dispatching commands via signal adds O(n) overhead per receiver; prefer direct `.call()` on a stored `Callable` for single-actor dispatch where signal fan-out is not needed.

### Godot Anti-Patterns

**Autoload actor capture** — Closing over `GameManager` or any global Autoload inside a `Callable` preserves global coupling inside the command. Pass the actor explicitly as a parameter or resolve it via `is_instance_valid()` + `NodePath` at execute time.

**RefCounted commands for real-time input** — Creating a new `UndoableCommand` per button event in a real-time game generates per-frame allocation pressure. Reserve `RefCounted` commands for turn-based or editor contexts where undo depth is bounded and allocation frequency is low.

**Bypassing the command pipeline** — A single `actor.position = x` outside `push()` silently corrupts the undo log from that point forward; every mutation the history tracks must route through `push()`.

### GDScript Structural Example

```gdscript
# input_handler.gd — callable binding; actor-parameterized dispatch, no per-action class
class_name InputHandler
extends Node

@export var actor: CharacterBody2D
var _bindings: Dictionary[StringName, Callable] = {}

func bind(action: StringName, fn: Callable) -> void:
    _bindings[action] = fn

func release_to_ai(ai_actor: CharacterBody2D) -> void:
    actor = ai_actor  # same bindings, new target — zero changes elsewhere

func _unhandled_input(event: InputEvent) -> void:
    for action: StringName in _bindings:
        if event.is_action_pressed(action) and is_instance_valid(actor):
            _bindings[action].call(actor)
            get_viewport().set_input_as_handled()
            return
```

```gdscript
# move_command.gd — origin captured at execute(); undo restores it exactly
class_name MoveCommand
extends RefCounted

var _to: Vector2
var _from: Vector2 = Vector2.ZERO

func _init(destination: Vector2) -> void:
    _to = destination

func execute(actor: Node2D) -> void:
    _from = actor.position
    actor.position = _to

func undo(actor: Node2D) -> void:
    actor.position = _from
```

```gdscript
# command_history.gd — cursor-based; supports multi-level undo and redo
class_name CommandHistory
extends RefCounted

var _stack: Array[MoveCommand] = []
var _cursor: int = -1

func push(cmd: MoveCommand, actor: Node2D) -> void:
    _stack.resize(_cursor + 1)   # discard redo branch on new action
    cmd.execute(actor)
    _stack.append(cmd)
    _cursor += 1

func undo(actor: Node2D) -> void:
    if _cursor >= 0:
        _stack[_cursor].undo(actor)
        _cursor -= 1

func redo(actor: Node2D) -> void:
    if _cursor < _stack.size() - 1:
        _cursor += 1
        _stack[_cursor].execute(actor)
```

### Related Patterns

Event Queue, Flyweight, State, Observer

### Competing Patterns

Direct Call, Event Queue, Callable

### Key Implementation Notes

- `Callable` fully replaces stateless `Command` subclasses; add `RefCounted` only when `undo()` is needed.
- Use `is_instance_valid()` before dereferencing any `Node` held in a history entry.
- Resize the history `Array` on `push()` at `_cursor + 1` to discard the redo branch before appending.
- For editor plugins, use `EditorUndoRedoManager` — never a custom history stack.
- In multiplayer contexts, commands drive local prediction; `@rpc` + `MultiplayerSynchronizer` handle authoritative reconciliation.
- A `Callable`-based binding table keyed on `StringName` actions integrates cleanly with `InputMap` without duplicating binding logic.

---

## Flyweight

### Core Intent

Share a single copy of immutable intrinsic state across all instances, keeping only per-instance extrinsic state on each object.

### Problem It Solves

Rendering thousands of similar objects requires per-object data that would exhaust memory if fully duplicated; the portions that are identical across all instances of a type — mesh, texture, movement cost — represent wasted memory when stored per-instance. The shared portions need a single authoritative home that all instances reference.

### Engineering Motivation

Godot's `Resource` system is a native Flyweight implementation: a `.tres` file loaded from the same path returns the same object in memory, shared across all referencing nodes with no extra infrastructure. The intrinsic/extrinsic split maps directly onto `Resource` fields (shared, effectively immutable) versus `Node` properties (per-instance).

### When to Use

- A large number of scene instances share identical static data — mesh, texture, terrain properties, stat blocks.
- Object count is in the thousands and per-instance memory footprint is a measurable constraint.
- Designer-editable shared configuration is part of the pattern's value (`@export` on `Resource`).
- GPU instanced rendering is the target; `MultiMeshInstance3D` maps directly to the Flyweight model.

### When NOT to Use

- Instance count is small enough that sharing provides negligible memory savings.
- Every instance has genuinely unique state with no common subset worth sharing.
- `Resource.duplicate()` is being called per-instance, which defeats the pattern entirely.

### Main Tradeoffs

| Benefit                                                                                   | Cost                                                                                             |
| ----------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------ |
| Eliminates per-instance duplication of large shared data at zero code cost via `Resource` | Shared `Resource` mutation affects every instance referencing it — the primary failure mode      |
| `ResourceLoader.load()` guarantees one object per path; sharing is automatic              | `Resource.duplicate()` silently breaks sharing; callers must know when not to call it            |
| `@export` exposes shared config in the Inspector for designer authorship                  | Intrinsic/extrinsic split requires design discipline; mixing the two degrades the pattern        |
| `MultiMeshInstance3D` maps the Flyweight directly onto GPU instanced draw calls           | Per-instance extrinsic data (transforms, tints) must be maintained separately in the `MultiMesh` |

### Common Misuse

Developers call `resource.duplicate()` on an `@export`-exposed `Resource` in `_ready()` to get a "safe per-instance copy," then wonder why the memory-sharing benefits evaporated — every instance now holds its own full copy.

### Failure Mode

A shared `Resource` field that should be read-only is mutated at runtime (e.g., adjusting a tint, modifying a stat); every instance referencing that resource reflects the change instantly, producing widespread unexpected behavior with no single identifiable source.

### Structural Model

```text
[Resource sharing — multiple Nodes, one Resource object]

oak_tree.tres  (TreeDefinition Resource — one object in memory)
    mesh: Mesh
    movement_cost: int = 1
    blocks_movement: bool = true

Tree_01 (Node3D)  @export definition ──▶ [oak_tree.tres]
Tree_02 (Node3D)  @export definition ──▶ [oak_tree.tres]   ← same object reference
Tree_03 (Node3D)  @export definition ──▶ [pine_tree.tres]
Tree_04 (Node3D)  @export definition ──▶ [pine_tree.tres]  ← same object reference

Per-instance (extrinsic) state stays on the Node:
    Tree_01: position, bark_tint, height_scale  (Node3D transform + local vars)
    Tree_02: position, bark_tint, height_scale

[GPU instancing analog]
MultiMeshInstance3D
    multimesh.mesh ──▶ shared Mesh (one GPU upload)
    multimesh instance transforms[] ← per-instance extrinsic data
```

### Game-Specific Lens

Nystrom notes that Flyweight may be the only GoF pattern with direct hardware support: GPU instanced rendering is architecturally identical — one shared model, per-instance transform data streamed separately. In Godot, `MultiMeshInstance3D` is the engine-native realization of this; `Resource`-based Flyweight handles the data-access layer, while `MultiMesh` handles the render layer.

### Godot Adaptation Notes

- `Resource` is the Godot-native Flyweight; no custom shared-object infrastructure is needed.
- `ResourceLoader.load("res://path.tres")` always returns the same object for the same path — sharing is automatic and guaranteed.
- `@export var definition: MyResource` in the Inspector assigns a shared reference; no factory method or registry is needed to enforce uniqueness.
- `Resource.duplicate(true)` performs a deep copy and must never be called on a flyweight; it is the correct tool only when per-instance mutation is genuinely required.
- The `const`-all-fields discipline from the C++ implementation maps to "never write to a shared Resource field at runtime" — Godot cannot enforce this statically, so it must be a code convention.
- For GPU-scale instancing, replace individual `MeshInstance3D` nodes with `MultiMeshInstance3D`; the shared `Mesh` on the `MultiMesh` is the GPU-level Flyweight.
- What is unchanged: the intrinsic/extrinsic split requires explicit architectural discipline regardless of engine.

### Gameplay-Level Usage

Terrain tile grids store an `Array[TerrainType]` where each element is a reference to one of a small set of shared `TerrainType` resources; the grid holds thousands of references at the cost of a few shared objects. Enemy stat blocks are shared `EnemyType` resources; a hundred goblin grunt instances share one `EnemyType` and differ only in current health and position.

### Entity-Level Usage

Each enemy or environment node holds `@export var type: EnemyType` assigned in the Inspector; the node reads `type.move_speed`, `type.max_health`, and `type.sprite_frames` without owning any of that data. Per-instance extrinsic state — current health, current target, position — stays as direct properties on the node.

### Engine/System-Level Usage

A `ResourceLoader.load()` call at boot populates a typed dictionary of `TerrainType`, `ProjectileType`, or `EnemyType` resources keyed by `StringName`; the world map, spawners, and projectile systems all hold references into this shared registry without duplicating any data.

### Suggested Script Layout

```text
res://resources/types/
    enemy_type.gd           # Resource — intrinsic shared data
    terrain_type.gd         # Resource — intrinsic shared data
    projectile_type.gd      # Resource — intrinsic shared data
res://resources/data/
    enemies/goblin_grunt.tres
    enemies/goblin_wizard.tres
    terrain/grass.tres
    terrain/river.tres
res://entities/enemy/
    enemy.gd                # Node — extrinsic per-instance data + @export type: EnemyType
    enemy.tscn
```

### Godot Performance Notes

**Resource sharing vs. per-instance duplication** — Assigning the same `.tres` reference to 1 000 enemy instances costs one pointer per instance. Calling `duplicate()` per instance costs the full size of the resource per instance and eliminates the pattern's benefit entirely.

**SceneTree traversal cost** — Reading `definition.move_speed` on a shared `Resource` is a direct field access; it is no more expensive than reading a local property. No SceneTree traversal occurs.

**PackedScene instancing cost** — `PackedScene.instantiate()` does not copy shared `Resource` references; the instanced scene shares the same `Resource` objects assigned in the source scene, preserving Flyweight semantics automatically.

**Node count implications** — Replacing hundreds of individual `MeshInstance3D` nodes with one `MultiMeshInstance3D` reduces SceneTree overhead dramatically at high instance counts; prefer `MultiMesh` when instance count exceeds a few dozen.

### Godot Anti-Patterns

**Calling `duplicate()` in `_ready()`** — Duplicating an `@export` resource on every instance to enable "safe" per-instance modification defeats the pattern and doubles memory use. Design the resource to hold only truly shared data; put per-instance state on the node.

**Mutable shared Resource fields** — Writing to a `Resource` field at runtime from an instance method (e.g., `type.current_health -= damage`) mutates shared state for every instance of that type. Per-instance mutable state must live on the node.

**Per-instance `load()` calls** — Calling `ResourceLoader.load()` with the same path in every entity's `_ready()` re-parses the asset from disk; assign the shared resource once at a system level or via the Inspector.

### GDScript Structural Example

```gdscript
# enemy_type.gd — intrinsic state: one Resource shared across all instances of a type
class_name EnemyType
extends Resource

@export var display_name: String = ""
@export var max_health: int = 100
@export var move_speed: float = 150.0
@export var attack_damage: int = 10
@export var sprite_frames: SpriteFrames
@export var collision_radius: float = 16.0
# Treat all fields as immutable at runtime — mutation affects every instance of this type.
```

```gdscript
# enemy.gd — extrinsic state: per-instance data only; shared data accessed via type reference
class_name Enemy
extends CharacterBody2D

@export var type: EnemyType  # assign same .tres in Inspector for all grunts of this type

var current_health: int = 0
var target: Node2D = null

func _ready() -> void:
    assert(type != null, "Enemy requires an EnemyType resource.")
    current_health = type.max_health
    $AnimatedSprite2D.sprite_frames = type.sprite_frames  # shared reference, no copy

func take_damage(amount: int) -> void:
    current_health -= amount

func get_speed() -> float:
    return type.move_speed  # read-only access to shared data

func get_attack_damage() -> int:
    return type.attack_damage
```

### Related Patterns

Type Object, Object Pool, State

### Competing Patterns

Enum + match (simpler, scatters data), Type Object (similar structure, different intent: runtime type flexibility vs. memory efficiency)

### Key Implementation Notes

- Never write to a shared `Resource` field at runtime from an instance; treat all `Resource` fields as read-only after initial load.
- `ResourceLoader.load()` with the same path always returns the same object; use this guarantee instead of a custom registry.
- `Resource.duplicate(true)` breaks sharing and must be used deliberately and sparingly.
- For GPU-scale objects, replace individual node instances with `MultiMeshInstance3D`; the `Mesh` on the `MultiMesh` is the engine-level Flyweight.
- Use `@export var type: EnemyType` to surface the shared resource in the Inspector; this is the core wiring mechanism, not a convenience.
- Stateless `State` objects (no per-machine data) can be shared as Flyweights across multiple FSM instances using the same Resource reference.

---

## Observer

### Core Intent

Let a subject notify a list of loosely coupled observers when its state changes, without knowing the concrete types of its observers.

### Problem It Solves

Achievement, audio, and analytics systems all need to react to game events, but embedding their calls directly in gameplay code creates unacceptable cross-domain coupling. Any system that wants notification must be able to register for it without the event source knowing it exists.

### Engineering Motivation

Godot's `signal` system is a first-class, engine-native implementation of Observer: the subject declares signals, observers connect callables, and Node lifetime handles the destruction safety problem automatically. The dangling-observer crash from C++ — the pattern's primary production failure mode — does not occur for `Node` observers because freed nodes disconnect their signal connections automatically.

### When to Use

- A change in one system should trigger reactions in one or more unrelated systems.
- The number or identity of interested receivers is not known at scene-authoring time.
- Cross-domain events (achievements, analytics, audio triggers) must not penetrate domain boundaries.
- Decoupling the event source from receivers is more valuable than explicit call-site traceability.

### When NOT to Use

- Sender and receiver are always understood together; a direct method call is cleaner and traceable.
- The receiver might be slow or perform heavy work; use `call_deferred()` or an Event Queue to decouple in time.
- The codebase is small enough that signal indirection adds confusion without a concrete decoupling benefit.
- Thread safety is required; Godot signals are not thread-safe by default and require `call_deferred()` for cross-thread emission.

### Main Tradeoffs

| Benefit                                                                                     | Cost                                                                                               |
| ------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| Subject and observers change independently; subject has zero import dependency on receivers | Signal call chain is invisible at call sites; debugger shows `emit()` rather than receiver methods |
| Observers connect and disconnect at runtime without modifying the subject                   | `Object`/`RefCounted` observers must disconnect manually; failure causes lapsed listener leaks     |
| `Node` observers auto-disconnect on `queue_free()` — no dangling pointer crashes            | Synchronous emission: a slow receiver in the signal chain stalls the subject directly              |
| Signals are first-class typed API; IDE provides completion and parameter checking           | Overuse of signals for intra-feature communication hides coupling that should be explicit          |

### Common Misuse

Developers wire signals between nodes that are always part of the same feature and must always be understood together, producing hidden coupling that breaks silently when either node is refactored — the same coupling problem that signals were meant to solve, now obscured by indirection.

### Failure Mode

A `RefCounted` or `Object` observer connects to a signal and is later freed or goes out of scope without calling `disconnect()`; the subject holds the connection and calls into invalidated memory on next emission, either crashing or firing into a dead object silently.

### Structural Model

```text
[Direct wiring — same scene, known receiver]

HealthComponent (Node)
    signal health_changed(current: int, maximum: int)
    signal depleted()
    apply_delta(delta) → emit health_changed | depleted

HealthComponent --health_changed(int,int)--> UIHealthBar._on_health_changed
HealthComponent --depleted()--------------> Player._on_player_depleted

[EventBus — cross-scene, any number of unknown receivers]

Enemy.gd
    EventBus.enemy_died.emit(id, position)
                    ↓
    EventBus (Autoload)
        signal enemy_died(id: int, position: Vector2)
                    ↓──────────────────────────────────┐
    AchievementSystem                         AudioSystem
    ._on_enemy_died(id, pos)                 ._on_enemy_died(id, pos)

[Node freed] → signal connections auto-removed — lapsed listener impossible for Nodes
[Object/RefCounted freed without disconnect()] → crash on next emission
```

### Game-Specific Lens

Nystrom argues that the GoF Observer's class-heavy `onNotify()` interface is unnecessary in languages with first-class functions: a registered callable does the same job with less infrastructure. Godot's `signal` system realizes this exactly — `.connect(callable)` accepts any callable without requiring the observer to implement a specific interface, eliminating the `Observer` base class entirely.

### Godot Adaptation Notes

- `signal` declarations replace the `Observer` interface; no base class is needed.
- `.connect()` and `.disconnect()` replace `addObserver()`/`removeObserver()`; bindings are type-checked at connection time.
- `Node` observers auto-disconnect on `queue_free()` — the dangling-pointer crash from C++ does not apply.
- `RefCounted` and `Object` observers must call `disconnect()` explicitly before release; the lapsed listener memory leak applies to these types.
- `call_deferred()` on the emission side converts synchronous Observer to deferred execution for receivers that are too slow to block the subject.
- A typed `EventBus` Autoload — signals only, no state or logic — is preferable to direct cross-scene `get_node()` chains for many-to-many cross-domain events.
- When a custom event bus provides cleaner routing than raw signals at project scale, use it and explain the tradeoff: it adds one level of indirection but removes all direct scene path dependencies between emitters and receivers.

### Gameplay-Level Usage

A gameplay event bus Autoload declares typed signals for all game-level events (`enemy_died`, `level_completed`, `item_collected`); achievement, analytics, quest, and audio systems connect to whichever signals they care about independently. The systems that emit these signals never reference the systems that receive them.

### Entity-Level Usage

A `HealthComponent` node on any character declares `health_changed` and `depleted` signals; the owning entity's `_ready()` wires these to a `UIHealthBar` and to any other local receivers. The component has no knowledge of, and no reference to, any of its observers.

### Engine/System-Level Usage

A narrowly scoped `EventBus` Autoload with typed signal declarations only — no state, no logic, no behaviour — acts as the project-wide signal exchange for cross-scene, cross-domain events. Systems connect in their own `_ready()` and disconnect in `_exit_tree()` or automatically when freed as Nodes.

### Suggested Script Layout

```text
res://components/
    health_component.gd     # Node — declares and emits signals
res://ui/
    ui_health_bar.gd        # Node — connects in scene or _ready()
res://autoloads/
    event_bus.gd            # Autoload — typed signal declarations only, no state
res://systems/
    achievement_system.gd   # Node or Autoload — connects to EventBus
    audio_system.gd         # Node or Autoload — connects to EventBus
```

### Godot Performance Notes

**Signal connection overhead** — `.connect()` is O(1); `.emit()` is O(n) in the number of connected callables. For a subject with two to four observers the cost is negligible. For high-frequency signals emitted every physics frame with many observers, prefer direct method calls and use signals only for low-frequency state-change events.

**Node count implications** — Signals require no additional nodes; `HealthComponent` is the only node introduced, and it serves a lifecycle/encapsulation role regardless of Observer use.

**Memory allocation patterns** — Godot signal connections are stored internally in the engine; they do not trigger user-space heap allocation per connection. Disconnecting on `queue_free()` is automatic for Node observers.

### Godot Anti-Patterns

**EventBus with logic or state** — Adding methods, counters, or cached state to the `EventBus` Autoload turns it into a hidden global service; it should contain signal declarations only and remain a passive routing layer.

**Using signals for intra-feature communication** — Wiring signals between two nodes that are always part of the same scene and always change together hides coupling without removing it; use a direct method call when the receiver is always known and always required.

**Forgetting to disconnect `Object` observers** — `Node` observers auto-disconnect on free; `Object` and `RefCounted` observers do not. Failing to call `disconnect()` on these causes the lapsed listener memory leak that Godot's Node system was designed to prevent in the first place.

### GDScript Structural Example

```gdscript
# health_component.gd — Subject; declares and emits, knows nothing about receivers
class_name HealthComponent
extends Node

signal health_changed(current: int, maximum: int)
signal depleted()

@export var maximum: int = 100
var _current: int = 0

func _ready() -> void:
    _current = maximum

func apply_delta(delta: int) -> void:
    _current = clamp(_current + delta, 0, maximum)
    health_changed.emit(_current, maximum)
    if _current == 0:
        depleted.emit()

func get_ratio() -> float:
    return float(_current) / float(maximum)
```

```gdscript
# event_bus.gd (Autoload "EventBus") — signal declarations only; no state, no logic
class_name EventBus
extends Node

signal enemy_died(enemy_id: int, kill_position: Vector2)
signal item_collected(item_type: StringName, collector_id: int)
signal score_changed(new_score: int)

# Emit from anywhere:   EventBus.enemy_died.emit(id, global_position)
# Observe from anywhere: EventBus.enemy_died.connect(_on_enemy_died)
```

```gdscript
# achievement_system.gd — connects to EventBus; enemies never reference this system
class_name AchievementSystem
extends Node

var _kill_count: int = 0

func _ready() -> void:
    EventBus.enemy_died.connect(_on_enemy_died)

func _on_enemy_died(_id: int, _pos: Vector2) -> void:
    _kill_count += 1
    if _kill_count == 1:
        _grant(&"first_blood")
    elif _kill_count == 100:
        _grant(&"centurion")

func _grant(id: StringName) -> void:
    EventBus.score_changed.emit(0)  # trigger downstream observers
    print("Achievement: ", id)
```

### Related Patterns

Event Queue, Command, State

### Competing Patterns

Event Queue, Direct Call

### Key Implementation Notes

- Declare signals with explicit typed parameters; untyped `signal foo` loses IDE assistance and type safety at connection time.
- `Node` observers auto-disconnect on `queue_free()`; `Object`/`RefCounted` observers must call `disconnect()` explicitly before release.
- Use `call_deferred()` at the emission site to prevent a slow receiver from blocking the subject within its own call stack.
- An `EventBus` Autoload containing only signal declarations is preferable to direct cross-scene `get_node()` chains for many-to-many event routing.
- Two observers connected to the same signal must have no ordering dependency; if order matters, the observers are implicitly coupled and a direct sequential call chain is more honest.
- Prefer connecting signals in the scene editor or in `_ready()` of the owning node; avoid connecting in deeply nested utility functions where connection lifetime is unclear.

---

## Prototype

### Core Intent

Specify the kinds of objects to create using a prototypical instance and create new objects by cloning that prototype.

### Problem It Solves

A spawner that creates one entity type requires either a separate subclass per type (a parallel class hierarchy) or direct knowledge of the concrete class at construction time. When entity variants differ by runtime-configured state — not purely by class — type-parameterized construction cannot capture that distinction.

### Engineering Motivation

Godot's `PackedScene` system makes the GoF `clone()` method redundant: `PackedScene.instantiate()` deep-copies a fully configured scene instance including all child nodes, scripts, and property overrides. The "parallel spawner class hierarchy" problem from C++ cannot arise because `Spawner` is type-agnostic — any `PackedScene` is a valid prototype.

### When to Use

- A spawner must produce pre-configured entity variants without knowing their concrete types.
- Entity variants differ by runtime-configured data, not just by class — and you want to configure them visually in the editor.
- Data-driven content files define entity variants via prototype delegation (one resource referencing a base resource) to share base attributes.

### When NOT to Use

- `PackedScene.instantiate()` already covers the use case — no additional pattern infrastructure is needed.
- The system already uses Component or Type Object, which solve entity-type variation without per-type `clone()` implementations.
- Variant differences are purely data-driven; a single entity type with a swappable `@export var type: EnemyType` (Type Object) handles it more cleanly.

### Main Tradeoffs

| Benefit                                                                                    | Cost                                                                                            |
| ------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------- |
| `PackedScene.instantiate()` clones any configured scene; `Spawner` remains type-agnostic   | Scene instancing cost is non-trivial for complex scenes; pool if spawning at high frequency     |
| Full deep-copy semantics by default — no shallow/deep ambiguity for scene instances        | `Resource.duplicate()` requires `true` for deep copy of subresources; default is shallow        |
| Data prototype delegation via Resource `@export base` enables designer content inheritance | Delegation chains must be resolved manually; Godot provides no automatic prototype chain lookup |
| No `clone()` method needs to be implemented on any class                                   | Prototype data chains add read-complexity; clear naming conventions are essential               |

### Common Misuse

Implementing a GoF-style `clone()` interface on entity classes when `PackedScene.instantiate()` already handles scene-level cloning, adding redundant infrastructure that duplicates what the engine provides natively.

### Failure Mode

Calling `Resource.duplicate()` without `true` on a resource that holds nested subresources produces a shallow copy; the original and the clone share the same subresource objects, and modifying one corrupts the other in ways that only surface when the shared subresource is first mutated.

### Structural Model

```text
[PackedScene variant — type-agnostic spawner, no clone() method]

Spawner (Node)
    @export prototype: PackedScene ──▶ ghost.tscn
    spawn(at: Vector3) → prototype.instantiate() → Node

ghost.tscn  (any scene structure works — Spawner never inspects it)
    Ghost (CharacterBody3D)
    └── HealthComponent (Node)
    └── AIController (Node)
    └── CollisionShape3D

[Assign a different .tscn to the same Spawner node to spawn a different type]

[Resource delegation variant — data prototype chain for designer content inheritance]

goblin_wizard.tres
    base: ──▶ goblin_base.tres   ← unset fields delegate here
    spells: [fireball.tres]
    max_health: 0                ← 0 = "inherit from base"

goblin_base.tres
    base: null
    max_health: 20
    move_speed: 3.0
    spells: []

resolve_health():  goblin_wizard(0) → base → goblin_base(20) → 20
```

### Game-Specific Lens

Nystrom is candid that the GoF Prototype design pattern is largely redundant in modern engine practice, where `PackedScene` and Type Object solve entity-type variation more cleanly. Its most relevant form in games is in data modeling: giving resource objects a `base` field that enables designer-authored single-delegation inheritance so variants can be defined without duplicating base attributes.

### Godot Adaptation Notes

- `PackedScene.instantiate()` replaces `clone()` entirely for scene-level entity spawning; it performs a full deep copy including all child nodes, scripts, and overridden properties.
- `Resource.duplicate(true)` performs a deep copy of a resource graph; always pass `true` when the resource contains nested subresource references.
- Data prototype delegation maps to an `@export var base: EnemyDefinition` field on a `Resource`; resolution is a manual chain traversal since Godot provides no automatic prototype lookup.
- The "parallel spawner class hierarchy" problem does not arise in Godot; a single `Spawner` node is type-agnostic over any `PackedScene`.
- Deep-vs-shallow copy ambiguity is resolved by default for scenes (`instantiate()` always deep-copies) but must be handled explicitly for resources (`duplicate()` is shallow by default).
- For high-frequency spawning, wrap `PackedScene.instantiate()` inside an Object Pool to avoid per-spawn allocation.

### Gameplay-Level Usage

A wave director holds an `Array[PackedScene]` of enemy prototypes and calls `instantiate()` on whichever prototype matches the current wave definition; the director never references any concrete enemy class. Data-driven level scripts reference `EnemyDefinition` resources that chain to base definitions, allowing designers to define fifty enemy variants from three base configs without any script changes.

### Entity-Level Usage

A `Spawner` node holds `@export var prototype: PackedScene`; swapping the assigned `.tscn` in the Inspector changes what the spawner produces. A `Projectile` pool pre-instantiates N copies of a `PackedScene` at load time and recycles them, using `instantiate()` only during the pool warm-up phase.

### Engine/System-Level Usage

A `SpawnRegistry` Autoload loads a dictionary of `PackedScene` prototypes keyed by `StringName` at startup; runtime systems request spawns by key without holding direct scene references. `EnemyDefinition` resources are loaded into a registry at boot and shared as Flyweights across all spawned instances.

### Suggested Script Layout

```text
res://systems/spawning/
    spawner.gd              # Node — @export prototype: PackedScene
    spawn_registry.gd       # Autoload or Resource — keyed PackedScene dictionary
res://resources/definitions/
    enemy_definition.gd     # Resource — data prototype with @export base: EnemyDefinition
    data/
        goblin_base.tres
        goblin_wizard.tres  # base → goblin_base.tres
        goblin_archer.tres  # base → goblin_base.tres
res://entities/
    ghost/ghost.tscn        # the PackedScene prototype
    demon/demon.tscn
```

### Godot Performance Notes

**PackedScene instancing cost** — `PackedScene.instantiate()` parses and constructs the full node tree on every call; for complex scenes spawned at high frequency (bullets, particles), use an Object Pool that pre-instantiates at load time and recycles instances.

**Resource sharing vs. per-instance duplication** — `@export var type: EnemyDefinition` on a spawned instance holds a shared reference with no copy cost. Calling `resource.duplicate(true)` inside `_ready()` creates a full per-instance copy — never do this unless per-instance mutation is genuinely required.

**Memory allocation patterns** — Each `PackedScene.instantiate()` call allocates the full node tree; pre-warm pools during loading screens, not during gameplay frames, to keep allocation off the hot path.

### Godot Anti-Patterns

**Implementing `clone()` on Node subclasses** — Adding a `clone()` method to entity scripts duplicates what `PackedScene.instantiate()` already does and adds unnecessary maintenance. Use scene instantiation.

**Shallow `resource.duplicate()` on data definitions** — Calling `duplicate()` without `true` on a resource with nested subresources produces a partial copy that silently shares subresource state. Always pass `true` for data definitions with nested resources.

**Spawner class hierarchy** — Creating `GhostSpawner`, `DemonSpawner`, and `ZombieSpawner` subclasses is the exact C++ anti-pattern that `PackedScene` eliminates; one `Spawner` node with a swappable `@export prototype: PackedScene` handles all types.

### GDScript Structural Example

```gdscript
# spawner.gd — type-agnostic; PackedScene IS the prototype, no clone() needed
class_name Spawner
extends Node

@export var prototype: PackedScene
@export var spawn_parent: NodePath = ^".."

func spawn(at: Vector3) -> Node:
    assert(prototype != null, "Spawner.prototype must be assigned.")
    var instance: Node = prototype.instantiate()
    get_node(spawn_parent).add_child(instance)
    if instance is Node3D:
        (instance as Node3D).global_position = at
    return instance

func spawn_batch(positions: Array[Vector3]) -> Array[Node]:
    var result: Array[Node] = []
    for pos: Vector3 in positions:
        result.append(spawn(pos))
    return result
```

```gdscript
# enemy_definition.gd — data prototype delegation; designers define variants in the Inspector
class_name EnemyDefinition
extends Resource

@export var base: EnemyDefinition  # delegate chain; null = root definition
@export var max_health: int = 0    # 0 = "inherit from base"
@export var move_speed: float = 0.0
@export var display_name: String = ""

func resolve_health() -> int:
    if max_health > 0:
        return max_health
    return base.resolve_health() if base != null else 0

func resolve_speed() -> float:
    if move_speed > 0.0:
        return move_speed
    return base.resolve_speed() if base != null else 0.0

func resolve_name() -> String:
    if not display_name.is_empty():
        return display_name
    return base.resolve_name() if base != null else ""
```

### Related Patterns

Component, Type Object, Object Pool

### Competing Patterns

PackedScene + `instantiate()` (engine-native; supersedes GoF Prototype for scene-level cloning), Type Object, Component

### Key Implementation Notes

- Use `PackedScene.instantiate()` for all scene-level entity cloning; never implement `clone()` on `Node` subclasses.
- Always pass `true` to `Resource.duplicate()` when the resource contains nested subresource references.
- Data prototype delegation via `@export var base: SameResourceType` enables designer content inheritance without script changes.
- Pool `PackedScene` instances at load time for any entity spawned at high frequency; instantiation is not allocation-free.
- Type Object (`@export var type: EnemyDefinition`) is the preferred pattern when variants differ by data; use Prototype when variants differ by scene structure and require different node hierarchies.
- `SpawnRegistry` Autoload keyed by `StringName` decouples spawn-site scripts from direct `PackedScene` references, supporting data-driven wave and level definitions.

---

## Singleton

### Core Intent

Ensure a class has exactly one instance and provide a global point of access to it.

### Problem It Solves

Some systems — audio playback, save data, scene routing — must exist as exactly one instance and be reachable from anywhere in the project. Without a controlled global access mechanism, callers must either receive the instance by explicit injection or use unmediated raw globals.

### Engineering Motivation

Nystrom's chapter is primarily an argument against the pattern: the lazy initialization it relies on fires at an unpredictable frame and causes heap allocation spikes mid-gameplay, and the global access it provides actively encourages the cross-domain coupling that game architecture requires to be isolated. In Godot, Autoloads replace the pattern structurally while resolving the lazy-init spike — but they preserve the coupling and testability costs unchanged.

### When to Use

- The system truly must be instantiated exactly once AND no lighter-weight mechanism — explicit injection, Resource sharing, or a signal bus — is practical.
- The system is genuinely ambient infrastructure with project-wide scope: audio playback, scene transition, save/load, global event bus.
- Use Autoloads sparingly; Nystrom's actual recommendation applies directly: prefer explicit dependency passing or scoped services in almost every case.

### When NOT to Use

- Convenient global access is the primary motivation — this is the most common misuse.
- The system will ever need a second instance: test doubles, split-screen players, platform-specific providers.
- Cross-scene shared state is the need; a `Resource` passed via `@export` is a non-global alternative with no access control cost.
- Cross-scene events are the need; a typed `EventBus` Autoload (signals only) is preferable to a stateful manager Autoload.
- "Manager" classes are proliferating — the proliferation is the signal that responsibilities should move to the objects being managed.

### Main Tradeoffs

| Benefit                                                                                      | Cost                                                                                                                         |
| -------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Autoload initializes at project startup — no lazy-init frame spike (unlike C++ Singleton)    | Global access still encourages unintended cross-domain coupling regardless of when init occurs                               |
| Available globally from any script without injection or `@export` wiring                     | Untestable in isolation; Autoloads cannot be replaced with mocks without engine-level workarounds                            |
| Single registration point in ProjectSettings makes the set of globals explicit and auditable | Autoload proliferation (GameManager, UIManager, EnemyManager) produces the same hidden dependency web as C++ Singleton abuse |
| Autoload can hold state, expose signals, and process each frame                              | Always-on processing and memory cost even when the autoload is idle                                                          |

### Common Misuse

Developers register an Autoload for every system that needs to be "accessible from anywhere," solving "I need to access this from multiple scenes" rather than the actual problem of "this system must exist as exactly one instance."

### Failure Mode

Autoloads proliferate across the project — `GameManager`, `UIManager`, `InventoryManager`, `QuestManager` — until every system is globally reachable from every other system with no access control; a change to any one Autoload's API breaks scenes that were never intended to depend on it.

### Structural Model

```text
[Autoload pattern — narrow, justified scope]

ProjectSettings → Autoload:
    AudioBus      res://autoloads/audio_bus.gd      ← SFX pool, one bus
    SceneRouter   res://autoloads/scene_router.gd   ← scene transitions
    EventBus      res://autoloads/event_bus.gd      ← signals only, no state

Access: AudioBus.play(stream)  [any script, no import, no injection]

[Anti-pattern: Autoload proliferation — hidden dependency web]

GameManager ──(invisible)──▶ PlayerManager ──(invisible)──▶ InventoryManager
UIManager   ──(invisible)──▶ QuestManager  ──(invisible)──▶ DialogueManager

[Preferred alternative: Resource for cross-scene shared state]
GameSettings.tres (Resource, @export on any node that needs it)
    master_volume: float
    difficulty: int
    — no global access point; dependency is explicit in the Inspector

[Preferred alternative: EventBus Autoload for cross-scene events]
EventBus (Autoload — signals only)
    signal enemy_died(id: int, pos: Vector2)
    ← zero state, zero coupling, fully auditable
```

### Game-Specific Lens

Nystrom inverts the GoF presentation entirely, treating Singleton as an anti-pattern chapter. Games pay two costs the GoF never addresses: lazy initialization can spike a frame when the audio or file system first allocates at a gameplay moment, and the global coupling Singleton enables directly undermines domain isolation that large teams need for parallel development. Godot's Autoload resolves the first cost (eager startup init) but not the second.

### Godot Adaptation Notes

- Autoload is Godot's native Singleton mechanism; registration in ProjectSettings, not code, is the correct setup path.
- Autoloads initialize at project startup in registration order — there is no lazy-init frame spike, resolving Nystrom's specific performance concern.
- The global coupling and testability problems are unchanged; Autoloads cannot be easily mocked or replaced in test scenarios.
- A `Resource` passed via `@export` is the preferred pattern for cross-scene shared data; it provides no global access point and makes dependencies explicit in the Inspector.
- A typed `EventBus` Autoload (signal declarations only, no state) is the preferred pattern for cross-scene events; it is the only Autoload type that does not accumulate hidden coupling.
- When a stateful service Autoload is genuinely necessary, keep it narrowly scoped: audio playback, scene routing, save/load. These justify Autoload because they are truly project-wide, have no meaningful alternative, and must persist across scene transitions.
- `EditorPlugin` singletons are a separate category and follow their own registration rules.

### Gameplay-Level Usage

A `SaveSystem` Autoload that persists `GameState` across scenes is a justified singleton: it is genuinely project-wide, must survive scene transitions, and has no per-scene alternative. A global `ScoreManager` Autoload that tracks one integer is not justified; pass the score via a `GameState` resource.

### Entity-Level Usage

Individual entities should never hold Autoload references as fields — this makes their dependencies invisible. If an entity needs to emit a game-level event, it emits on `EventBus` (signal-only Autoload) and has no other Autoload dependency. If an entity needs configuration data, it receives a `Resource` via `@export`.

### Engine/System-Level Usage

Three Autoloads cover the legitimate project-wide surface: `AudioBus` (SFX pool, one bus), `SceneRouter` (fade/transition, `change_scene_to_packed()`), and `EventBus` (typed signals only). Every other "service" either lives as a node in the relevant scene or passes its dependencies explicitly.

### Suggested Script Layout

```text
res://autoloads/
    audio_bus.gd        # Autoload — SFX pool, one instance, justified
    scene_router.gd     # Autoload — scene transitions, justified
    event_bus.gd        # Autoload — typed signals only, no state
res://resources/
    game_settings.gd    # Resource — cross-scene shared data, no global access
    game_state.gd       # Resource — runtime state passed via @export
```

### Godot Performance Notes

**Frame-time stability** — Autoloads initialize at project startup in registration order; no lazy-init spike occurs during gameplay frames. Register heavy Autoloads early in the list so their initialization cost lands in the loading phase.

**Memory allocation patterns** — Autoloads persist for the lifetime of the project; any memory they hold is never released until exit. Keep Autoload state lean; push per-scene state down into `Resource` objects that can be unloaded.

**Node count implications** — Each Autoload adds one `Node` to the SceneTree root and receives `_process()` / `_physics_process()` calls if enabled; disable processing on Autoloads that do not require it.

### Godot Anti-Patterns

**Autoload proliferation** — Registering a new Autoload for every system that needs project-wide access produces the same hidden dependency web as C++ Singleton abuse. Audit Autoloads regularly; if a service can be scoped to a scene or injected via `@export`, remove it from the Autoload list.

**Stateful EventBus** — Adding mutable state, cached values, or logic to the `EventBus` Autoload turns it into a hidden global service. The EventBus Autoload must contain only signal declarations; all state belongs in `Resource` or scoped nodes.

**Lazy initialization within Autoloads** — Deferring expensive work (file I/O, audio stream loading) to the first call inside an Autoload recreates the frame-spike problem Autoloads were supposed to solve. Front-load all heavy initialization into `_ready()`, which runs before the first scene loads.

### GDScript Structural Example

```gdscript
# audio_bus.gd (Autoload "AudioBus")
# Justified: SFX pool must persist across scenes, has no per-scene alternative,
# and is genuinely project-wide infrastructure. Initialized at startup — no frame spike.
class_name AudioBus
extends Node

const _POOL_SIZE: int = 8

var _players: Array[AudioStreamPlayer] = []

func _ready() -> void:
    for i: int in _POOL_SIZE:
        var p := AudioStreamPlayer.new()
        p.bus = &"SFX"
        add_child(p)
        _players.append(p)

func play(stream: AudioStream, volume_db: float = 0.0) -> void:
    for player: AudioStreamPlayer in _players:
        if not player.playing:
            player.stream = stream
            player.volume_db = volume_db
            player.play()
            return
    push_warning("AudioBus: SFX pool exhausted — dropping sound.")
```

```gdscript
# game_settings.gd — Resource alternative to a settings Autoload; no global access point
# Assign the same .tres instance to any node that needs it via @export.
class_name GameSettings
extends Resource

@export var master_volume: float = 1.0
@export var sfx_volume: float = 1.0
@export var music_volume: float = 1.0
@export var difficulty: int = 1
@export var screen_shake_enabled: bool = true

# Usage: @export var settings: GameSettings  (on AudioBus, Player, or any node)
# Same .tres assigned in Inspector = shared state, no global access, explicit dependency.
```

### Related Patterns

Service Locator, Subclass Sandbox, Event Queue

### Competing Patterns

Service Locator, Explicit Dependency Injection, Resource sharing via `@export`

### Key Implementation Notes

- Prefer explicit `@export var dep: MyResource` injection over Autoload for any service whose consumers can be determined at scene-authoring time.
- If single-instantiation enforcement is needed without global access, use an assert-guard in `_init()` rather than an Autoload: `assert(not _instantiated, "Only one instance allowed.")`.
- Initialize all Autoload state in `_ready()`; never defer to first-use lazy init within a gameplay frame.
- A `EventBus` Autoload containing only signal declarations is the lowest-coupling Autoload type and is generally acceptable at project scale.
- When you find yourself creating a manager Autoload, ask whether the managed class can own its own behavior directly; most manager Autoloads are a sign the managed class is anemic.
- Autoloads cannot be easily mocked in GDScript tests; design critical systems to accept dependency injection so they remain testable in isolation.

---

## State

### Core Intent

Allow an object to alter its behavior when its internal state changes by delegating behavior to a swappable state object.

### Problem It Solves

An entity with multiple exclusive behavioral modes accumulates boolean flags that can be in invalid combinations, and switch statements scatter state-specific logic and data across unrelated methods. Adding mode-specific data (charge timers, sub-phase counters) forces it onto the owning entity class even when only meaningful in one mode.

### Engineering Motivation

Scattered booleans produce invalid combinations the type system cannot prevent; distinct state objects make invalid combinations unrepresentable by construction. Co-locating all data and behavior for one mode in a single object means state-specific data only exists while that state is active.

### When to Use

- An entity has discrete, mutually exclusive behavioral modes with clean entry and exit conditions.
- State-specific data would otherwise pollute the owning entity class.
- Entry and exit actions must fire on every transition into or out of a state, regardless of source state.
- A pushdown automaton is needed to preserve and resume prior state (e.g., fire-then-resume-movement).

### When NOT to Use

- State count is three or fewer and transitions are trivial — an enum and `match` block is simpler and fully sufficient.
- Behavior variation is data-driven rather than mode-driven — use Type Object instead.
- Two independent behavioral dimensions would combine into n × m states — use two concurrent FSMs.
- AI complexity requires history, planning, or fuzzy states — FSMs are not Turing-complete; use behavior trees.

### Main Tradeoffs

| Benefit                                                                                 | Cost                                                                                                |
| --------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------- |
| Invalid state combinations become unrepresentable by construction                       | State explosion when two independent dimensions share one FSM                                       |
| All data and behavior for one mode lives in one object                                  | Transition logic is distributed across state classes; following a flow requires reading all of them |
| Entry/exit actions eliminate setup/teardown duplication across all incoming transitions | Node-based states add permanent SceneTree entries even when inactive                                |
| Pushdown automaton preserves prior state with minimal added complexity                  | `RefCounted` states allocate on every transition; frequent transitions on hot paths require pooling |

### Common Misuse

State-specific data (charge timers, sub-phase counters, accumulated cooldowns) is placed on the owning entity rather than inside the state class — exactly the boolean-flag tangle the pattern was designed to eliminate.

### Failure Mode

State-specific data stays on the owning entity; as state count grows the entity accumulates fields that are only valid in one mode, producing the invalid-combination problem the pattern was meant to replace.

### Structural Model

```text
[State transition diagram]

              PRESS_JUMP                       LAND
STANDING ─────────────────▶ JUMPING ◀──────────────────
    │                                                   │
    │ PRESS_DUCK                              PRESS_DUCK
    ▼                                                   ▼
DUCKING ◀───────────────────────────────── DIVING
           RELEASE_DUCK

[RefCounted variant — logic-heavy states with no per-state child nodes]

PlayerFSM (Node)
    _state: PlayerState
    _transition(to: PlayerState) — exit() old, enter() new; GC frees old automatically
    _unhandled_input  → _state.handle_input(body, event) → new state or null
    _physics_process  → _state.update(body, delta)       → new state or null

PlayerState (RefCounted)
    enter(owner: CharacterBody2D)
    exit(owner: CharacterBody2D)
    handle_input(owner, event: InputEvent) → PlayerState   ← null = no transition
    update(owner, delta: float) → PlayerState

[Node variant — states require _process, child nodes, AnimationPlayer, or scene composition]

Character (CharacterBody2D)
└── NodeFSM (Node)                    ← calls set_process/set_physics_process on transitions
    ├── Standing (CharacterState)     ← process disabled; enabled only when active
    ├── Jumping  (CharacterState)
    └── Ducking  (CharacterState)     ← owns charge_time in its own fields

[Pushdown automaton variant]
PlayerFSM
    _stack: Array[PlayerState]
    push_state(FiringState.new()) → pause current, enter new
    pop_state()                   → exit current, resume previous (any prior state)
```

### Godot Adaptation Notes

- Choose **RefCounted** for states with no per-state child nodes or independent processing requirements; choose **Node** when a state needs `_physics_process`, `AnimationPlayer` access, or its own child hierarchy.
- The C++ "defer deletion to after the triggering method returns" concern is eliminated: GDScript reference counting frees the old `RefCounted` state automatically when `_state` is reassigned in `_transition()`.
- In the Node variant, `set_process(false)` and `set_physics_process(false)` give explicit per-state lifecycle control; disable all child states in `NodeFSM._ready()` before activating the initial state.
- Godot's `AnimationTree` with `AnimationStateMachine` is a production-grade built-in FSM for animation transitions; never replace it with a custom script FSM for pure animation work.
- Concurrent FSMs map directly to two independent `PlayerFSM` or `NodeFSM` children on the same entity — locomotion FSM and equipment FSM run independently at n + m cost rather than n × m.
- Pushdown automaton: an `Array[PlayerState]` used as a stack is sufficient; push a transient state and pop it on completion to return to whatever state was previously active, with no hardcoded "return to" per source state.
- Stateless state objects (no per-FSM instance data) can be allocated once and shared as `Resource` instances across multiple FSM instances, functioning as Flyweights.

### Gameplay-Level Usage

A game phase FSM (`MainMenu → Loading → Playing → Paused → GameOver`) uses `RefCounted` states owned by a persistent `Node` or Autoload; each state manages which scenes are loaded and which Autoload services are active. A boss FSM uses `Node`-based states when each combat phase requires a distinct child node hierarchy (spawners, arena modifiers, animation controllers).

### Entity-Level Usage

A player character FSM uses `RefCounted` states for movement modes where state-specific data (coyote-time counters, jump buffer timers, charge timers) lives inside the relevant state object — not on the `CharacterBody2D`. The `PlayerFSM` node is a child of the player scene and drives the owning body by upward reference, decoupled from physics and rendering components.

### Engine/System-Level Usage

An input mode manager uses a state machine to switch between `GameInput` and `UIInput` states at the top of the input stack, routing `_unhandled_input` events to different handlers without proliferating `is_ui_open` conditionals. A scene transition manager uses states to gate asset loading, fade animations, and scene ownership changes as an ordered sequence.

### Suggested Script Layout

```text
res://entities/player/
    player.tscn                   # Player (CharacterBody2D) ▶ PlayerFSM (Node)
    player_fsm.gd                 # Node — transition driver
    states/
        player_state.gd           # RefCounted base
        standing_state.gd         # RefCounted
        jumping_state.gd          # RefCounted
        ducking_state.gd          # RefCounted — owns _charge_time field
res://entities/boss/
    boss.tscn                     # Boss ▶ NodeFSM ▶ [Phase1, Phase2, Phase3 as Nodes]
    node_fsm.gd                   # Node — set_process() lifecycle driver
    states/
        character_state.gd        # Node base
```

### Godot Performance Notes

**Memory allocation patterns** — `RefCounted` states allocate on each transition and are freed automatically. For FSMs that transition at high frequency (multiple times per second), pre-allocate a fixed set of state instances and store them as fields on the FSM; swap between pre-allocated instances rather than constructing new ones per transition.

**Node count implications** — Node-based states add permanent SceneTree entries regardless of whether they are active. Prefer `RefCounted` for FSMs with five or more states where most states are rarely active; disabled Nodes still occupy SceneTree memory and are traversed during tree operations.

**Signal connection overhead** — If states connect signals on `enter()` and disconnect on `exit()`, cache the signal objects rather than reconstructing them per transition if the target nodes are stable.

### Godot Anti-Patterns

**State data on the owning entity** — Placing charge timers, sub-phase counters, or mode-specific flags on the `CharacterBody2D` rather than in the state class recreates the boolean-flag problem. Every field used exclusively by one state belongs in that state object.

**Using `AnimationStateMachine` for game logic** — Driving gameplay decisions from `AnimationTree` transition conditions couples game logic to the animation layer. Drive the `AnimationTree` from state `enter()`/`exit()` callbacks; never reverse the dependency.

**Deep per-state inheritance** — Subclassing concrete states (`DuckingState extends StandingState`) to share behavior creates a brittle inheritance tree inside the FSM. Factor shared behavior into helper methods on the owning entity or a shared `RefCounted` utility object.

### GDScript Structural Example

```gdscript
# player_state.gd — RefCounted base; no SceneTree presence or lifecycle callbacks needed
class_name PlayerState
extends RefCounted

func enter(owner: CharacterBody2D) -> void: pass
func exit(owner: CharacterBody2D) -> void: pass
func handle_input(owner: CharacterBody2D, event: InputEvent) -> PlayerState: return null
func update(owner: CharacterBody2D, delta: float) -> PlayerState: return null
```

```gdscript
# player_fsm.gd — owns transition protocol; drives CharacterBody2D via parent reference
class_name PlayerFSM
extends Node

var _state: PlayerState = null

func _ready() -> void:
    _transition(StandingState.new())

func _unhandled_input(event: InputEvent) -> void:
    var next: PlayerState = _state.handle_input(_body(), event)
    if next:
        _transition(next)

func _physics_process(delta: float) -> void:
    var next: PlayerState = _state.update(_body(), delta)
    if next:
        _transition(next)

func _transition(to: PlayerState) -> void:
    if _state:
        _state.exit(_body())   # GC frees old state after this returns
    _state = to
    _state.enter(_body())

func _body() -> CharacterBody2D:
    return get_parent() as CharacterBody2D
```

```gdscript
# character_state.gd — Node base; use when states need _process, child nodes, or animations
class_name CharacterState
extends Node

func enter() -> void: pass
func exit() -> void: pass
# Subclasses override _process() / _physics_process() directly.
# NodeFSM calls set_process/set_physics_process(true/false) on every transition.
```

```gdscript
# node_fsm.gd — activates/deactivates child CharacterState nodes on transition
class_name NodeFSM
extends Node

var _current: CharacterState = null

func _ready() -> void:
    for child: Node in get_children():
        if child is CharacterState:
            child.set_process(false)
            child.set_physics_process(false)
    if get_child_count() > 0:
        transition_to(get_child(0).name)

func transition_to(state_name: StringName) -> void:
    if _current:
        _current.exit()
        _current.set_process(false)
        _current.set_physics_process(false)
    _current = get_node(NodePath(state_name)) as CharacterState
    _current.set_process(true)
    _current.set_physics_process(true)
    _current.enter()
```

### Related Patterns

Flyweight, Update Method, Type Object

### Competing Patterns

Enum + match, Behavior Tree, Type Object

### Key Implementation Notes

- Prefer stateless shared `RefCounted` state objects (allocated once, reused) for states with no per-FSM instance data; allocate new instances only when the state carries per-machine fields.
- GDScript reference counting replaces C++ deferred deletion; reassigning `_state` in `_transition()` is safe — the old object is freed after the calling method returns.
- Add `enter()` and `exit()` to the base class from the start; retrofitting them later requires touching every concrete state.
- For concurrent FSMs with interactions, cross-check the other FSM's current state type via `is` in the relevant state's `update()`; do not couple the two FSMs through shared overridden methods.
- Pushdown automaton: pop from the stack on any termination condition in the transient state's `handle_input()` or `update()` — no hardcoded "return to X" per source state is needed.
- `AnimationTree` with `AnimationStateMachine` handles animation-layer FSMs; script FSMs should drive `AnimationTree` transitions, not replace them.

---
