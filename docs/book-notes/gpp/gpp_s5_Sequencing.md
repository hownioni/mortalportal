## Double Buffer

### Core Intent

Maintain two copies of state — a readable current buffer and a writable next buffer — and swap them atomically once writing is complete so that readers always see a fully consistent snapshot.

### Problem It Solves

A reader and a writer sharing a single piece of state concurrently — whether a display scanout and the CPU, or actors reading each other's state mid-update — causes the reader to observe a partially-written, logically inconsistent snapshot. When update iteration order determines what each actor sees, simulation results become order-dependent.

### Engineering Motivation

Godot's GPU framebuffer and rendering thread separation are already Double Buffer implementations managed by the engine — you never write those yourself. The user-space case is actor simulation: when entities read each other's state in the same `_physics_process` pass, the first entity to update writes state that later entities read, making results iteration-order-dependent rather than logically simultaneous.

### When to Use

- Multiple simulation entities read each other's state during the same update phase and must all behave as if their updates happened simultaneously.
- A reader must never observe a partially-written state snapshot across a frame boundary.
- Custom simulation grids (cellular automata, fluid dynamics, contagion models) require each cell to read last frame's values while writing this frame's.

### When NOT to Use

- For GPU framebuffer rendering: Godot's `DisplayServer` and `RenderingServer` handle this entirely — never implement your own framebuffer buffering.
- When reads and writes occur in clearly separated, non-overlapping phases within one `_physics_process` call — explicit ordering removes the need for buffering entirely.
- When state is small and entities interact rarely — a two-phase explicit loop (all-update, then all-apply) is simpler and equivalent.

### Main Tradeoffs

| Benefit                                                                                   | Cost                                                                                                      |
| ----------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| All readers see a complete, consistent prior-frame snapshot regardless of iteration order | Requires 2× the memory of the buffered state                                                              |
| Eliminates update-ordering dependencies between actors in the same pass                   | Swap must occur at a well-defined boundary; code that reads between phases sees inconsistent state        |
| GDScript array reference swap is O(1) regardless of array size — no data copy needed      | Per-object distributed buffering requires two passes over all objects per frame                           |
| Encapsulates the concurrency contract inside the simulation type                          | Buffered state is one frame stale during the write phase; account for this in any incremental computation |

### Common Misuse

Applying per-object double buffering to state that is only ever read after the full update pass completes; a simpler explicit two-phase loop — all objects update, then all objects apply results — solves the same ordering problem with half the memory.

### Failure Mode

A system stores a direct reference into a buffer element across frames; after the swap, that reference now points into the write-side buffer being actively modified this frame, producing corrupted reads that only manifest under specific iteration orders and frame rates.

### Structural Model

```text
[GPU/display variant — fully handled by Godot; never implement yourself]

DisplayServer    ← window_set_vsync_mode() controls swap chain pacing
RenderingServer  ← runs on a dedicated thread; game logic and render state are buffer-separated
→ No user code involved. Do not attempt to manage framebuffer double buffering.

[Per-actor simulation variant — the only user-space case in Godot]

SimActor
    _current_<field>: T   ← read-only during the update pass
    _next_<field>: T      ← write-only during the update pass

SimStage._physics_process():
    Phase 1 — update all: actor.compute()
                          reads _current_*, writes _next_*  ← order-independent
    Phase 2 — swap all:   actor.swap()
                          _next_* → _current_*, _next_* reset  ← simultaneous promotion

[GDScript array reference swap — O(1), no data copy]
var tmp: PackedByteArray = _current
_current = _next   ← reference reassignment; no element copying
_next = tmp
```

### Godot Adaptation Notes

- Godot's `RenderingServer` runs on a dedicated thread with its own state buffer; the game logic thread and render thread are already double-buffered at the engine level. Do not replicate this.
- Physics interpolation (`ProjectSettings: physics/common/physics_interpolation`) eliminates the need to manually interpolate between physics frames for smooth visual rendering — the engine handles the buffer boundary between simulation state and visual position.
- GDScript array and `PackedByteArray` swaps are O(1) reference reassignments — swapping two large simulation grids costs the same as swapping two pointers.
- The "static index flip" trick from C++ (`current_ ^= 1`) is unnecessary in GDScript; swap the two container references directly.
- `call_deferred()` can implement a lightweight two-phase update without the full pattern: defer all state promotions to end-of-frame rather than managing explicit current/next fields.
- What is unchanged: the read-from-current / write-to-next / swap-at-boundary discipline — this is the invariant regardless of engine; violating it produces the ordering-dependent simulation bugs the pattern exists to prevent.

### Gameplay-Level Usage

Cellular automaton maps (spreading fire, pathogen propagation, influence fields) require each cell to read last frame's values while writing this frame's; double-buffering the grid array guarantees order-independent propagation. Turn-based simultaneous action resolution (all units commit actions simultaneously) uses per-unit double-buffered state to guarantee that a unit resolved earlier in the loop does not affect units resolved later in the same pass.

### Entity-Level Usage

An actor that can "stun" adjacent actors during the same update pass writes to `_next_stunned` and reads from `_current_stunned`; all stun effects become visible to all actors simultaneously at the frame boundary rather than propagating through the iteration order. Per-entity buffering is appropriate when the buffered state is small (one or two fields) and the interaction radius is local.

### Engine/System-Level Usage

A terrain modification system that allows players and explosions to alter tiles simultaneously in the same frame uses a double-buffered `PackedByteArray` grid managed by a single `SimStage` node. The stage's `_physics_process` runs the two-phase update and reference swap; no other system accesses the write buffer during the update pass.

### Suggested Script Layout

```text
res://systems/simulation/
    sim_stage.gd            # Node — two-phase update driver; owns _actors array
    sim_actor.gd            # Node — double-buffered state fields + swap()
res://simulations/
    life_simulation.gd      # Node — self-contained double-buffer grid (grid use case)
    influence_map.gd        # Node — double-buffered terrain influence field
```

### Godot Performance Notes

**Memory allocation patterns** — Pre-allocate both `_current` and `_next` buffers at `_ready()` time with a fixed size. The reference swap allocates nothing at runtime; `_next.resize()` during gameplay would defeat the benefit.

**Resource sharing vs. per-instance duplication** — Per-actor double buffering (two fields per actor) scales linearly with actor count. For dense grids, `PackedByteArray` is preferred over `Array[bool]` — it avoids GDScript object overhead per element and is contiguous in memory.

**SceneTree traversal cost** — The two-phase loop iterates `_actors` twice per `_physics_process` tick. Cache the array at `_ready()` rather than calling `get_children()` or `get_nodes_in_group()` each frame to avoid repeated SceneTree traversal.

**Node count implications** — The pattern requires no extra nodes; `SimStage` and `SimActor` fulfill the same roles as the existing world and actor nodes. The only overhead is the extra buffered field(s) per actor.

### Godot Anti-Patterns

**Implementing framebuffer double buffering** — Writing custom pixel buffer swap logic when Godot's `RenderingServer` and `DisplayServer` already handle GPU swap chains. Never replicate engine-level rendering infrastructure in GDScript.

**Reading from `_next_` during the update pass** — Any code that reads `_next_<field>` during Phase 1 sees a partially-written state that varies by iteration order. Only `_current_<field>` is valid for reading during the update phase.

**Storing direct references into buffer elements** — Caching a reference to an element inside `_current` or `_next` across a swap invalidates the reference; always re-fetch through the container after each swap.

### GDScript Structural Example

```gdscript
# life_simulation.gd — canonical double-buffer use case: read _current, write _next, swap
class_name LifeSimulation
extends Node

const GRID_W: int = 64
const GRID_H: int = 64

var _current: PackedByteArray
var _next: PackedByteArray

func _ready() -> void:
    _current = PackedByteArray()
    _current.resize(GRID_W * GRID_H)
    _next = _current.duplicate()
    for i: int in _current.size():
        _current[i] = 1 if randf() < 0.3 else 0

func _physics_process(_delta: float) -> void:
    _step()                               # reads _current only, writes _next only
    var tmp: PackedByteArray = _current   # O(1) reference swap — no data copy
    _current = _next
    _next = tmp

func _step() -> void:
    for i: int in _current.size():
        var x: int = i % GRID_W
        var y: int = i / GRID_W
        var n: int = _count_neighbors(x, y)
        var alive: bool = _current[i] == 1
        _next[i] = 1 if (alive and n in [2, 3]) or (not alive and n == 3) else 0

func _count_neighbors(x: int, y: int) -> int:
    var n: int = 0
    for dy: int in range(-1, 2):
        for dx: int in range(-1, 2):
            if dx == 0 and dy == 0:
                continue
            n += _current[((y + dy) % GRID_H) * GRID_W + ((x + dx) % GRID_W)]
    return n
```

### Related Patterns

Update Method, Game Loop

### Competing Patterns

Two-phase explicit ordering (all-write then all-read with single buffer), `call_deferred()` for end-of-frame state promotion

### Key Implementation Notes

- Never implement GPU framebuffer buffering; Godot's `RenderingServer` and `DisplayServer` own that layer.
- GDScript array and `PackedByteArray` reference swaps are O(1); prefer them over element-by-element copy or index tricks.
- Phase discipline is the invariant: reads from `_current_*` only; writes to `_next_*` only; swap at a single well-defined boundary per frame.
- For very small buffered state (one or two booleans per actor), consider `call_deferred("_apply_next_state")` as a lightweight alternative to managing explicit current/next fields.
- Pre-size both buffers at load time; never resize during gameplay.
- Physics interpolation in ProjectSettings eliminates the need to double-buffer visual position for smooth rendering between physics ticks.

---

## Game Loop

### Core Intent

Process user input without blocking, update game state, and render each frame in a continuous loop that controls game-time progression independently of hardware speed.

### Problem It Solves

A blocking event loop that waits for user input cannot drive continuous animation, physics, or AI. Without explicit time-step management, game speed scales with CPU clock, making behavior vary across hardware and preventing deterministic multiplayer simulation.

### Engineering Motivation

Godot owns the game loop entirely; you never write it. The loop calls `_unhandled_input`, `_physics_process`, and `_process` on every node in the SceneTree each frame. The relevant engineering question in Godot is not how to implement the loop but how to correctly partition code across its three phases — particularly keeping deterministic simulation in the fixed-rate phase and visual updates in the variable-rate phase.

### When to Use

- Always — every `Node` that overrides `_process`, `_physics_process`, or `_unhandled_input` participates in the loop automatically.
- Put all deterministic simulation (movement, physics, combat, AI) in `_physics_process`; its `delta` is constant.
- Put all visual-only updates (animations, particles, shader uniforms, UI feedback) in `_process`; its `delta` reflects actual elapsed time.
- Use `_unhandled_input` or `_input` for event-driven non-blocking input consumption.

### When NOT to Use

- Never write a manual `while true` loop inside a Node callback; the engine loop is already running and a nested blocking loop will stall the OS event pump.
- Never run physics simulation in `_process`; its `delta` is variable, making simulation results frame-rate-dependent and non-deterministic.
- For non-real-time batch processing (offline export, headless simulation), use a `Thread` rather than abusing `_process` as a step function.

### Main Tradeoffs

| Benefit                                                                                      | Cost                                                                                                              |
| -------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| `_physics_process` runs at a fixed timestep — deterministic, hardware-independent simulation | `_process` delta varies; visual code that mixes simulation assumptions with render code breaks at low frame rates |
| `Engine.max_physics_steps_per_frame` prevents the spiral of death with a built-in cap        | Capped catch-up means simulation time can lag real time on pathologically slow hardware                           |
| Physics interpolation via ProjectSettings eliminates manual render-interpolation code        | Interpolation introduces one physics tick of visual latency; may require tuning for fast-paced games              |
| Godot polls platform events internally — no manual OS event pump required                    | `_process` may be dropped on heavy frames; code that assumes `_process` fires every tick is incorrect             |

### Common Misuse

Using `_process` for physics and networked simulation: `delta` is variable and non-deterministic, causing simulation divergence between fast and slow machines and breaking replay and multiplayer consistency.

### Failure Mode

Simulation state is written from both `_process` and `_physics_process`; at high frame rates `_process` runs multiple times per physics tick, writing state the physics tick then overwrites mid-frame, producing visually inconsistent behavior that only manifests at specific frame rate / physics rate ratios.

### Structural Model

```text
[Godot owns the loop; user code runs from callbacks]

OS / Platform
    ↓ (Godot handles platform event polling internally)
Godot Engine
    │
    ├── _unhandled_input(event: InputEvent)
    │       ← non-blocking event consume; equivalent to processInput()
    │       ← fires when no other node consumed the event
    │
    ├── [physics tick — fixed rate]
    │   _physics_process(delta: float)
    │       delta = 1.0 / ProjectSettings.physics_ticks_per_second  (const ~0.01667s at 60 Hz)
    │       ← deterministic update: movement, AI, combat, networked state
    │       ← Engine.max_physics_steps_per_frame (default 8) caps spiral-of-death
    │
    └── [render frame — variable rate]
        _process(delta: float)
            delta = real elapsed time since last frame  (varies)
            ← visual-only: animations, particles, shader uniforms, UI
            ← may fire multiple times per physics tick, or be skipped under heavy load

[Spiral-of-death guard — built into Godot]
Engine.max_physics_steps_per_frame = 8  (default)
    → if one frame takes longer than 8 physics ticks to render,
      simulation time lags real time rather than running infinite catch-up updates.

[ProjectSettings — configure the loop here, not in code]
    physics/common/physics_ticks_per_second        → fixed timestep rate
    physics/common/max_physics_steps_per_frame     → catch-up cap
    application/run/max_fps                        → render rate cap (0 = uncapped)
    physics/common/physics_interpolation           → automatic visual interpolation
```

### Godot Adaptation Notes

- Godot owns the loop; implementing a custom `while true` game loop is never correct for real-time nodes.
- `_physics_process` IS the fixed-timestep update loop — its `delta` is constant and equal to `1.0 / physics_ticks_per_second`; never clamp or modify it inside the callback.
- `_process` IS the variable-render callback — clamp its `delta` in visual-only code to guard against hitches: `var safe_delta: float = minf(delta, 1.0 / 20.0)`.
- The spiral-of-death guard (`Engine.max_physics_steps_per_frame`) is configured in ProjectSettings, not in code; the default of 8 is appropriate for most games.
- Physics interpolation (`ProjectSettings: physics/common/physics_interpolation`) eliminates manual `lag / timestep` interpolation for `Node2D` and `Node3D` positions — enable it before writing manual interpolation.
- `Engine.time_scale` scales all `delta` values globally; set it outside loop callbacks, never inside `_physics_process`.
- Platform event loop integration is automatic; Godot calls the OS event pump internally each frame — no manual yield or poll is required.

### Gameplay-Level Usage

A game-wide pause system sets `get_tree().paused = true`; all nodes with `process_mode = PROCESS_MODE_PAUSABLE` (the default) stop receiving `_process` and `_physics_process` callbacks, while nodes with `PROCESS_MODE_WHEN_PAUSED` (pause menus, audio fades) continue. Time manipulation (`Engine.time_scale`) scales all physics and process deltas uniformly for slow-motion effects without modifying any simulation code.

### Entity-Level Usage

Each game entity inherits from `CharacterBody2D`, `Area2D`, or `Node` and overrides `_physics_process` for movement and AI, `_process` for animations and visual feedback, and `_unhandled_input` for player-controlled input. No entity needs to call anything to participate in the loop — SceneTree membership is sufficient.

### Engine/System-Level Usage

ProjectSettings governs all loop parameters; the only code-level loop configuration is `Engine.max_physics_steps_per_frame` and `Engine.physics_ticks_per_second` for runtime overrides (e.g., headless dedicated server running at a different tick rate than the client). A `DebugOverlay` Autoload reads `Engine.get_frames_per_second()` and `Performance.get_monitor(MONITOR_*)` in `_process` for profiling without coupling to any game system.

### Suggested Script Layout

```text
# No loop implementation files — Godot owns the loop.
# Loop configuration lives in project.godot (ProjectSettings).

res://entities/
    player.gd               # CharacterBody2D — correct _process/_physics_process separation
res://autoloads/
    debug_overlay.gd        # Autoload — reads Engine / Performance monitors in _process
res://systems/
    time_manager.gd         # Node — sets Engine.time_scale for slow-motion; never runs in-loop
```

### Godot Performance Notes

**Frame-time stability** — `_physics_process` delta is constant by design; frame spikes manifest as `_process` running multiple times per physics tick (or not at all), not as physics instability. Monitor `Performance.TIME_PROCESS` and `TIME_PHYSICS_PROCESS` separately.

**SceneTree traversal cost** — Every Node in the SceneTree with `_process` or `_physics_process` overridden adds one callback per frame. Disable processing on Nodes that do not require per-frame callbacks: `set_process(false)` and `set_physics_process(false)` at `_ready()` if the Node only reacts to signals or direct calls.

**Node count implications** — Each active Node with a processing callback contributes to per-frame SceneTree overhead. For systems with hundreds of uniform entities, prefer a single system Node with a typed `Array` over individual per-entity `_physics_process` callbacks.

### Godot Anti-Patterns

**Simulation in `_process`** — Writing physics, AI pathfinding, or combat resolution in `_process` makes simulation frame-rate-dependent. All deterministic state must live exclusively in `_physics_process`.

**Manual OS event pump** — Adding `OS.delay_msec()` or any blocking call inside a loop callback to control frame rate stalls the engine's own event pump, causing the OS to mark the window unresponsive. Use `Engine.max_fps` via ProjectSettings or `Engine.physics_ticks_per_second` for rate control.

**Runtime ProjectSettings writes per frame** — Calling `ProjectSettings.set_setting()` inside `_process` to tune loop parameters is both incorrect and expensive; configure at startup or use `Engine` properties for runtime adjustments.

### GDScript Structural Example

```gdscript
# player.gd — demonstrates correct loop-phase separation; all three phases with real logic
class_name Player
extends CharacterBody2D

# Loop configuration (ProjectSettings, not code):
#   physics/common/physics_ticks_per_second = 60       → _physics_process rate
#   physics/common/max_physics_steps_per_frame = 8     → spiral-of-death guard
#   physics/common/physics_interpolation = true        → eliminates manual interpolation

const SPEED: float = 200.0
const JUMP_VELOCITY: float = -500.0
var _jump_buffered: bool = false

func _unhandled_input(event: InputEvent) -> void:
    # Phase 1 — Input: non-blocking event consume; equivalent to processInput().
    if event.is_action_pressed(&"jump"):
        _jump_buffered = true

func _physics_process(delta: float) -> void:
    # Phase 2 — Update (fixed rate, deterministic): all simulation state written here only.
    # delta = 1.0 / physics_ticks_per_second; do NOT clamp or modify it.
    if not is_on_floor():
        velocity += get_gravity() * delta

    if _jump_buffered and is_on_floor():
        velocity.y = JUMP_VELOCITY
        _jump_buffered = false

    var dir: float = Input.get_axis(&"move_left", &"move_right")
    velocity.x = dir * SPEED
    move_and_slide()

func _process(delta: float) -> void:
    # Phase 3 — Render (variable rate): visual-only; never write simulation state here.
    var _safe_delta: float = minf(delta, 1.0 / 20.0)  # guard against hitches in visual code
    $Sprite2D.flip_h = velocity.x < -0.1
    $AnimationPlayer.play(
        &"jump" if not is_on_floor() else
        &"run"  if absf(velocity.x) > 1.0 else
        &"idle"
    )
```

### Related Patterns

Update Method, Double Buffer, Event Queue

### Competing Patterns

Platform Event Loop (when the platform owns the loop), Thread-per-system with shared clock

### Key Implementation Notes

- `_physics_process` IS the fixed-timestep update; `_process` IS the variable-render callback — never reverse this assignment.
- Never clamp `_physics_process` delta; it is already constant. Clamp `_process` delta for visual-only code.
- Configure `physics/common/physics_interpolation = true` before writing any manual position interpolation between physics frames.
- `Engine.max_physics_steps_per_frame` is the spiral-of-death guard; 8 is appropriate for most games; headless servers may raise it for catchup simulation.
- `get_tree().paused` and `process_mode` gate `_process`/`_physics_process` per-node; this is the correct mechanism for pause, not a manual `is_paused` flag checked inside callbacks.
- Never call `OS.delay_msec()` or any blocking call inside a Node callback.

---

## Update Method

### Core Intent

Give each game object a method called once per frame by the game loop, encapsulating that object's per-frame behavior so the loop need not know the concrete type of any entity.

### Problem It Solves

Placing each entity's frame behavior directly in the game loop produces a tangle of intermixed update logic and per-entity variables as entity count grows, making the loop unmaintainable and blocking dynamic entity addition or removal. Per-frame behavioral code written as straight-line logic cannot yield mid-execution; behavior must be decomposed into single-frame slices with state persisted in fields.

### Engineering Motivation

In Godot, `_process(delta)` and `_physics_process(delta)` ARE the Update Method — every `Node` in the SceneTree receives these callbacks each frame without any manual registration or loop management. The SceneTree replaces the manual entities array and the iteration loop; the engine handles mid-frame addition and removal safety automatically.

### When to Use

- Any entity needs to execute continuous per-frame behavior — override `_physics_process` or `_process` directly.
- Per-entity behavior should be selectively activated and deactivated at runtime — use `set_process(bool)` and `set_physics_process(bool)`.
- Entities must respect pause state — configure `process_mode` per node (`PAUSABLE`, `WHEN_PAUSED`, `ALWAYS`, `DISABLED`, `INHERIT`).
- A subset of entities needs to be updated as a batch — use groups and iterate `get_nodes_in_group()` from a system node.

### When NOT to Use

- Turn-based entities that only act when explicitly commanded — disable `_process` and `_physics_process`; call their methods directly when a turn fires.
- The entity count and update cost are large enough to make per-entity SceneTree callbacks a measurable bottleneck — use a single system node with a typed `Array` and one `_physics_process` loop.
- Behavioral logic is complex enough that frame-slicing produces unmanageable per-frame state — use `await` with coroutines to write straight-line logic that spans multiple frames.

### Main Tradeoffs

| Benefit                                                                                   | Cost                                                                                                                         |
| ----------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| Entities register automatically with SceneTree membership — no manual array management    | `process_priority` and tree order determine execution sequence; implicit ordering requires care for state dependencies       |
| `set_process(false)` deactivates any node instantly with zero loop overhead               | Disabled nodes still occupy SceneTree memory and are traversed during tree operations                                        |
| `queue_free()` is deferred to end-of-frame — calling it inside `_physics_process` is safe | Mid-frame `add_child()` defers the child's first callback to next frame — a child added this frame is not updated this frame |
| `process_mode` encodes pause behavior per-node without manual flag checks                 | `PROCESS_MODE_INHERIT` means children silently inherit an ancestor's mode — unexpected behavior when the tree is deep        |

### Common Misuse

Placing `_process` or `_physics_process` overrides on a base entity class and building a deep subclass hierarchy to vary behavior per entity type — the Component pattern (child nodes with their own `_physics_process`) solves this more cleanly and avoids the brittle base class problem.

### Failure Mode

A system iterates `get_children()` or `get_nodes_in_group()` and calls `queue_free()` on entries during the iteration; while `queue_free()` is deferred, modifying the group membership mid-loop can produce skipped or double-processed entries depending on group query caching.

### Structural Model

```text
[SceneTree as automatic Update Method driver]

SceneTree
    _physics_process(delta) called every physics tick (60 Hz default)
    _process(delta) called every rendered frame (variable)
    ↓
Root (Node)
    ├── Enemy_01 (CharacterBody2D)    _physics_process → patrol, attack
    │   ├── PatrolComponent (Node)    _physics_process → movement logic
    │   └── HealthBar (CanvasItem)    _process         → visual update only
    ├── Enemy_02 (CharacterBody2D)    _physics_process → patrol, attack
    └── Player (CharacterBody2D)      _physics_process → input, movement

[Mid-frame safety — built into SceneTree]
    add_child(new_entity)       → first callback fires next frame (safe)
    queue_free(entity)          → freed at end of frame, not during iteration (safe)
    set_physics_process(false)  → callback removed immediately, no skipped work

[Per-entity control]
    set_process(bool)                  → enable/disable _process
    set_physics_process(bool)          → enable/disable _physics_process
    process_mode = PROCESS_MODE_*      → governs pause behavior
    process_priority: int              → lower value = earlier execution (default 0)

[Group-based batch update]
    get_tree().get_nodes_in_group(&"enemies")  → typed subset iteration
    → system node iterates; individual entities do not need _physics_process
```

### Godot Adaptation Notes

- `_process(delta)` and `_physics_process(delta)` ARE the Update Method; no registration, no manual loop, no virtual dispatch overhead beyond the engine's own node dispatch.
- SceneTree membership IS entity registration; `add_child()` registers and `queue_free()` deregisters — the "manual entity array" from C++ does not exist.
- `set_process(false)` and `set_physics_process(false)` are the Godot equivalents of removing an entity from the update array; they incur no iteration cost for the disabled node.
- `process_priority` sets execution order within a processing group; lower values execute earlier. Use it to enforce update-order dependencies instead of structuring scene trees for implicit ordering.
- `process_mode = PROCESS_MODE_DISABLED` propagates to children via `PROCESS_MODE_INHERIT` — setting it on a parent disables all descendants simultaneously without iterating them individually.
- Component behavior via child Nodes: each child can have its own `_physics_process`, owning one domain of behavior (patrol, health, weapon). SceneTree calls each independently — no "super-update" is needed on the parent.
- For large entity counts (hundreds of enemies) where per-entity SceneTree callback overhead is measurable, move to a system node pattern: one `EnemySystem` node with a typed `Array[EnemyData]` and one `_physics_process` loop.

### Gameplay-Level Usage

An `EnemySystem` node manages all enemies via a group; it enables or disables batch processing on all enemies when combat state changes without requiring each enemy to listen for a game-phase signal. A turn resolution system iterates a typed array of `Unit` nodes in `_physics_process`, calling `unit.execute_action()` and disabling the unit's own `_physics_process` once its turn is complete.

### Entity-Level Usage

A `PatrolComponent` node is a child of `Enemy`; it overrides `_physics_process` and drives `get_parent() as CharacterBody2D` velocity and `move_and_slide()`. The `Enemy` node itself owns only cross-component state (current health, faction); all behavioral processing lives in child component nodes. Calling `set_physics_process(false)` on `Enemy` propagates via `PROCESS_MODE_INHERIT` to all components simultaneously.

### Engine/System-Level Usage

A `CullSystem` node queries `get_nodes_in_group(&"enemies")` each physics tick and calls `set_physics_process()` based on distance to the camera, ensuring only on-screen entities pay update cost. A `WaveManager` node activates and deactivates enemy groups by calling `set_physics_process()` on the group root node, propagating the change to all children at once.

### Suggested Script Layout

```text
res://entities/enemy/
    enemy.gd                # CharacterBody2D — cross-component state, thin _physics_process
    enemy.tscn              # Enemy ▶ PatrolComponent, HealthComponent, WeaponComponent
    components/
        patrol_component.gd     # Node — owns patrol _physics_process
        health_component.gd     # Node — signal emitter, no processing needed
        weapon_component.gd     # Node — attack logic _physics_process
res://systems/
    enemy_system.gd         # Node — group-based batch management, culling
    cull_system.gd          # Node — distance-based process enable/disable
```

### Godot Performance Notes

**SceneTree traversal cost** — `get_nodes_in_group()` traverses the group registry each call; cache the result in a typed `Array` at startup if the group membership is stable and the call is inside `_physics_process`. For dynamic membership (enemies spawning and dying), re-cache on membership change events rather than calling `get_nodes_in_group()` every tick.

**Node count implications** — Each Node with an active `_process` or `_physics_process` override contributes to per-frame SceneTree callback overhead. At several hundred entities, replacing individual `_physics_process` callbacks with a single system node iterating a typed `Array` measurably reduces overhead by eliminating per-node dispatch indirection.

**Typed vs. untyped Array performance** — `Array[EnemyData]` (typed) avoids per-element type coercion during iteration. Use typed arrays in any system node that iterates entities in `_physics_process`.

**Signal connection overhead** — Components that emit signals in `_physics_process` on every tick (e.g., `position_updated`) accumulate O(n) signal dispatch cost per frame per receiver. Throttle high-frequency signals or replace them with direct method calls for in-scene component communication.

### Godot Anti-Patterns

**`get_children()` in `_physics_process`** — Calling `get_children()` inside a per-frame callback to iterate components rebuilds the array every tick. Cache child references at `_ready()` in a typed `Array`; access them directly per frame.

**Deep entity subclass hierarchy** — Placing `_physics_process` on a `BaseEnemy` and subclassing `MeleeEnemy`, `RangedEnemy`, and `FlyingEnemy` creates a brittle inheritance tree. Use child `Node` components with their own `_physics_process` instead; behavior composes at the scene level.

**`set_process` inside `_physics_process` as a state flag** — Using `set_physics_process(false)` mid-callback to "skip the next tick" is an implicit state pattern that obscures control flow. Use explicit state variables or a proper State machine for mode-dependent behavior.

### GDScript Structural Example

```gdscript
# patrol_component.gd — Node component; owns its own _physics_process, decoupled from entity
class_name PatrolComponent
extends Node

@export var speed: float = 80.0
@export var patrol_range: float = 120.0

var _origin: Vector2 = Vector2.ZERO
var _direction: float = 1.0

func _ready() -> void:
    _origin = (get_parent() as CharacterBody2D).global_position

func _physics_process(_delta: float) -> void:
    var body: CharacterBody2D = get_parent() as CharacterBody2D
    body.velocity.x = speed * _direction
    if absf(body.global_position.x - _origin.x) >= patrol_range:
        _direction = -_direction
    body.move_and_slide()

# Pause this component only:     set_physics_process(false)
# Pause entity + all components: enemy_node.process_mode = PROCESS_MODE_DISABLED
```

```gdscript
# enemy_system.gd — group-based batch lifecycle management; no per-entity loop needed
class_name EnemySystem
extends Node

func activate_wave() -> void:
    _set_enemies_active(true)

func deactivate_wave() -> void:
    _set_enemies_active(false)

func cull_by_distance(player_pos: Vector2, active_radius: float) -> void:
    for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
        var in_range: bool = (enemy as Node2D).global_position.distance_to(player_pos) <= active_radius
        enemy.set_physics_process(in_range)

func _set_enemies_active(enabled: bool) -> void:
    for enemy: Node in get_tree().get_nodes_in_group(&"enemies"):
        enemy.set_process(enabled)
        enemy.set_physics_process(enabled)
```

### Related Patterns

Game Loop, Component, State, Data Locality

### Competing Patterns

Component with system-level iteration, Coroutines / `await` for multi-frame straight-line behavior

### Key Implementation Notes

- `_physics_process` and `_process` ARE the Update Method; no custom framework or virtual dispatch layer is needed.
- `set_physics_process(false)` is O(1) and removes the node from the callback list immediately — use it freely for inactive entities.
- Cache `get_nodes_in_group()` results in a typed `Array` if the group is stable; do not call it every `_physics_process` tick for large groups.
- Use `process_priority` to enforce cross-entity update ordering rather than relying on tree insertion order or scene structure.
- `queue_free()` inside `_physics_process` is safe; the engine defers freeing to end-of-frame. Never call `free()` directly inside a callback.
- Child nodes added via `add_child()` during `_physics_process` receive their first callback on the next frame — design spawned entities to tolerate a one-frame initialization delay.
- For entity counts above a few hundred, prefer one system node iterating a typed `Array` over individual per-entity `_physics_process` overrides.

---
