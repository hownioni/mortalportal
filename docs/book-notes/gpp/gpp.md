# Game Programming Patterns — Architecture Reference

> Robert Nystrom | gameprogrammingpatterns.com
> Distilled for AI coding agent context (Claude Code)

---

## Section 1: Quick-Reference Pattern Matrix

| Symptom / Situation                         | Recommended Pattern | Why It Works                    | Main Tradeoff                          | Complexity | Chapter |
| ------------------------------------------- | ------------------- | ------------------------------- | -------------------------------------- | ---------- | ------- |
| Input bindings hard-coded, can't remap      | Command             | Action is swappable object      | Indirection per input event            | Low        | 2       |
| Need undo/redo or match replay              | Command             | Command stores prior state      | All mutations must route through       | Medium     | 2       |
| Thousands of objects share static data      | Flyweight           | Shared intrinsic state pointer  | Intrinsic/extrinsic state split        | Medium     | 3       |
| System A couples directly to system B       | Observer            | Indirect notification list      | Implicit, hard-to-trace control flow   | Low        | 4       |
| Spawner tightly coupled to entity type      | Prototype           | Clone existing instance         | Shallow vs. deep copy ambiguity        | Low        | 5       |
| Need single shared instance everywhere      | Singleton           | One global access point         | Global state, untestable               | Low        | 6       |
| Multiple exclusive behaviors per entity     | State               | Explicit FSM transitions        | State explosion at scale               | Medium     | 7       |
| Render buffer visible mid-write             | Double Buffer       | Swap complete frames atomically | Double memory cost                     | Medium     | 8       |
| Game speed tied to processor clock          | Game Loop           | Fixed-timestep decoupled loop   | Platform event-loop coordination       | Medium     | 9       |
| Update logic scattered across entity class  | Update Method       | Per-object frame-slice call     | Update ordering dependencies           | Low        | 10      |
| Designer-authored behavior unsafe in engine | Bytecode            | Sandboxed VM instructions       | VM maintenance and interpreter cost    | High       | 11      |
| Many subclasses reach into engine directly  | Subclass Sandbox    | Protected base operations only  | Brittle base class; accretion risk     | Medium     | 12      |
| New content types require recompile         | Type Object         | Instance represents a type      | Manual type lifetime management        | Medium     | 13      |
| Entity class spans physics, render, AI      | Component           | Decoupled domain components     | Wiring complexity, pointer indirection | High       | 14      |
| Synchronous event blocks sending system     | Event Queue         | Buffers events for later pull   | Feedback loops, dropped requests       | High       | 15      |
| Global service hides real dependencies      | Service Locator     | Abstract service behind locator | Harder to trace actual provider        | Medium     | 16      |
| Hot-path suffering cache misses             | Data Locality       | Contiguous array data layout    | Inflexible, less OOP-friendly          | High       | 17      |
| Derived data recomputed every frame         | Dirty Flag          | Mark-dirty, lazy recompute      | Deferred cost hits at access time      | Low        | 18      |
| Heap alloc/free during gameplay frame       | Object Pool         | Pre-allocated fixed reuse pool  | Fixed capacity; wasted if oversized    | Medium     | 19      |
| Proximity queries scan all objects          | Spatial Partition   | Spatial data structure index    | Update cost for moving objects         | High       | 20      |

---

## Section 2: Core Architectural Philosophy

### Decoupling vs. Complexity

- Abstraction cost is justified when two pieces change independently at different rates, and a change to one would otherwise cascade into the other; decouple to localize future changes.
- Prefer direct coupling when both sides change together, the codebase is small, or the indirection conceals program structure without delivering a concrete flexibility benefit.

### Composition vs. Inheritance

- Prefer composition (Component pattern) when an entity spans multiple independent domains, when behavior must be assembled at runtime, or when the inheritance tree is growing wide rather than deep.
- Inheritance becomes harmful when base classes accumulate methods to satisfy diverse subclasses, creating the brittle base class problem where any base change risks breaking all derived classes simultaneously.

### Global State Management

- Unrestricted global access (Singleton, raw globals) makes code hard to reason about, encourages unintended coupling across distant systems, and creates race conditions in multi-threaded engines.
- Mediate necessary global access through Service Locator (which abstracts the provider and supports null objects) or pass dependencies explicitly; limit access scope to the minimum set of callers that genuinely need it.

### Performance-Aware Architecture

- Game loops, entity update paths, and particle/physics systems are hot paths where cache miss rates, per-frame heap allocation, and virtual dispatch overhead directly determine frame stability; treat these differently from cold paths.
- Let profiler data drive optimization decisions: premature abstraction that fragments data in memory or adds pointer indirection in tight loops can cost more performance than the design flexibility gains are worth.

### Pragmatism Over Purity

- Architectural cleanliness should yield when code is explicitly prototypal and intended to be discarded, or when the time cost of getting architecture right exceeds the shipping deadline's tolerance.
- "Good enough" means the minimum structure that lets the current work proceed without creating irreversible technical debt; the threshold is whether the team can still freely change the affected code next week without heroics.

---

## Section 3: Engine-Level Constraints

### Variant Boxing Overhead

**Why it matters** — Untyped GDScript variables wrap every value in a `Variant`, adding boxing and unboxing cost on every access; strict static typing eliminates this overhead entirely on the affected lines.

**Architectural consequences**

- Declare all variables, parameters, and return types with explicit types; `var x: float` is zero-overhead whereas `var x` boxes every assignment into a Variant and unboxes it on every read.
- `Packed*Array` types (`PackedFloat32Array`, `PackedVector2Array`, `PackedInt32Array`) store contiguous C-level data with no per-element Variant overhead; prefer them over `Array[float]` in any loop that runs each frame.
- Untyped collections in system-level code are the primary low-effort performance regression source; audit all hot-path `Array` accesses for missing type annotations before any other optimization.

**Patterns influenced** — Data Locality, Object Pool, Spatial Partition, Update Method

---

### SceneTree Traversal Cost

**Why it matters** — `get_node()`, `find_child()`, and `get_nodes_in_group()` are O(n) tree operations that accumulate significant cost when called inside per-frame callbacks.

**Architectural consequences**

- Cache all Node references in `@onready` fields during `_ready()`; never call `get_node()` or `$path` syntax from within `_physics_process` or `_process`.
- `get_nodes_in_group()` traverses the group registry on every call; cache the result in a typed `Array` when group membership is stable across frames.
- System-node patterns with pre-cached typed arrays eliminate per-frame traversal entirely and are preferable to ad-hoc SceneTree queries in any hot path.

**Patterns influenced** — Component, Update Method, Spatial Partition, Observer

---

### Process Scheduling and Frame-time Stability

**Why it matters** — `_physics_process` runs at a fixed timestep while `_process` runs at variable render rate; simulation logic placed in the wrong callback produces frame-rate-dependent behavior.

**Architectural consequences**

- All deterministic simulation — movement, physics, AI decisions, combat resolution, networked state — must run exclusively in `_physics_process`; `_process` is reserved for visual-only updates.
- `Engine.max_physics_steps_per_frame` caps the spiral-of-death catch-up limit; configure it in `ProjectSettings` so loop parameters are auditable alongside other project settings.
- `call_deferred()` delivers a call at end-of-frame and is the correct bridge between physics-step writes and render-frame reads without introducing cross-callback state mutations.

**Patterns influenced** — Game Loop, Update Method, Double Buffer, State, Observer

---

### Signal Execution Model

**Why it matters** — Signals execute synchronously in call-stack order by default; a signal emitted mid-physics-step runs its handler immediately, potentially mutating shared state inside the caller's own execution frame.

**Architectural consequences**

- Use `signal.emit.call_deferred(args)` when a handler must not mutate state until the current step is fully resolved; synchronous emission is correct only when the handler has no side effects on the emitter's state.
- Signal cycles (A emits → B handler emits → A handler) do not stack-overflow; they silently loop across frames and accumulate side effects that are nearly impossible to trace without explicit cycle detection.
- Keep signal fan-out bounded and document any signal chain that crosses subsystem boundaries; deeply wired signal graphs make execution order opaque to both developers and tooling.

**Patterns influenced** — Observer, Event Queue, Command, State, Component

---

### Object Lifetime and Deferred Deletion

**Why it matters** — `queue_free()` schedules Node deletion at end-of-frame rather than immediately; any code path that accesses a queued-free Node within the same frame raises errors.

**Architectural consequences**

- Guard all Node accesses from deferred callbacks, signal handlers, or worker thread results with `is_instance_valid()` when the Node may have been freed during the current frame.
- `RefCounted` objects are freed when their last reference drops to zero with no deferred window; use typed variables to retain references and prevent premature collection through unintentional reference loss.
- Object Pool patterns avoid `queue_free()` entirely by toggling `process_mode = PROCESS_MODE_DISABLED` instead of freeing; this eliminates the deferred-deletion window and keeps nodes in a predictable, re-acquirable state.

**Patterns influenced** — Object Pool, Observer, Component, Command, Service Locator

---

### Ownership and Resource Sharing

**Why it matters** — `Resource` objects are shared references by default; assigning one to two Nodes gives both the same object, and a mutation from either propagates silently to the other.

**Architectural consequences**

- Call `resource.duplicate(true)` on any Resource that holds per-instance mutable state before assigning it to a Node that will modify it; the default reference assignment is correct only for read-only or intentionally shared data.
- A Node's SceneTree ownership is determined by the parent it was added to via `add_child()`; transferring ownership requires `reparent()` or an explicit `remove_child()` followed by `add_child()` on the new owner.
- `@export` Resource fields are shared references in the Inspector; per-scene variants require saving separate `.tres` files rather than relying on a startup `duplicate()` call that may be missed during hot-reload.

**Patterns influenced** — Flyweight, Type Object, Prototype, Service Locator, Component

---

### Node Count Overhead

**Why it matters** — Every Node registered in the SceneTree carries maintenance cost across the physics server, rendering server, and tree traversal; unnecessary nodes degrade performance at scale.

**Architectural consequences**

- Use `RefCounted` or `Resource` for data-only and behavior-only structures; promote to `Node` only when `_process` callbacks, SceneTree signals, or SceneTree lifecycle are genuinely required.
- Disabled nodes with `PROCESS_MODE_DISABLED` are still traversed in tree operations like `find_children()` and group queries; minimize the count of permanently disabled nodes in live scene trees.
- Flat scene hierarchies outperform deep ones; each additional nesting level multiplies the traversal cost of any tree operation performed on or below that level.

**Patterns influenced** — Component, Object Pool, Data Locality, Update Method, Type Object

---

### PackedScene Instancing Cost

**Why it matters** — `PackedScene.instantiate()` parses the full node tree and runs all `_init()` and `_ready()` callbacks; repeated calls during gameplay frames produce measurable frame-time spikes.

**Architectural consequences**

- Pre-instantiate high-frequency objects — projectiles, enemies, effects — during the loading screen and manage them through an Object Pool that reactivates dormant instances via `process_mode` toggling rather than spawning new ones.
- `PackedScene.instantiate()` must not appear in `_physics_process` for any object type that spawns at more than a few instances per frame; front-load all instantiation to level load.
- Each instance inherits shared `Resource` references from the source scene; call `resource.duplicate(true)` explicitly for any Resource that must hold per-instance mutable state, otherwise all instances share one object.

**Patterns influenced** — Object Pool, Prototype, Flyweight, Component

---

### GDScript Interpretation Overhead

**Why it matters** — GDScript is interpreted at runtime; tight loops and math-heavy operations are significantly slower than equivalent GDExtension C or Rust code, and no GDScript-level restructuring eliminates this gap.

**Architectural consequences**

- Use the Godot profiler (`Debugger → Profiler`) to confirm that a specific loop is the frame-time bottleneck before any structural refactor; the profiler reports per-function GDScript time and reveals whether the cost is loop iteration or called functions.
- Replace only the profiler-confirmed hot path with a GDExtension module; orchestration, configuration, and cold-path logic should remain in GDScript where iteration speed is higher.
- System-node patterns that run one GDScript loop over pre-allocated typed arrays reduce per-call dispatch overhead relative to per-entity `_physics_process` overrides and are the recommended intermediate step before reaching for GDExtension.

**Patterns influenced** — Data Locality, Update Method, Spatial Partition, Object Pool

---

### Data Access Patterns

**Why it matters** — GDScript cannot control heap object layout, but the choice between `Packed*Array`, typed `Array`, untyped `Array`, and direct server API calls has a measurable impact on system-loop throughput at scale.

**Architectural consequences**

- Use `Packed*Array` types for all numeric data in system-node hot-path loops; they store contiguous C memory with no Variant overhead and are the closest GDScript equivalent to C++ struct arrays.
- Batch rendering and physics operations through `RenderingServer` and `PhysicsServer2D` / `PhysicsServer3D` direct APIs to bypass per-Node SceneTree overhead when updating large object populations.
- For true struct-layout control and SIMD potential, move the confirmed-hot computation path to a GDExtension module that writes results back into `Packed*Arrays` consumed by the GDScript orchestration layer.

**Patterns influenced** — Data Locality, Spatial Partition, Object Pool, Update Method, Component

---

### GDScript Dynamic Dispatch

**Why it matters** — GDScript resolves all method calls dynamically at runtime; there is no static dispatch, inlining, or devirtualization, and dispatch reduction is not a meaningful optimization target within GDScript.

**Architectural consequences**

- Design GDScript code for correctness and maintainability; the interpreter overhead per dispatch is uniform and cannot be selectively eliminated by architectural choices at the GDScript level.
- Use `is` checks and `class_name`-based typing for polymorphic dispatch decisions; this is idiomatic GDScript and does not carry the overhead model that `dynamic_cast` does in C++.
- When profiling confirms that GDScript call overhead on a specific hot path is the bottleneck, migrate that path to GDExtension; do not attempt to optimize GDScript dispatch from within GDScript.

**Patterns influenced** — Subclass Sandbox, Type Object, State, Component, Bytecode

---

### Main Thread Restriction

**Why it matters** — Most Godot `Object` and `Node` APIs must be called from the main thread; accessing them from a worker thread causes undefined behavior or silent engine crashes.

**Architectural consequences**

- Use `WorkerThreadPool` for background computation — pathfinding, file I/O, heavy simulation — and deliver results to the main thread via `call_deferred()` on a main-thread Node rather than writing to the SceneTree directly from the worker.
- Protect shared data between the worker and main thread with a `Mutex`; keep the locked region to a buffer swap, not to the processing of the buffer contents, to minimize contention.
- Signal emissions from worker threads are not safe; queue results and emit signals only after the main thread has taken ownership of the data.

**Patterns influenced** — Event Queue, Double Buffer, Spatial Partition, Game Loop

---

## Section 4: Pattern Selection Guide

### Component vs. Subclassing (Entity Architecture)

| Situation                                | Prefer      | Avoid       | Reason (max 10 words)                            |
| ---------------------------------------- | ----------- | ----------- | ------------------------------------------------ |
| Entity spans physics, render, and AI     | Component   | Subclassing | Domains couple through shared base class         |
| Dozens of variants, behavior is fixed    | Subclassing | Component   | Component wiring overhead is not justified       |
| Behavior must swap at runtime            | Component   | Subclassing | Inheritance binding is statically fixed          |
| Small, cohesive, single-domain entity    | Subclassing | Component   | Simpler; no inter-component communication needed |
| Code reuse across unrelated entity types | Component   | Subclassing | Components reuse without forcing shared ancestry |

---

### Observer vs. Event Queue (Event Propagation)

| Situation                                   | Prefer      | Avoid       | Reason (max 10 words)                              |
| ------------------------------------------- | ----------- | ----------- | -------------------------------------------------- |
| Decouple sender identity from receiver      | Observer    | Event Queue | Lower complexity; synchronous call is sufficient   |
| Sender and receiver run in different phases | Event Queue | Observer    | Observer fires synchronously inside sender's frame |
| Slow or blocking receiver possible          | Event Queue | Observer    | Slow observer directly stalls the subject          |
| Must trace event source for debugging       | Observer    | Event Queue | Synchronous call stack is directly inspectable     |
| Cross-thread safety required                | Event Queue | Observer    | Observer has no inherent thread boundary           |
| Receiver must aggregate or batch requests   | Event Queue | Observer    | Queue allows discard, delay, or coalescing         |

---

### Singleton vs. Service Locator (Global Access)

| Situation                                             | Prefer          | Avoid           | Reason (max 10 words)                              |
| ----------------------------------------------------- | --------------- | --------------- | -------------------------------------------------- |
| Need to swap implementation at runtime                | Service Locator | Singleton       | Singleton permanently binds to one concrete type   |
| Testing requires a null or mock service               | Service Locator | Singleton       | Service Locator supports registered null provider  |
| True single-instance enforcement is needed            | Singleton       | Service Locator | Locator does not enforce one-instance constraint   |
| Infrastructure-level ambient service (audio, logging) | Service Locator | Singleton       | Decouples callers from concrete implementing class |
| Access must be tightly controlled by scope            | Neither         | Both            | Pass dependency explicitly; use neither pattern    |

---

### State vs. Type Object (Behavior Variation)

| Situation                                       | Prefer      | Avoid       | Reason (max 10 words)                               |
| ----------------------------------------------- | ----------- | ----------- | --------------------------------------------------- |
| Entity transitions between exclusive modes      | State       | Type Object | State encodes legal transitions as first-class data |
| Many instances share a fixed class profile      | Type Object | State       | Type Object enables data-driven, shared type config |
| Types defined externally or moddable            | Type Object | State       | Type Object instances loadable from data files      |
| Complex per-mode behavior with state data       | State       | Type Object | State bundles behavior and data per mode cleanly    |
| Behavior changes at fixed class-definition time | Type Object | State       | Type Object avoids runtime mode-switch overhead     |

---

### Object Pool vs. Standard Allocation (Memory Management)

| Situation                                           | Prefer              | Avoid               | Reason (max 10 words)                             |
| --------------------------------------------------- | ------------------- | ------------------- | ------------------------------------------------- |
| Frequent alloc/free of same-size objects            | Object Pool         | Standard Allocation | Eliminates fragmentation; O(1) deterministic cost |
| Objects vary significantly in size                  | Standard Allocation | Object Pool         | Pool wastes memory padding to maximum size        |
| Gameplay frame must not touch heap                  | Object Pool         | Standard Allocation | Pool alloc never calls system allocator           |
| Object count is truly unbounded                     | Standard Allocation | Object Pool         | Fixed pool silently fails at capacity             |
| Objects encapsulate expensive resources (DB, audio) | Object Pool         | Standard Allocation | Pool reuses resource acquisition across resets    |

---

### Flyweight vs. Full Object Representation (Memory Sharing)

| Situation                                      | Prefer       | Avoid        | Reason (max 10 words)                                 |
| ---------------------------------------------- | ------------ | ------------ | ----------------------------------------------------- |
| Thousands of objects share static mesh/texture | Flyweight    | Full Objects | Shared intrinsic pointer eliminates per-instance copy |
| Each object's state is fully unique            | Full Objects | Flyweight    | No shared data means no memory savings                |
| GPU instanced rendering of similar meshes      | Flyweight    | Full Objects | Maps directly to instanced draw call model            |
| Per-instance behavior varies independently     | Full Objects | Flyweight    | Flyweight assumes behavior is shared, not varied      |

---

### Command vs. Direct Call (Action Encapsulation)

| Situation                                    | Prefer      | Avoid       | Reason (max 10 words)                               |
| -------------------------------------------- | ----------- | ----------- | --------------------------------------------------- |
| Input bindings must be remappable at runtime | Command     | Direct Call | Command is a swappable, storable indirection object |
| Need undo/redo or action history             | Command     | Direct Call | Command stores pre-execution state for reversal     |
| AI and player share same action system       | Command     | Direct Call | Command decouples actor identity from action logic  |
| Simple one-shot, no history needed           | Direct Call | Command     | Command class overhead not justified for triviality |
| Replay or deterministic simulation needed    | Command     | Direct Call | Recorded command stream drives replay identically   |

---

### Bytecode vs. Subclassing (Behavior Extensibility)

| Situation                                  | Prefer      | Avoid       | Reason (max 10 words)                             |
| ------------------------------------------ | ----------- | ----------- | ------------------------------------------------- |
| Designers author behavior, not programmers | Bytecode    | Subclassing | Bytecode sandboxes designer from engine internals |
| Behavior must hot-reload without recompile | Bytecode    | Subclassing | Subclassing requires full C++ recompile cycle     |
| Performance is critical for behavior path  | Subclassing | Bytecode    | Native code is faster than VM interpreter         |
| Behavior set is small and closed           | Subclassing | Bytecode    | Bytecode VM maintenance overhead not justified    |
| Behavior must be moddable by end users     | Bytecode    | Subclassing | Bytecode ships as data, not compiled binary       |

## Section 5: Pattern Catalog

---

### Design Patterns Revisited

`@gpp_s5_Design.md`

### Sequencing Patterns

`@gpp_s5_Sequencing.md`

### Behavioral Patterns

`@gpp_s5_Behavioral.md`

### Decoupling Patterns

`@gpp_s5_Decoupling.md`

### Optimization Patterns

`@gpp_s5_Optimization.md`

---

## Section 6: Pattern Combination Recipes

---

### Goal: Building Flexible Gameplay Entities

**Godot Primitives / Patterns:**

- Scene hierarchy / Node children (replaces Component)
- `_physics_process` on each child Node (replaces Update Method — engine-native)
- `Packed*Array` + system node (replaces Data Locality flat arrays for high-count entities)
- `process_priority` for explicit cross-component update ordering
- `.tscn` scene file (replaces factory function)

**Why They Work Together in Godot:**

- Scene composition is the Component runtime: child Nodes with independent `_physics_process` callbacks require no update loop, no component interface, and no manual wiring beyond `@onready` field declarations.
- For homogeneous high-count entities (bullets, projectiles, crowd members), replacing per-entity Nodes with one system node iterating `PackedVector2Array` arrays eliminates per-node SceneTree dispatch overhead at the scale where it becomes measurable.
- `process_priority` (lower = earlier) enforces update ordering between sibling components explicitly and auditably, replacing the implicit iteration-sequence ordering that SoA array layout imposes in C++.

**Implementation Notes:**

- Use scene-hierarchy components (child Nodes with `_physics_process`) for low-count heterogeneous entities — player, boss, interactables; switch to system-node + `Packed*Array` only for homogeneous entities counted in the hundreds.
- The `.tscn` file is the factory: `player.tscn` assembles `MovementComponent`, `HealthComponent`, and `WeaponComponent` as child Nodes without any code factory function.
- Pan-domain state (position, velocity, facing) lives on the container Node; components access it via `get_parent() as CharacterBody2D`, which is the communication channel that avoids direct component-to-component coupling.
- Cache all component references in `@onready` fields at `_ready()`; never call `$ComponentName` or `get_node()` inside `_physics_process`.
- For system-node entities, despawn by swapping the target index with the last active element (`_pos[idx] = _pos[_n - 1]; _n -= 1`) rather than marking inactive flags; this keeps the active prefix contiguous and eliminates the isActive branch.
- `MultiMeshInstance3D` is the GPU-side Data Locality equivalent; replace individual `MeshInstance3D` nodes with one `MultiMeshInstance3D` at visual-population counts above a few dozen.

**Watch Out For:**

- Renaming a component Node in the scene tree silently breaks all `@onready` cache references to it; `get_node()` errors only surface at `_ready()` runtime, not at edit time.
- Transitioning an entity from per-entity Nodes to a system-node + `Packed*Array` design invalidates all Node-based identity references; the migration requires redesigning entity identification to use array indices rather than Node pointers.
- System-node packed arrays must be pre-allocated at `_ready()` with `resize(MAX)`; never call `append()` or `push_back()` on them during `_physics_process`.

**Suggested Layout:**

```text
res://entities/player/
    player.tscn             # Player (CharacterBody2D) ▶ MovementComponent, HealthComponent
    player.gd               # @onready refs, signal wiring only
    components/
        movement_component.gd
        health_component.gd
res://systems/
    bullet_system.gd        # system-node for PackedFloat32Array bullet population
```

**GDScript Sketch:**

```gdscript
# bullet_system.gd — system-node approach; replaces per-bullet Node + _physics_process
class_name BulletSystem
extends Node

const MAX: int = 256
var _px: PackedFloat32Array = PackedFloat32Array()
var _py: PackedFloat32Array = PackedFloat32Array()
var _vx: PackedFloat32Array = PackedFloat32Array()
var _vy: PackedFloat32Array = PackedFloat32Array()
var _n: int = 0

func _ready() -> void:
    _px.resize(MAX); _py.resize(MAX)
    _vx.resize(MAX); _vy.resize(MAX)

func spawn(pos: Vector2, vel: Vector2) -> void:
    if _n >= MAX: return
    _px[_n] = pos.x; _py[_n] = pos.y
    _vx[_n] = vel.x; _vy[_n] = vel.y
    _n += 1

func despawn(idx: int) -> void:
    _n -= 1
    _px[idx] = _px[_n]; _py[idx] = _py[_n]
    _vx[idx] = _vx[_n]; _vy[idx] = _vy[_n]

func _physics_process(delta: float) -> void:
    for i: int in _n:
        _px[i] += _vx[i] * delta
        _py[i] += _vy[i] * delta
```

---

### Goal: Decoupling Game Systems Without Sacrificing Performance

**Godot Primitives / Patterns:**

- Scene hierarchy / Node children (replaces Component — within-entity isolation)
- Signal + `EventBus` Autoload (replaces Event Queue — cross-system identity and temporal decoupling)
- Autoload shell + `AudioProvider` abstraction (replaces Service Locator — infrastructure isolation)
- `call_deferred()` for events that must not execute mid-physics-step

**Why They Work Together in Godot:**

- The three isolation seams map directly: scene components isolate domains within an entity, an `EventBus` Autoload isolates cross-scene system notification by identity, and an Autoload provider shell isolates every call site from the infrastructure implementation.
- In Godot, a typed Signal on an `EventBus` Autoload replaces an Event Queue for most cross-system communication: it provides identity decoupling and, via `call_deferred()`, temporal decoupling — without ring-buffer infrastructure.
- A ring-buffer `Event Queue` is still warranted over a signal when aggregation, coalescing, or cross-thread delivery is required (e.g., audio deduplication); for single-notification cross-system events, a signal to the EventBus is simpler and traceable.

**Implementation Notes:**

- `EventBus.gd` (Autoload) contains typed signal declarations only — no state, no logic; every consumer connects in its own `_ready()` and never requires the EventBus to know it exists.
- `AudioService.gd` (Autoload) is the provider shell; it holds `_provider: AudioProvider = NullAudioProvider.new()` initialized in `_ready()`, ensuring every call site is always safe before registration.
- Use `health.depleted.connect(_on_depleted)` in the entity's `_ready()` for within-entity component signals; use `EventBus.enemy_died.emit(...)` for cross-scene notifications that any number of unknown consumers may handle.
- Emit cross-scene events with `EventBus.enemy_died.emit.call_deferred(id, pos)` when the event fires mid-physics-step and handlers must not run until the step completes.
- Keep `EventBus` signals to genuinely cross-domain events; within-subsystem signals should connect directly between the involved nodes without routing through the global bus.

**Watch Out For:**

- The `EventBus` Autoload is a global variable; every system that connects to it creates a hidden dependency, and the coupling problem it is meant to solve re-emerges silently as the number of connected systems grows.
- Cross-scene events carry stale-world risk: world state at the signal handler's execution may differ from state at emission time — especially with `call_deferred()` — so emit all necessary context as signal parameters rather than reading world state in the handler.
- Initializing `_provider = NullAudioProvider.new()` in `_ready()` rather than as a field default is required; field initializers run before the Autoload tree is fully built and may fire before sibling Autoloads are ready.

**GDScript Sketch:**

```gdscript
# enemy.gd — three isolation seams at the point of enemy death
class_name Enemy
extends CharacterBody2D

@onready var health: HealthComponent = $HealthComponent  # Component: within-entity
@export var death_sfx: AudioStream

func _ready() -> void:
    health.depleted.connect(_on_depleted)

func _on_depleted() -> void:
    AudioService.play(death_sfx)                              # Autoload provider: infrastructure
    EventBus.enemy_died.emit(get_instance_id(), global_position)  # Signal/EventBus: cross-scene
    queue_free()

# No reference to AchievementSystem, TutorialSystem, or AudioSystem in this file.
# Each observer wires itself: EventBus.enemy_died.connect(_on_enemy_died) in its own _ready().
```

---

### Goal: Managing High Object Counts Efficiently

**Godot Primitives / Patterns:**

- Pre-instantiated pool with `process_mode` toggling (replaces Object Pool)
- `PackedFloat32Array` + system node (replaces Data Locality)
- System-node `_physics_process` (replaces Update Method — engine-native at the system level)
- Packed-active deactivation-by-swap for inline O(1) removal

**Why They Work Together in Godot:**

- A system node holding `PackedFloat32Array` arrays pre-allocated to `MAX_COUNT` eliminates per-frame `instantiate()` cost entirely; the flat arrays are the pool and the data store simultaneously.
- Deactivation by swapping the expired element with the last active element keeps the active prefix contiguous with no gaps, so the `_physics_process` loop iterates only live objects with no branch or wasted memory read.
- For GameObjects that require Node identity (collision shapes, signals, scene hierarchy), pre-instantiated Nodes with `PROCESS_MODE_DISABLED` serve the pool role; for pure-data objects (particles, projectiles with no collision), a `PackedFloat32Array` system node is more efficient.

**Implementation Notes:**

- Choose the approach by object type: `PackedFloat32Array` system node for pure-data homogeneous objects (projectiles, VFX, bullets); pre-instantiated Node pool for objects that require `Area2D`, signals, or collision shapes.
- The packed-active swap deactivates by copying the last active element over the removed one and decrementing the active count; the update loop then processes the swapped element at the same index on the next iteration.
- Do not re-increment `i` after a swap-deactivation; the swapped element at index `i` must be processed before moving to `i + 1`.
- Pool exhaustion strategy must match the object type: silently drop for VFX (cosmetic), assert for enemies (a missing enemy is a gameplay bug), evict the quietest playing sound for audio channels.
- Clear all references on a Node pool release (`target = null`, `owner_ref = null`) to prevent GC hold-aliveness through dead slots.

**Watch Out For:**

- The `despawn(idx)` swap invalidates any external reference held to a specific array index; the external code that held `idx` now points at the swapped-in object, not the original one — store a stable entity ID separately if stable external identity is needed.
- `PackedScene.instantiate()` during `_physics_process` for pool warm-up is the bug; always warm up during a loading screen's `_ready()`, never during gameplay.
- `GPUParticles2D` and `GPUParticles3D` are built-in pooled particle systems; never replace them with a custom `PackedFloat32Array` particle system.

**GDScript Sketch:**

```gdscript
# vfx_system.gd — packed-active array with inline swap-on-expire; no Node per particle
class_name VFXSystem
extends Node

const MAX: int = 1024
var _x:    PackedFloat32Array = PackedFloat32Array()
var _y:    PackedFloat32Array = PackedFloat32Array()
var _vx:   PackedFloat32Array = PackedFloat32Array()
var _vy:   PackedFloat32Array = PackedFloat32Array()
var _life: PackedFloat32Array = PackedFloat32Array()
var _n: int = 0

func _ready() -> void:
    _x.resize(MAX); _y.resize(MAX)
    _vx.resize(MAX); _vy.resize(MAX); _life.resize(MAX)

func emit(pos: Vector2, vel: Vector2, lifetime: float) -> void:
    if _n >= MAX: return
    _x[_n] = pos.x; _y[_n] = pos.y
    _vx[_n] = vel.x; _vy[_n] = vel.y
    _life[_n] = lifetime
    _n += 1

func _physics_process(delta: float) -> void:
    var i: int = 0
    while i < _n:
        _life[i] -= delta
        if _life[i] <= 0.0:
            _n -= 1                                 # swap-with-last: O(1), no gap
            _x[i] = _x[_n]; _y[i] = _y[_n]
            _vx[i] = _vx[_n]; _vy[i] = _vy[_n]
            _life[i] = _life[_n]                    # do NOT increment i: recheck slot
        else:
            _x[i] += _vx[i] * delta
            _y[i] += _vy[i] * delta
            i += 1
```

---

### Goal: Reducing Runtime Allocation During Gameplay Frames

**Godot Primitives / Patterns:**

- Pre-instantiated pool with `process_mode` toggling (replaces Object Pool)
- Resource setter + `_dirty` flag + `queue_redraw()` (replaces Dirty Flag)
- `ProjectSettings: physics/common/physics_interpolation` (replaces Double Buffer for rendering — engine-native)
- Per-actor `PackedByteArray` swap (replaces Double Buffer for simultaneous-update simulation)

**Why They Work Together in Godot:**

- The pool eliminates `PackedScene.instantiate()` during gameplay frames — the dominant GDScript allocation source — by pre-allocating all objects at load time and toggling `process_mode` instead of freeing and re-creating.
- The dirty flag prevents recomputing expensive Resource-derived data (navigation paths, stat aggregations) on every frame; encapsulating all primary-data writes behind typed property setters ensures every mutation sets the flag.
- Godot's built-in physics interpolation (`ProjectSettings`) handles the rendering Double Buffer concern: visual positions are smoothed between physics ticks without any user-space buffer swap, eliminating the pattern's primary game-engine use case.

**Implementation Notes:**

- Enable `physics/common/physics_interpolation` in ProjectSettings before writing any manual interpolation code between physics and render frames.
- The per-actor simulation Double Buffer (simultaneous-update grids, contagion maps, cellular automata) is the remaining user-space case: maintain `_current` and `_next` `PackedByteArray` arrays and swap references at the end of each `_physics_process` tick.
- Implement dirty flags via GDScript property setters (`var x: float: set(v): x = v; _dirty = true`); a setter-less public field allows any caller to modify primary data without setting the flag, silently breaking the invariant.
- Initialize `_dirty = true` at construction; the derived value has not yet been computed and is stale by definition.
- `queue_redraw()` on a `CanvasItem` is the engine-native single-bit dirty flag for custom 2D drawing; call it from the setter rather than maintaining a separate `_draw_dirty` field.

**Watch Out For:**

- The reference-swap for `PackedByteArray` double buffering is O(1) in GDScript (reference reassignment, not data copy); if the arrays are mistakenly duplicated rather than swapped, the cost is O(n).
- A missing `queue_free()` call on the previous pool occupant before reassigning its slot to a new object causes the previous lifetime's state to persist until the next `reset()` call.
- Calling `queue_redraw()` every `_process` frame unconditionally means the dirty flag is always set and its deferred benefit is lost; call it only from setters that change data that `_draw()` uses.

---

### Goal: Creating Extensible AI Behavior

**Godot Primitives / Patterns:**

- `RefCounted` state objects + `PlayerFSM` / `NodeFSM` Node (replaces State + Update Method)
- `EnemyState` base with provided operations (replaces Subclass Sandbox)
- `AnimationTree` with `AnimationStateMachine` (engine-native animation FSM — do not replace)
- `Expression` class for formula-level designer-authored behavior (lightweight Bytecode alternative)
- Custom GDScript VM (replaces Bytecode for truly sandboxed designer-authored logic)

**Why They Work Together in Godot:**

- The script FSM owns gameplay logic — movement decisions, health checks, combat triggers — while `AnimationTree` owns the animation layer; keeping them separate prevents animation transitions from driving gameplay and gameplay state from driving animation directly.
- `EnemyState` base class provides `_travel_animation()`, `_play_sfx()`, and `_query_player()` as provided operations; states call only these methods and have no direct coupling to `AnimationTree`, `AudioService`, or SceneTree queries.
- `Expression.parse(formula, param_names)` + `Expression.execute(values)` evaluates designer-authored damage or AI scoring formulas at runtime without building a full VM; use it for scalar behavioral variation before committing to a custom bytecode system.

**Implementation Notes:**

- States drive `AnimationTree` by calling `_travel_animation(owner, &"walk")` from `enter()`; the animation layer is a consequence of state entry, never the driver of state transitions.
- `RefCounted` states are the correct base type for logic-only states with no child nodes; use `Node`-based states only when a state requires its own `_physics_process`, child nodes, or `AnimationPlayer` access.
- For boss AI where each phase requires a fundamentally different behavior tree or spawner configuration, `NodeFSM` with child `CharacterState` Nodes and `set_physics_process()` lifecycle control is preferable to `RefCounted` states.
- `Expression` formulas stored as `@export var formula: String` on a `Resource` are hot-reloadable and designer-editable in the Inspector; call `_expr.parse()` once at initialization, not per-evaluation.
- A custom GDScript VM is warranted only when behavior must be sandboxed from engine access (user mods, untrusted content); for any other case, GDScript with hot-reload already delivers designer iteration without sandboxing overhead.

**Watch Out For:**

- Putting animation transition logic inside `AnimationTree` condition parameters and reading gameplay state from the `AnimationTree` reverses the dependency; script FSM must drive `AnimationTree`, never the reverse.
- `Expression.execute()` silently returns an empty `Variant` on parse failure; always call `_expr.has_execute_failed()` after execution and handle the error case explicitly.
- Subclass Sandbox base class accumulates coupling as more behaviors are added; once the provided-operations count exceeds ten to fifteen, extract cohesive groups into helper `RefCounted` objects exposed via single accessors on the base.

**Suggested Layout:**

```text
res://entities/enemy/
    enemy.tscn              # Enemy ▶ EnemyFSM, AnimationTree, VisionCone (Area2D)
    enemy_state.gd          # RefCounted base — provided operations
    states/
        patrol_state.gd     # extends EnemyState
        chase_state.gd      # extends EnemyState
        attack_state.gd     # extends EnemyState
res://systems/vm/
    spell_vm.gd             # RefCounted — custom VM for designer-authored ability logic
    spell_sandbox.gd        # RefCounted — security boundary for VM opcodes
```

**GDScript Sketch:**

```gdscript
# enemy_state.gd — base with provided operations; Subclass Sandbox for state subclasses
class_name EnemyState
extends RefCounted

func enter(owner: CharacterBody2D) -> void: pass
func exit(owner: CharacterBody2D)  -> void: pass
func update(owner: CharacterBody2D, delta: float) -> EnemyState: return null

# Provided operations — states call only these; zero direct AnimationTree/AudioService coupling
func _travel_anim(owner: CharacterBody2D, anim: StringName) -> void:
    var pb := owner.get_node("AnimationTree")["parameters/playback"]
    (pb as AnimationNodeStateMachinePlayback).travel(anim)

func _play_sfx(stream: AudioStream, volume_db: float = 0.0) -> void:
    AudioService.play(stream, volume_db)

func _nearest_player(owner: CharacterBody2D) -> CharacterBody2D:
    return owner.get_tree().get_first_node_in_group(&"player") as CharacterBody2D
```

```gdscript
# patrol_state.gd — concrete state; calls provided ops only; returns next state on transition
class_name PatrolState
extends EnemyState

func enter(owner: CharacterBody2D) -> void:
    _travel_anim(owner, &"walk")     # drives AnimationTree from state entry, not the reverse

func update(owner: CharacterBody2D, delta: float) -> EnemyState:
    owner.velocity.x = 80.0
    owner.move_and_slide()
    if _nearest_player(owner) != null:
        return ChaseState.new()      # transition: return the desired next state
    return null
```

---

### Goal: Supporting Dynamic or Moddable Content

**Godot Primitives / Patterns:**

- `Resource` with `@export parent: SameType` + `resolve_*()` methods (replaces Type Object)
- `PackedScene.instantiate()` (replaces Prototype — engine subsumes `clone()`)
- `Expression` class (lightweight Bytecode for formula-level behavioral variation)
- `ResourceLoader.load()` (replaces type object registry — engine-native caching)
- Custom GDScript VM + `SpellSandbox` (replaces full Bytecode for sandboxed modding)
- Inspector + `.tres` files (replaces separate designer authoring tool for data types)

**Why They Work Together in Godot:**

- `Resource` files are the designer-facing "classes": a `SpellType.tres` defines a spell variant entirely in the Inspector with no code change, and `ResourceLoader.load()` guarantees one object per path with no custom registry.
- `@export var spawn_scene: PackedScene` on the type Resource gives the type control over which node hierarchy is instantiated, replacing the C++ factory method; `spawn_scene.instantiate()` is the Prototype clone.
- `Expression.parse(formula, params)` evaluates designer-authored damage or scaling formulas stored as `@export var formula: String` fields on the Resource, delivering runtime behavioral variation without a full VM.

**Implementation Notes:**

- `@export var parent: SpellType = null` enables single-level designer inheritance between `.tres` files; `resolve_damage()` walks the chain until it finds a non-zero value, providing copy-down semantics without a separate flattening step.
- `ResourceLoader.load("res://types/fireball.tres")` always returns the same cached object for the same path; there is no custom registry, no lifetime management, and no uniqueness enforcement needed.
- For post-ship moddable content (user-created spells, untrusted sources), a custom VM + `SpellSandbox` is required because loaded GDScript scripts have full engine access; `Expression` is insufficient for behavioral sandboxing.
- Call `_expr.parse(formula, param_names)` once at initialization, not per-execution; check `_expr.has_execute_failed()` after every `execute()` call and fall back to `resolve_damage()`.
- `resource.duplicate(true)` deep-copies the full Resource graph; never call it on a type Resource used as a Flyweight — all instances referencing the same `.tres` must share one object.

**Watch Out For:**

- Circular `parent` chains (`SpellA.parent = SpellB`, `SpellB.parent = SpellA`) are not detected at load time; add an `assert(parent != self)` guard in `resolve_*()` methods.
- GDScript scripts loaded with `load()` for moddable behavior run with full, unrestricted engine access — they are NOT sandboxed; use a custom VM with a `SpellSandbox` security boundary for any user-provided behavioral logic.
- Type Resources freed or hot-reloaded while entity instances hold references produce stale resolved values; always call `is_instance_valid(type)` before any `resolve_*()` call during development.

**Suggested Layout:**

```text
res://resources/types/
    spell_type.gd               # Resource — @export fields + resolve_*() + spawn factory
    data/spells/
        base_spell.tres         # root of inheritance chain; parent = null
        fireball.tres           # parent = base_spell.tres; overrides damage
        chain_lightning.tres    # parent = base_spell.tres; overrides formula
res://systems/vm/
    spell_vm.gd                 # RefCounted — custom VM for sandboxed post-ship mods
    spell_sandbox.gd            # RefCounted — security boundary; opcodes listed explicitly
```

**GDScript Sketch:**

```gdscript
# spell_type.gd — Resource-based type object; Expression for designer formulas
class_name SpellType
extends Resource

@export var display_name: String = ""
@export var base_damage: int = 0         # 0 = inherit from parent
@export var damage_formula: String = ""  # e.g., "base + (level * 2)"
@export var parent: SpellType = null
@export var spawn_scene: PackedScene     # Prototype: instantiated on cast

var _expr: Expression = Expression.new()
var _expr_ready: bool = false

func resolve_damage() -> int:
    if base_damage > 0: return base_damage
    return parent.resolve_damage() if parent != null else 0

func evaluate_damage(level: int) -> int:
    if damage_formula.is_empty(): return resolve_damage()
    if not _expr_ready:
        _expr.parse(damage_formula, ["base", "level"])
        _expr_ready = true
    var result: Variant = _expr.execute([resolve_damage(), level])
    return int(result) if not _expr.has_execute_failed() else resolve_damage()

func cast(at: Vector3, parent_node: Node) -> Node:
    assert(spawn_scene != null, "%s has no spawn_scene." % display_name)
    var inst: Node = spawn_scene.instantiate()
    parent_node.add_child(inst)
    if inst is Node3D: (inst as Node3D).global_position = at
    return inst
```

---

### Goal: Building a Robust Game Loop

**Godot Built-In Solution:** Godot's engine owns the game loop entirely: `_physics_process(delta)` runs at a fixed timestep governed by `ProjectSettings: physics/common/physics_ticks_per_second`, `_process(delta)` runs per render frame, `Engine.max_physics_steps_per_frame` caps spiral-of-death catch-up, and `ProjectSettings: physics/common/physics_interpolation` eliminates the Double Buffer concern for visual rendering by smoothing positions between physics ticks with no user code. The original combination is warranted only for the user-space simulation Double Buffer case — per-actor simultaneous-update grids (cellular automata, contagion maps) where actors read each other's state in the same `_physics_process` pass — in which case the Double Buffer translation in Section 5 applies; the Game Loop and Update Method components remain engine-owned.

---

### Goal: Building a Replayable Command History

**Godot Primitives / Patterns:**

- `Callable` (replaces stateless fire-and-forget Command — zero allocation)
- `RefCounted` `UndoableCommand` subclasses (replaces undo/redo Command — GC-managed lifetime)
- Bounded `Array[UndoableCommand]` with cursor (replaces Object Pool — explicit pool not needed in GDScript)
- `EditorUndoRedoManager` (engine-native for `@tool` scripts and editor plugins)

**Why They Work Together in Godot:**

- In C++, Object Pool prevents per-command heap allocation during gameplay; in GDScript, `RefCounted` allocation is GC-managed and inexpensive, so the pool's role reduces to bounding history depth with a `MAX_DEPTH` constant rather than pre-allocating a fixed command arena.
- `Callable` replaces the entire stateless Command subclass hierarchy for fire-and-forget input remapping: `_bindings[&"jump"] = func(a: CharacterBody2D): a.jump()` has zero per-call allocation and no class declaration.
- `EditorUndoRedoManager` provides full undo infrastructure for `@tool` scripts and editor plugins; never build a custom history stack in editor context.

**Implementation Notes:**

- Use `Callable` for input bindings that need no undo; use `RefCounted UndoableCommand` subclasses only when undo state must be captured at `execute()` time.
- Bound the history with `const MAX_DEPTH: int = 64`; when the stack reaches depth, `remove_at(0)` to evict the oldest command rather than asserting.
- All mutations tracked by the history must route through `push(cmd, actor)`; one direct write to actor state outside the history silently corrupts undo from that point.
- `UndoableCommand` captures pre-execution state in `execute()` — not in `_init()` — so the state reflects the exact world at the moment the command ran.
- For networked replay, serialize the command stream (not the history stack) as a `PackedByteArray`; replay by re-executing the recorded commands in order, not by replaying undo operations.

**Watch Out For:**

- The `_stack.resize(_cursor + 1)` call before `append()` discards the redo branch on a new push; if the resize is omitted, redoing a command that was superseded by a new action produces undefined behavior.
- A `UndoableCommand` that holds a direct `Node` reference will crash on `undo()` if the Node was freed between push and undo; always guard with `is_instance_valid()` before dereferencing history entries.
- `Callable` closures that capture a local variable by reference (GDScript captures by value) may produce unexpected behavior in a loop; prefer `Callable.bind(arg)` over closures for loop-generated bindings.

**GDScript Sketch:**

```gdscript
# command_history.gd — bounded undo/redo without explicit Object Pool
# GDScript RefCounted allocation is GC-managed; pool concern → depth bound only.
class_name CommandHistory
extends RefCounted

const MAX_DEPTH: int = 64
var _stack: Array[UndoableCommand] = []
var _cursor: int = -1

func push(cmd: UndoableCommand, actor: Node2D) -> void:
    _stack.resize(_cursor + 1)           # discard redo branch
    cmd.execute(actor)
    if _stack.size() >= MAX_DEPTH:
        _stack.remove_at(0)              # evict oldest; cursor stays at end
    else:
        _cursor += 1
    _stack.append(cmd)
    _cursor = _stack.size() - 1

func undo(actor: Node2D) -> void:
    if _cursor >= 0 and is_instance_valid(actor):
        _stack[_cursor].undo(actor)
        _cursor -= 1

func redo(actor: Node2D) -> void:
    if _cursor < _stack.size() - 1 and is_instance_valid(actor):
        _cursor += 1
        _stack[_cursor].execute(actor)
```

---

### Goal: Delivering Ambient Cross-Cutting Services Safely

**Godot Primitives / Patterns:**

- Autoload shell (replaces Service Locator — global access point)
- `NullAudioProvider extends AudioProvider` with `push_warning()` (replaces Null Object)
- `LoggingAudioProvider extends AudioProvider` (replaces Decorator)
- `AudioProvider` base `RefCounted` (replaces abstract service interface)

**Why They Work Together in Godot:**

- A raw Autoload IS a Singleton; the `AudioProvider` abstraction layer is added only when swappability, a null provider, or a logging Decorator is genuinely required — not by default for every Autoload.
- `NullAudioProvider.new()` initialized in `_ready()` guarantees that `AudioService.play()` is always safe from the first frame, eliminating the null-return crash that makes raw Singleton lookup hazardous.
- `LoggingAudioProvider` wraps any `AudioProvider` and is swapped in by calling `AudioService.provide(LoggingAudioProvider.new(real_provider))`; no call-site changes are required anywhere in the project.

**Implementation Notes:**

- Initialize `_provider = NullAudioProvider.new()` in `_ready()`, not as a field default value; field initializers run before the SceneTree is built and may fire before sibling Autoloads are initialized.
- `NullAudioProvider` must call `push_warning()` in every method when running in debug builds; a null provider that silently absorbs calls turns missing-registration bugs invisible.
- The Autoload shell owns no provider lifetime; the bootstrap node that calls `AudioService.provide(real_provider)` is responsible for the provider object's lifecycle.
- Apply this pattern only to genuinely ambient infrastructure — audio, logging, analytics; pass domain-specific services explicitly as function parameters.
- For test isolation, call `AudioService.provide(MockAudioProvider.new())` in the test's setup and restore it in teardown; no framework is needed.

**Watch Out For:**

- Decorating the `NullAudioProvider` with a logger produces log entries for calls that go nowhere; always decorate the real service (`LoggingAudioProvider.new(real)`) rather than the null fallback.
- Every service registered through an Autoload-based locator is a hidden global dependency; adding non-ambient domain services to the locator creates the "grab-bag global namespace" problem the pattern is meant to prevent.
- Calling `AudioService.provide(null)` causes `_provider` to become `null` if the Autoload does not defensively reassign to `NullAudioProvider`; always handle `null` in `provide()` with an explicit fallback.

---

## Godot-Native Combinations

---

### Goal: Global Event Broadcasting Across Unrelated Systems

**Godot Primitives / Patterns:**

- `EventBus` Autoload with typed signal declarations (Signal replaces Observer + EventQueue identity/temporal decoupling)
- `call_deferred()` on signal emission for cross-step delivery

**Why They Work Together in Godot:**

- A signal-only Autoload provides global typed signal declarations that any Node can emit to or observe without any coupling between emitter and observer — a cross-scene Observer with no subscriber registry.
- Typed signal parameters (`signal enemy_died(id: int, pos: Vector2)`) give IDE completion, type checking at connection time, and explicit data contracts that raw `emit(args)` does not.
- Keeping the `EventBus` to signal declarations only — no state, no logic, no counters — prevents it from accreting into a hidden global service that every system depends on.

**Implementation Notes:**

- `EventBus.gd` (Autoload) contains only `signal` declarations; any method, variable, or logic added to it marks the beginning of its transformation into a Singleton anti-pattern.
- Node observers auto-disconnect when `queue_free()` is called; `Object` and `RefCounted` observers must call `signal.disconnect(callable)` explicitly before release or the connection becomes a lapsed listener.
- Scope signals to the domain that owns them: `EventBus.enemy_died` for game-wide events; a `LevelManager` node's own signal for events scoped to the current level that are not consumed outside it.
- For cross-thread signal emission, emit from the main thread via `EventBus.enemy_died.emit.call_deferred(id, pos)` in a main-thread callback; never emit signals from a worker thread directly.

**Watch Out For:**

- A handler that emits on the same `EventBus` in response to a signal it just received creates a cycle; unlike a synchronous recursive call, this cycle does not produce a stack overflow — it silently recirculates across frames.
- Connecting to `EventBus` signals in `_ready()` and never disconnecting from a non-Node observer causes the observer to be kept alive by the signal connection even after all other references are released.
- High-frequency events emitted every `_physics_process` tick (per-frame position updates, per-frame health changes) should not route through `EventBus`; use direct component signals or a ring-buffer `Event Queue` for rate-sensitive data.

**GDScript Sketch:**

```gdscript
# event_bus.gd (Autoload "EventBus") — signal declarations only; no state, no logic
class_name EventBus
extends Node

signal enemy_died(enemy_id: int, kill_position: Vector2)
signal item_collected(item_type: StringName, collector_id: int)
signal level_completed(level_index: int, elapsed_time: float)
signal player_health_changed(current: int, maximum: int)

# Emit:       EventBus.enemy_died.emit(id, global_position)
# Observe:    EventBus.enemy_died.connect(_on_enemy_died) in any node's _ready()
# Deferred:   EventBus.enemy_died.emit.call_deferred(id, pos)
# Node observers auto-disconnect on queue_free(); RefCounted observers must disconnect().
```

---

### Goal: Designer-Configurable Entities Without Code Changes

**Godot Primitives / Patterns:**

- `Resource` subclass with `@export` fields (replaces Type Object data class)
- `@export var parent: SameType` + `resolve_*()` methods (replaces type object inheritance chain)
- `@export var spawn_scene: PackedScene` on the Resource (factory method — replaces `newMonster()`)
- Inspector + `.tres` files (replaces separate designer authoring tooling)

**Why They Work Together in Godot:**

- A `Resource` subclass with `@export` fields is a designer-facing "class definition" that is editable in the Godot Inspector, serializable to `.tres`, and loadable at runtime without recompiling — Type Object with the engine providing the registry, authoring tool, and serialization.
- `@export var parent: EnemyType = null` on the Resource enables single-level designer inheritance between `.tres` files; `resolve_health()` walks the chain until finding a non-zero value, providing copy-down semantics that designers author by composing `.tres` references.
- `ResourceLoader.load("res://types/goblin.tres")` guarantees one shared object per path; no custom registry, no lifetime management, and no factory indirection is needed.

**Implementation Notes:**

- All resolve methods must guard against circular `parent` references; add `assert(parent != self, "Circular parent chain detected.")` at the top of each resolver.
- Entities hold `@export var type: EnemyType` and call `type.resolve_health()` in `_ready()` to cache resolved values; never call `resolve_*()` inside `_physics_process` — walk the chain once at initialization.
- Never mutate a shared type Resource at runtime; all per-instance mutable state (current health, cooldown timers) lives on the entity node, not on the Resource.
- Different entity types that need different node structures use different `spawn_scene: PackedScene` values; the type controls what gets instantiated, enabling heterogeneous entity types without a switch statement in the spawner.

**Watch Out For:**

- Calling `resource.duplicate()` on a type Resource per-entity-instance defeats the Flyweight sharing that makes the pattern memory-efficient; duplicate only when per-instance mutation of the Resource is genuinely required.
- `@export` type fields in the Inspector assign shared references; modifying a type Resource's field in-game affects every entity referencing it, not just the one being inspected.
- A missing `parent` assignment in a derived `.tres` file silently uses null as the base, returning zero or empty for all unset inherited fields; add a validator in `resolve_*()` that returns a safe default with `push_warning()`.

**Suggested Layout:**

```text
res://resources/types/
    enemy_type.gd               # Resource — @export fields + resolve_*() + spawn factory
    data/enemies/
        goblin_base.tres        # parent = null (root of chain)
        goblin_warrior.tres     # parent = goblin_base.tres; overrides max_health
        goblin_shaman.tres      # parent = goblin_base.tres; overrides spell_scene
```

**GDScript Sketch:**

```gdscript
# enemy_type.gd — Resource hierarchy; designers add variants as .tres files only
class_name EnemyType
extends Resource

@export var display_name: String = ""
@export var max_health: int = 0      # 0 = unset; resolved from parent chain
@export var move_speed: float = 0.0
@export var parent: EnemyType = null
@export var spawn_scene: PackedScene

func resolve_health() -> int:
    if max_health > 0: return max_health
    return parent.resolve_health() if parent != null else 0

func resolve_speed() -> float:
    if move_speed > 0.0: return move_speed
    return parent.resolve_speed() if parent != null else 0.0

func spawn(at: Vector3, parent_node: Node) -> Node:
    assert(spawn_scene != null, "EnemyType '%s' has no spawn_scene." % display_name)
    var inst: Node = spawn_scene.instantiate()
    parent_node.add_child(inst)
    if inst is Node3D: (inst as Node3D).global_position = at
    return inst
```

---

### Goal: Reactive Shared State Across Multiple Scenes

**Godot Primitives / Patterns:**

- `Resource` with reactive property setters (Signal replaces Observer)
- `@export var stats: PlayerStats` on any Node that needs shared state (replaces Service Locator for data)
- Typed `set:` property syntax for automatic invalidation notification

**Why They Work Together in Godot:**

- A `Resource` assigned to multiple Nodes via `@export` is the same shared object in memory; a property setter that emits a signal on mutation notifies all connected observers simultaneously without any observer registration infrastructure.
- `@export var stats: PlayerStats` makes the dependency explicit in the Inspector — any Node that needs the shared state declares it publicly; passing it through Autoloads or Service Locators is unnecessary.
- Because the signal is declared on the `Resource` itself, any system that holds a reference to the Resource can connect to its signals directly without going through the entity that owns it.

**Implementation Notes:**

- Declare signals on the `Resource` subclass (`signal health_changed(current: int, maximum: int)`), not on the Node that holds it; this allows UI, audio, and save systems to observe changes directly from the Resource without any coupling to the entity.
- Use GDScript's typed property setter syntax (`var health: int: set(v): health = v; signal.emit(v)`) to guarantee that every write path triggers the notification; a setter-less field allows silent mutations.
- A single shared Resource instance is correct for global player stats, settings, and session data; create separate `.tres` instances or call `resource.duplicate(true)` for per-character or per-save-slot state.
- Connect to Resource signals in the observer's `_ready()` and disconnect in `_exit_tree()` if the observer is a non-persistent Node; Resource signals do not auto-disconnect when a Node is freed unless the connection was made with `CONNECT_ONE_SHOT` or the signal target is a Node.

**Watch Out For:**

- A Resource signal emitted mid-`_physics_process` executes all connected handlers synchronously within the same step; use `call_deferred()` on the emit if any handler modifies state that the emitting code reads after the signal.
- Sharing one Resource instance between scenes that should have independent state (e.g., two players in split-screen) silently couples them; each player requires its own Resource instance, not a shared one.
- Hot-reloading a `.tres` file during development creates a new Resource object that is not the same instance held by running Nodes; signals connected to the old instance no longer fire.

**GDScript Sketch:**

```gdscript
# player_stats.gd — shared Resource with reactive setters; UI and audio observe directly
class_name PlayerStats
extends Resource

signal health_changed(current: int, maximum: int)
signal gold_changed(new_amount: int)

@export var max_health: int = 100
var _health: int = 0

var current_health: int:
    get: return _health
    set(v):
        _health = clampi(v, 0, max_health)
        health_changed.emit(_health, max_health)

var gold: int = 0:
    set(v):
        gold = maxi(v, 0)
        gold_changed.emit(gold)

func _init() -> void:
    _health = max_health
```

---

### Goal: Scene-Based Object Pooling for High-Frequency Spawning

**Godot Primitives / Patterns:**

- `PackedScene.instantiate()` at load time (replaces per-spawn allocation — Prototype warm-up)
- `process_mode = PROCESS_MODE_DISABLED` for dormant objects (replaces free-list "dead" state)
- `Array[Node]` available stack with typed push/pop (replaces free-list pointer chain)
- `reset()` method on each pooled object (replaces `init()` — clears per-use state and GC references)

**Why They Work Together in Godot:**

- Instantiating all `PackedScene` copies during a loading screen front-loads `_ready()` and tree-notification cost to a frame where latency is acceptable, making `acquire()` a property write rather than a tree parse.
- `PROCESS_MODE_DISABLED` stops all `_process`, `_physics_process`, and input callbacks on the node and its children simultaneously; `PROCESS_MODE_INHERIT` restores them in one write, making pool state transitions O(1) with no iteration.
- All pooled nodes remain as children of the pool node for their entire lifetime; `queue_free()` is never called on a pooled object — it would permanently remove the node from the tree.

**Implementation Notes:**

- Use `GPUParticles2D` and `GPUParticles3D` for visual particle effects; never replace them with a custom Node pool.
- Pre-size the available Array with `_available.reserve(POOL_SIZE)` after warm-up to prevent Array resize during the acquire/release cycle.
- `reset()` must null all references held by the pooled object (`target = null`, `owner_ref = null`) to allow GC to reclaim objects that were referenced during the previous lifetime.
- `_ready()` on each pooled node runs exactly once at warm-up; per-use initialization belongs in `reset()`, which is called on every `acquire()`.
- For pools accessed from multiple systems, expose a typed `PoolRegistry` Autoload that provides `acquire_bullet() -> BulletNode` and `release_bullet(node)` methods, encapsulating pool identity from call sites.

**Watch Out For:**

- Calling `queue_free()` on a pooled node is the critical failure mode: the node is permanently removed from the SceneTree and the next `acquire()` returns a freed node, causing a null-access crash that may not surface until the pool has cycled.
- A `reset()` that initializes only the fields set by the previous use, not all fields, allows state from two lifetimes back to persist when a field is conditionally set; always initialize all fields unconditionally in `reset()`.
- `_available.pop_back()` returns `null` when the pool is exhausted; call sites that do not check for `null` before using the result cause hard-to-trace crashes that only appear during peak gameplay.

---

### Goal: Lightweight Entity Composition Without Deep Inheritance

**Godot Primitives / Patterns:**

- `Node` host (SceneTree presence, lifecycle, signals to tree)
- `RefCounted` behavioral components (logic-only, no SceneTree presence, GC-managed)
- `Resource` data components (serializable, Inspector-editable, shared across instances)
- `@export var stats: EntityStats` on the Node host (explicit dependency — no Service Locator)

**Why They Work Together in Godot:**

- The three base types map to three responsibility tiers: `Resource` owns designer-configurable data, `RefCounted` owns runtime behavioral logic, and `Node` owns SceneTree lifecycle and signal topology — each type carries exactly the obligations its base class implies.
- `RefCounted` behavioral components hold no SceneTree references and require no `_ready()` lifecycle; they are constructed in the host's `_ready()` with data injected from a `Resource`, keeping behavior portable and testable without a scene.
- The `Node` host is deliberately thin — `@onready` references, `_ready()` wiring, and delegation to `RefCounted` components — preventing the host script from becoming a monolith as behavior complexity grows.

**Implementation Notes:**

- `RefCounted` components receive their configuration via `_init(stats: EntityStats)` parameter injection; they never hold a reference to the owning Node host, preventing circular lifetime dependencies.
- `@export var stats: EntityStats` on the host makes the data dependency explicit in the Inspector; changing the assigned `.tres` file in the Inspector hot-swaps the configuration without modifying any script.
- Declare signals on the `Resource` data component for state-change notifications (health depleted, inventory full) so observers can connect directly to the Resource without coupling to the Node host.
- `RefCounted` components that need to drive the host (e.g., `movement.tick(self, delta)`) receive the host as a parameter on each tick call; they do not store it as a field, which would create a reference cycle.
- This combination replaces deep entity inheritance hierarchies: `Player`, `Enemy`, and `NPC` share the same `MovementBehavior` `RefCounted` component with different `EntityStats` Resources, rather than branching into subclasses.

**Watch Out For:**

- A `RefCounted` component that stores the Node host as a field creates a reference cycle: the Node holds the `RefCounted`, the `RefCounted` holds the Node; GDScript's reference counter cannot break this cycle, and neither object is freed when expected.
- `@export` on a `RefCounted` field does not expose it as an editable object in the Inspector (only `Resource` subclasses are Inspector-editable); use `Resource` for designer-configurable data and `RefCounted` only for runtime-constructed behavior.
- `Resource` data components shared between entity instances are the same object in memory; if one entity modifies a field on the shared Resource (e.g., `stats.current_health -= damage`), all other entities referencing the same `.tres` are immediately affected.

**GDScript Sketch:**

```gdscript
# entity.gd — Node host wires Resource data and RefCounted behavior; thin by design
class_name Entity
extends CharacterBody2D

@export var stats: EntityStats           # Resource: serializable, Inspector-editable
var _move: MovementBehavior              # RefCounted: runtime behavior; not serialized

func _ready() -> void:
    assert(is_instance_valid(stats), "Entity requires an EntityStats resource.")
    _move = MovementBehavior.new(stats.move_speed)  # inject config; no Node reference stored
    stats.health_changed.connect(_on_health_changed)

func _physics_process(delta: float) -> void:
    _move.tick(self, delta)          # RefCounted drives host; host passed as parameter only

func take_damage(amount: int) -> void:
    stats.current_health -= amount   # setter on Resource emits stats.health_changed

func _on_health_changed(current: int, _max: int) -> void:
    if current <= 0: queue_free()
```

---

## Section 7: Architecture Review Checklist

### Coupling

- Are systems communicating directly when indirect communication would reduce breakage risk?
- Is dependency direction intentional and consistently enforced?
- Could an Observer or Event Queue replace direct method calls here?
- Is this abstraction decoupling things that actually need to change independently?
- Are components communicating through direct references where a message-broadcast mechanism would preserve decoupling?
- Does removing this coupling require changing the interface of more than one class?

### State

- Is mutable state centralized appropriately for this subsystem's scale?
- Is global access mediated through Service Locator rather than raw globals or Singletons?
- Are state transitions explicit (State pattern) or implicit (scattered conditionals)?
- Is shared mutable state causing unintended cross-system side effects?
- Is derived data being recomputed eagerly when a Dirty Flag could defer it until it is actually needed?
- Could a type change at runtime (Type Object with mutable type pointer) produce invalid invariants that are not being validated?

### Performance

- Are heap allocations occurring during gameplay frames?
- Is cache locality considered for hot-path subsystems?
- Is runtime polymorphism (virtual dispatch, pointer-to-base) used in tight loops where a data-oriented alternative exists?
- Are object lifetimes and ownership clear enough to avoid unexpected allocations?
- Does the hot-path update loop chase pointers through scattered heap objects rather than iterating a flat array?
- Are inactive objects in a tight update loop causing unnecessary cache-line loads and branch mispredictions?
- Is the pool sized for worst-case peak load, and is there a defined overflow strategy?

### Extensibility

- Will adding a new behavior require modifying existing classes?
- Could composition (Component) replace inheritance here without significant cost?
- Is behavior variation handled by the right mechanism for its scale and frequency of change?
- Would Type Object or Bytecode replace this subclass hierarchy and support runtime extensibility without recompilation?
- Is the Subclass Sandbox base class accreting enough provided operations to become a maintenance burden?
- Could this fixed enum-based type system be replaced by Type Object to allow designer-defined types?

### Complexity

- Is the chosen pattern solving a real, present problem rather than a hypothetical future one?
- Is the abstraction cost proportional to the actual benefit at current codebase scale?
- Would a simpler direct approach work given the current size and team?
- Is this pattern being applied because it fits, or because it's familiar?
- Is a Service Locator being used where explicit dependency injection (passing the object as a parameter) is practical?
- Is a Singleton being justified by convenient access rather than by a genuine requirement for singleness?
- Is a Bytecode VM being built without budgeting for the required front-end authoring tool?
