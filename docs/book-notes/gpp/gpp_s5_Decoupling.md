## Component

### Core Intent

Decompose a monolithic entity into a container that owns a set of independent component objects, one per domain, so domains remain decoupled from each other while composing freely.

### Problem It Solves

A game entity class that handles input, physics, rendering, and AI in one file becomes unmaintainable as every programmer must edit the same class, every domain couples to every other, and no behavior subset can be reused across entity types without inheritance-driven duplication. Inheritance cannot express arbitrary capability combinations without the Deadly Diamond or exponential subclass counts.

### Engineering Motivation

Godot's SceneTree is a native Component implementation: child Nodes are the components, the parent Node is the container, each component runs its own `_physics_process` independently, and the `.tscn` file is the factory. The C++ infrastructure the pattern required — component arrays, manual wiring, virtual dispatch, factory functions — is replaced by scene composition and the SceneTree's automatic dispatch.

### When to Use

- An entity spans multiple independent domains (input, movement, health, AI, weapons) that different developers edit simultaneously.
- Behavior must be reused across entity types without forcing a shared inheritance ancestor.
- Capability should be assembled from existing pieces in the editor by scene composition rather than subclassing.
- Domain-specific logic must be individually activatable and deactivatable at runtime.

### When NOT to Use

- The entity has one or two cohesive concerns; child node overhead and `get_parent()` indirection cost more than the coupling being avoided.
- Entity count is large enough that per-entity SceneTree callback overhead is measurable — use a single system node with a typed `Array` instead.
- The codebase is early-stage; add component structure when the monolith problem actually appears, not speculatively.

### Main Tradeoffs

| Benefit                                                                        | Cost                                                                                                                      |
| ------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| Domains are isolated; a physics developer never edits animation code           | `@onready` wiring and `get_parent()` casts add indirection that fails silently when scene structure changes               |
| Behaviors are reusable across entity types by reusing the component scene file | Inter-component ordering depends on tree order and `process_priority`; wrong order produces one-frame visual lag          |
| `.tscn` file assembles any capability combination without code                 | Components that need to talk frequently acquire direct references, reconstructing the coupling the pattern removed        |
| `set_process(false)` deactivates a domain with zero loop overhead              | Components removed from the scene mid-frame require deferred removal; never call `remove_child` inside `_physics_process` |

### Common Misuse

Components that frequently communicate acquire direct `get_node()` references to each other, coupling sibling components to specific scene paths — the same cross-domain coupling the pattern was meant to eliminate, now hidden inside the component graph.

### Failure Mode

`GraphicsComponent` (or the animation `_process`) runs before `MovementComponent` has resolved position in the same physics tick; the entity renders one frame behind its physics state. The bug is in `process_priority` ordering, not in any individual component, making it difficult to attribute.

### Structural Model

```text
[Scene hierarchy as Component composition — container holds domain Nodes as children]

Player (CharacterBody2D)                  ← thin container; pan-domain state (velocity)
├── MovementComponent (Node)              ← physics domain; _physics_process
│       reads Input, writes velocity → get_parent().move_and_slide()
├── HealthComponent (Node)                ← health domain; signal emitter
│       health_changed --signal--> UIHealthBar._on_health_changed
│       depleted       --signal--> Player._on_depleted
└── WeaponComponent (Node)                ← combat domain; _physics_process
        fire() → instantiates projectile; no knowledge of HealthComponent

[.tscn file IS the factory — no code factory function needed]
player.tscn  =  Player ▶ MovementComponent, HealthComponent, WeaponComponent
enemy.tscn   =  Enemy  ▶ PatrolComponent,   HealthComponent
turret.tscn  =  Turret ▶ AimComponent,      WeaponComponent

[Component communication options — choose by coupling tolerance]
A. Via parent node state:    get_parent().velocity += dir * speed  (zero coupling, order-dependent)
B. Via signal:               health.depleted.connect(player._on_depleted)  (loose, fire-and-forget)
C. Via @onready reference:   @onready var weapon: WeaponComponent = $WeaponComponent  (tight, tightly-related pairs only)

[Update ordering]
SceneTree dispatches _physics_process in tree order, modified by process_priority (int, lower = earlier).
    MovementComponent.process_priority = 0   ← input → velocity first
    WeaponComponent.process_priority   = 1   ← reads resolved position
```

### Godot Adaptation Notes

- The SceneTree child-node hierarchy IS the Component pattern; no custom component container class or update loop is needed.
- `@onready var health: HealthComponent = $HealthComponent` is the wiring pattern; it fails gracefully at startup rather than silently at runtime if the node path is wrong.
- `process_priority: int` (lower = earlier) on each component enforces update ordering within a parent; use it wherever one component depends on another having run first this tick.
- Pan-domain state (position, velocity, current health fraction) belongs on the container node; it is the zero-coupling communication channel between components that do not need to reference each other directly.
- A `.tscn` scene file assembles any component combination; swapping one component node for another changes entity behavior with zero code changes.
- `process_mode = PROCESS_MODE_DISABLED` on the parent propagates to all components simultaneously — one call disables the entire entity.
- For high entity counts, replace per-entity `_physics_process` callbacks with a single system node iterating a typed `Array`; this removes per-node SceneTree dispatch overhead while keeping the compositional design.
- Script composition via `Resource`-held `RefCounted` objects is the correct choice for components that are purely behavioral and need no SceneTree presence, no `_physics_process`, and no child nodes.

### Gameplay-Level Usage

A `CombatSystem` node queries `get_nodes_in_group(&"combatants")` and iterates typed `CombatComponent` references for hit resolution; each entity owns a `CombatComponent` Node that encapsulates its combat rules. Adding a new entity type to the combat system requires only adding it to the group and giving it a `CombatComponent` child — no changes to `CombatSystem`.

### Entity-Level Usage

A `Player` scene contains `MovementComponent`, `HealthComponent`, and `WeaponComponent` as child Nodes. The `Player` script holds `@onready` references to each and wires signals in `_ready()`; movement, health, and weapon logic never appear in the same file. Swapping `MovementComponent` for `FlyingMovementComponent` changes the entity's locomotion entirely by replacing one child scene node.

### Engine/System-Level Usage

An `EnemySpawner` instantiates `enemy.tscn` and immediately calls `get_node("PatrolComponent").set_origin(spawn_point)` to configure the patrol component before the enemy becomes active. A `LevelManager` activates and deactivates entire entity capability sets by toggling `process_mode` on the container node rather than iterating individual components.

### Suggested Script Layout

```text
res://entities/player/
    player.tscn             # Player (CharacterBody2D)
    player.gd               # Thin container — @onready refs + signal wiring only
    components/
        movement_component.gd   # Node — _physics_process, velocity control
        health_component.gd     # Node — signal emitter, no processing
        weapon_component.gd     # Node — _physics_process, fire logic
res://entities/enemy/
    enemy.tscn              # Enemy (CharacterBody2D)
    enemy.gd
    components/
        patrol_component.gd     # Node — reused across enemy types
        health_component.gd     # same file as player's HealthComponent
res://systems/
    combat_system.gd        # Node — queries group "combatants", no per-entity knowledge
```

### Godot Performance Notes

**Node count implications** — Each component is a SceneTree Node; a scene with five component children adds five entries to the tree traversal per frame. For entities in the hundreds, profile whether individual `_physics_process` overrides on each component are cheaper than one system node iterating a typed array.

**SceneTree traversal cost** — `get_parent()` and `$ChildNode` resolution are O(1) cached lookups; the overhead is negligible for typical entity counts. `get_nodes_in_group()` traverses the group registry and should be called once at `_ready()` and cached if the group membership is stable.

**Signal connection overhead** — Components wired via signals in `_ready()` pay O(1) connection cost once; per-frame signal emission is O(n) in connected receivers. For components emitting on every `_physics_process` tick, prefer direct method calls on a cached reference for single-receiver communication.

**Typed vs. untyped references** — `@onready var health: HealthComponent = $HealthComponent` provides typed access with IDE completion and avoids per-call type inference overhead at dispatch time.

### Godot Anti-Patterns

**`get_node()` paths in component logic** — A component calling `get_parent().get_node("../OtherComponent")` or `get_tree().get_root().get_node("path")` inside `_physics_process` is coupling to a fragile scene path that breaks on any scene refactor. Components communicate via parent-state, signals, or cached `@onready` references only.

**Logic in the container node** — Placing gameplay logic in the `Player` or `Enemy` script rather than in components defeats the pattern; the container should hold only signal wiring and `@onready` references. If the container script grows beyond twenty lines of logic, that logic belongs in a component.

**Deep component inheritance** — Subclassing `HealthComponent` to produce `ArmoredHealthComponent` creates a component inheritance tree alongside the scene hierarchy. Prefer composition: wrap `HealthComponent` with an `ArmorComponent` sibling rather than subclassing.

### GDScript Structural Example

```gdscript
# health_component.gd — health domain component; signal-based communication
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

func is_alive() -> bool:
    return _current > 0
```

```gdscript
# player.gd — thin container; wiring only, zero domain logic
# Scene: Player (CharacterBody2D) ▶ MovementComponent, HealthComponent, WeaponComponent
class_name Player
extends CharacterBody2D

@onready var movement: MovementComponent = $MovementComponent
@onready var health: HealthComponent = $HealthComponent
@onready var weapon: WeaponComponent = $WeaponComponent

func _ready() -> void:
    health.depleted.connect(_on_depleted)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed(&"jump"):
        movement.request_jump()
    if event.is_action_pressed(&"attack"):
        weapon.fire()

func _on_depleted() -> void:
    movement.set_physics_process(false)
    weapon.set_physics_process(false)
    $DeathEffect.emitting = true
```

### Related Patterns

Update Method, Data Locality, Strategy

### Competing Patterns

Monolithic entity with Update Method, Inheritance hierarchy, ECS-style system-per-component-type

### Key Implementation Notes

- `process_priority: int` (lower = earlier) enforces component update ordering; set it explicitly wherever one component reads state that another writes.
- Pan-domain state — position, velocity, current stamina fraction — belongs on the container, not on any one component.
- `.tscn` scene files are the factory; no code factory functions are needed unless entity configuration must be generated procedurally.
- `process_mode = PROCESS_MODE_DISABLED` on the container propagates to all children simultaneously; use it for entity deactivation.
- `queue_free()` is deferred to end-of-frame and safe to call from any component callback; `remove_child()` is not deferred and is unsafe mid-frame.
- For closely coupled component pairs (animation + rendering), direct `@onready` references are correct and preferable to routing through signals or parent state.
- Groups provide a lightweight form of component querying across entity types; `get_nodes_in_group(&"has_health")` retrieves all entities with a `HealthComponent` regardless of type.

---

## Event Queue

### Core Intent

Decouple when a request or notification is sent from when it is processed by buffering it in a queue that the receiver drains at a controlled point in time.

### Problem It Solves

A synchronous `play_sound()` call executes on the sender's thread, at the sender's moment, with the sender's timing — making batching, coalescing, and prioritization impossible while blocking the caller until the audio system responds. Any system where the producer's rate or timing differs from the consumer's cannot be bridged by direct calls or even by Observer alone.

### Engineering Motivation

Producers and consumers of a service naturally run at different points in the game loop and at different rates; a queue between them reconciles push-side production with pull-side processing without coupling their execution timing. `call_deferred()` is Godot's built-in single-event queue for the common case of temporal decoupling within one thread; a ring buffer is warranted only when aggregation, coalescing, or true capacity management is needed.

### When to Use

- Sender and receiver must be decoupled in time — the receiver must control when it processes requests, not just who sends them.
- Requests must be aggregated, coalesced, prioritized, or rate-limited before processing (e.g., audio deduplication, animation blending).
- Producer and consumer run on different threads; a queue with one lock per boundary is the minimal safe interface.
- The sender must not block on, or be affected by, the receiver's processing latency.

### When NOT to Use

- Only identity decoupling is needed — Observer is simpler, synchronous, and retains call-stack traceability.
- The sender needs a synchronous result; a queue cannot return a value to the enqueuing caller.
- `call_deferred()` covers the use case — a full ring buffer is not justified for simple end-of-frame delivery.
- A central global queue for all game-system communication is proposed; this recreates every global-state coupling risk behind a polished interface.

### Main Tradeoffs

| Benefit                                                                   | Cost                                                                                                  |
| ------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| Sender never blocks on receiver processing time                           | Events carry stale-world risk: world state may change between enqueue and dequeue                     |
| Receiver controls timing, batching, coalescing, and prioritization        | Feedback cycles are silent: A→B→A loops don't stack-overflow; they circulate indefinitely burning CPU |
| Natural thread boundary: enqueue is the only cross-thread operation       | Events must capture all context at enqueue time; queued payloads are larger than synchronous ones     |
| `call_deferred()` provides the single-event case with zero infrastructure | A full ring buffer requires capacity planning; overflow is an assert, not a graceful degradation      |

### Common Misuse

Building one global `EventBus` Autoload for all game-system communication and routing every cross-system notification through it — producing the same hidden dependency web and unauditable coupling graph as raw globals, with a more polished surface.

### Failure Mode

A handler enqueues a new event in response to receiving one; unlike a synchronous cycle (which stack-overflows visibly), the queue silently recirculates these events across frames, burning CPU and producing behaviour that is extremely difficult to trace back to the originating handler.

### Structural Model

```text
[Ring buffer — O(1) enqueue/dequeue, no per-event heap allocation]

          _head                            _tail
             ↓                               ↓
[ ] [id:5,v:0.8] [id:2,v:1.0] [id:7,v:0.5] [ ] [ ]
  ↑                                                 ↑
  wraps mod MAX_PENDING                     wraps mod MAX_PENDING

Sender (any _physics_process, any signal handler):
    play_sound(SFX_FOOTSTEP, 0.5)
    → coalesce: SFX_FOOTSTEP already pending? raise volume and return
    → otherwise: _sound_ids[_tail] = id; _tail = (_tail + 1) % MAX_PENDING

Drain (one controlled point — AudioQueue._physics_process):
    while _head != _tail:
        AudioBus.play_by_id(_sound_ids[_head], _volumes[_head])
        _head = (_head + 1) % MAX_PENDING

[call_deferred() — lightweight single-event temporal decoupling, built into Godot]
    node.call_deferred(&"method")          ← deferred to end of current frame
    my_signal.emit.call_deferred(arg)      ← deferred signal emission
    → correct for: one event, no coalescing, frame-boundary delivery is sufficient
    → do NOT use: for high-frequency events that need batching or aggregation

[Godot AudioServer — already a queue-based system for standard playback]
    AudioStreamPlayer.play() → internal request buffer → audio thread
    → custom queue needed only when: deduplication, channel budgeting, or priority control
    → is required beyond what AudioServer provides out of the box

[Thread-safe delivery pattern]
    Worker thread: _queue.append(data); mutex.unlock()
    Main thread:   mutex.lock(); var items = _queue.duplicate(); _queue.clear(); mutex.unlock()
                   for item in items: call_deferred(&"_process_item", item)
```

### Godot Adaptation Notes

- `call_deferred(&"method_name")` and `call_deferred(&"emit", args)` on a signal are Godot's built-in single-event queues; use them before reaching for a ring buffer.
- Godot's `AudioServer` is already a queue-based system that batches sound requests and processes them on the audio thread; custom audio queuing is only needed for deduplication or priority control beyond what `AudioStreamPlayer` provides.
- A ring buffer with pre-allocated `PackedInt32Array` and `PackedFloat32Array` backing stores avoids per-event heap allocation and keeps the structure cache-friendly — the direct GDScript equivalent of the C++ fixed-size array.
- GDScript `Array` resizing is O(n); pre-resize both backing arrays in `_ready()` and never call `append()` on them after initialization.
- For cross-thread event delivery: enqueue from the worker thread using `Mutex`, then call `call_deferred()` from the main thread handler to deliver to SceneTree-bound objects safely.
- The `EventBus` Autoload pattern from the Observer translation should remain a typed signal-only declaration file and must not become a queue; signals are synchronous and the pattern distinctions matter at scale.
- What is unchanged from the C++ implementation: the ring buffer head/tail index arithmetic, the coalesce-on-enqueue discipline, and the "events must be self-contained at enqueue time" requirement.

### Gameplay-Level Usage

A combat system enqueues damage events in a typed ring buffer during `_physics_process`; the `UISystem` drains the queue at the start of its `_process` pass, updating floating damage numbers and health bars after all physics simulation is settled for the frame. A sound effect manager deduplicates simultaneous requests — multiple footsteps in one frame from different characters raise volume rather than triggering multiple overlapping samples.

### Entity-Level Usage

A bullet emitter queues spawn requests during a burst-fire `_physics_process` pass; an `ObjectPoolDispatcher` drains the queue and distributes pool-allocated bullet instances at the start of the next frame, decoupling the emitter's fire rate from the pool's allocation rate. An AI decision component enqueues state-change requests so the FSM drains and validates them at a single known point rather than responding to mid-frame state changes.

### Engine/System-Level Usage

A `WorkerThread` performs pathfinding off the main thread and pushes results into a `Mutex`-guarded `Array`; the main thread's `_physics_process` checks the array, locks, copies completed paths, and clears the buffer — all without calling `call_deferred()` from the worker thread. A loading system enqueues asset-ready notifications during background loading; the main thread drains them on the first frame after the loading screen clears.

### Suggested Script Layout

```text
res://systems/
    audio_queue.gd          # Node — ring buffer + coalescing for SFX requests
    damage_event_queue.gd   # Node — typed ring buffer for UI damage display
    spawn_request_queue.gd  # Node — decouples emitter timing from pool allocation
res://autoloads/
    event_bus.gd            # Autoload — typed signal declarations only; NOT a queue
```

### Godot Performance Notes

**Memory allocation patterns** — Pre-allocate backing arrays (`PackedInt32Array`, `PackedFloat32Array`) to `MAX_PENDING` at `_ready()`. Never call `append()` after initialization; index directly into the pre-sized arrays to avoid reallocation.

**SceneTree traversal cost** — The ring buffer drain loop accesses packed arrays directly; no SceneTree traversal occurs. Keep the drain loop in `_physics_process` unless the consumer genuinely runs at a different rate, in which case a dedicated `Node` with its own `_process` is correct.

**Signal connection overhead** — If the queue notifies consumers via signal on each drain, `emit()` cost is O(n) in receivers per emission. For a single consumer, a direct method call on a cached reference is preferable.

**Typed vs. untyped Array performance** — `PackedInt32Array` and `PackedFloat32Array` avoid GDScript per-element type overhead and are contiguous in memory; prefer them over `Array[int]` and `Array[float]` for ring buffer backing stores.

### Godot Anti-Patterns

**Global event bus used as a queue** — Routing all game-system events through one `EventBus` Autoload makes every system an implicit dependency of every other system. The EventBus should be narrowly scoped to cross-domain events that are genuinely impossible to route directly.

**Enqueuing from a handler** — A `play_sound()` call inside an audio queue drain handler enqueues a new event into the same queue it is draining, creating a cycle. Establish and document a "no re-enqueue" rule for every handler registered to any queue.

**Using `call_deferred()` for aggregation** — Calling `call_deferred(&"play_sound", id, vol)` multiple times per frame for the same sound queues multiple independent deferred calls, producing duplicate audio rather than coalescing volume. Use a ring buffer with coalesce-on-enqueue for aggregation cases.

### GDScript Structural Example

```gdscript
# audio_queue.gd — ring buffer with coalescing; temporal + aggregation decoupling for SFX
class_name AudioQueue
extends Node

const MAX_PENDING: int = 16

var _sound_ids: PackedInt32Array
var _volumes: PackedFloat32Array
var _head: int = 0
var _tail: int = 0

func _ready() -> void:
    _sound_ids = PackedInt32Array()
    _volumes = PackedFloat32Array()
    _sound_ids.resize(MAX_PENDING)
    _volumes.resize(MAX_PENDING)

# Called from any game system — safe from _physics_process or signal handlers
func play_sound(sound_id: int, volume_db: float = 0.0) -> void:
    var i: int = _head
    while i != _tail:
        if _sound_ids[i] == sound_id:
            _volumes[i] = maxf(_volumes[i], volume_db)  # coalesce: raise volume only
            return
        i = (i + 1) % MAX_PENDING
    assert((_tail + 1) % MAX_PENDING != _head, "AudioQueue: capacity exceeded — raise MAX_PENDING")
    _sound_ids[_tail] = sound_id
    _volumes[_tail] = volume_db
    _tail = (_tail + 1) % MAX_PENDING

# Drain at one controlled point per frame — never mid-physics-step
func _physics_process(_delta: float) -> void:
    while _head != _tail:
        AudioBus.play_by_id(_sound_ids[_head], _volumes[_head])
        _head = (_head + 1) % MAX_PENDING
```

### Related Patterns

Observer, Command, Object Pool

### Competing Patterns

Observer (use when temporal decoupling is not needed), `call_deferred()` (use for single-event end-of-frame delivery), Direct Call

### Key Implementation Notes

- Use `call_deferred()` before building a ring buffer; it covers the single-event temporal decoupling case with no infrastructure.
- Pre-allocate ring buffer backing arrays at `_ready()` to `MAX_PENDING`; never resize or `append()` during gameplay frames.
- Coalesce on enqueue — scan for an existing matching entry and raise the field value rather than adding a duplicate slot.
- Every event must be self-contained at enqueue time; world state at drain time may differ from world state at enqueue time.
- Assert on overflow with a clear message; never silently drop events — overflow is a capacity tuning bug, not normal operation.
- Establish a "no re-enqueue from handler" rule for every queue; circular queueing is silent, persistent, and difficult to profile.
- For cross-thread delivery: enqueue under `Mutex` from the worker thread; drain under `Mutex` from the main thread; use `call_deferred()` for any SceneTree-bound follow-up calls from the drain.

---

## Service Locator

### Core Intent

Provide a global point of access to a service through an abstract interface, decoupling callers from both the concrete implementing class and the mechanism used to acquire the instance.

### Problem It Solves

Cross-cutting infrastructure services (audio, logging, analytics) are needed throughout the codebase; direct calls to a concrete Autoload couple every caller to one implementation and prevent swapping that implementation for a null service in tests, a logging decorator in development, or a platform variant at runtime. A raw Autoload solves global access but hard-codes the concrete class at every call site and provides no null-service safety.

### Engineering Motivation

Godot's Autoloads already solve global access; the Service Locator adds a provider abstraction layer on top. The concrete class is hidden behind a `RefCounted` interface; callers see only the forwarding methods on the Autoload shell. This enables the null-service default (calls are always safe before registration), the Decorator pattern (wrap the real provider with a logger, no call-site changes), and test injection (replace the provider with a mock at test setup).

### When to Use

- The service is genuinely cross-cutting ambient infrastructure — audio playback, structured logging, analytics — not a domain-specific service that should be passed explicitly.
- The service implementation must be swappable at runtime, across configurations, or for test injection without modifying call sites.
- A null provider (does nothing) or a logging decorator is required for development and test isolation.
- Threading the service through every call layer as a parameter is genuinely prohibitive given the project's call depth.

### When NOT to Use

- Explicit dependency injection (passing the service as a parameter) is practical — always prefer it; the dependency is transparent and impossible to miss.
- The service is domain-specific and used in one subsystem; pass it explicitly within that subsystem.
- The implementation will never need to be swapped; a plain Autoload accessed directly is simpler and equally correct.
- The temptation is to register domain services through the locator to avoid passing them around — this recreates a hidden global namespace.

### Main Tradeoffs

| Benefit                                                                         | Cost                                                                                                               |
| ------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Callers decouple from concrete type and acquisition mechanism                   | Dependencies are invisible at call sites; what a function uses requires tracing through the Autoload shell         |
| Implementation swappable at runtime — null, decorated, platform-specific        | `_provider` must be set before first use; initialization order bugs are silent until a `push_warning` fires        |
| Null provider makes every call safe even before registration                    | Null provider silently absorbs calls; missing-registration bugs become invisible behavioral failures unless warned |
| Decorator wraps a real provider for logging/profiling with no call-site changes | Global Autoload carries global-state risks; every script can reach any service at any point                        |

### Common Misuse

Registering domain-specific services through the locator to avoid threading them as parameters, producing a "grab-bag" global namespace where every system implicitly depends on the locator and actual dependencies become impossible to audit.

### Failure Mode

A provider is not registered before the first call; if the Autoload's `_provider` is `null` (rather than a `NullProvider`), the forwarding method crashes at the call site, not at the missing registration — making the initialization-order bug difficult to locate. If the `NullProvider` is the default but emits no warning, the missing registration is entirely invisible.

### Structural Model

```text
[Autoload as Service Locator — provider abstraction over raw Autoload access]

Raw Autoload (Singleton):    AudioBus.play(stream)     ← direct implementation; not swappable
Service Locator:             AudioService.play(stream) ← delegates to registered provider

[Structure]
AudioService (Autoload "AudioService")       ← the locator shell
    _provider: AudioProvider                  ← initialized to NullAudioProvider in _ready()
    provide(impl: AudioProvider)             ← registration entry point
    play(stream, vol) → _provider.play(...)  ← forwarding; never direct implementation

AudioProvider (RefCounted)                   ← abstract interface base
NullAudioProvider   extends AudioProvider    ← does nothing; push_warning in debug builds
RealAudioProvider   extends AudioProvider    ← real SFX pool; registered at startup
LoggingAudioProvider extends AudioProvider   ← Decorator: logs, then delegates to _inner

[Null service guarantee]
AudioService._ready():  _provider = NullAudioProvider.new()
→ AudioService.play() is always safe before registration — never crashes

[Decorator chain — no call-site changes]
var real   := RealAudioProvider.new(sfx_players)
var logged := LoggingAudioProvider.new(real)
AudioService.provide(logged)
→ all calls: print("[Audio] play …") then delegate to real provider

[Initialization order — explicit, not lazy]
_app_bootstrap.gd _ready():
    1. AudioService.provide(RealAudioProvider.new(...))   ← registered before any scene loads
    2. get_tree().change_scene_to_packed(main_menu)

[Prefer explicit injection for domain services]
    func fire(weapon: WeaponDef, audio: AudioProvider)  ← explicit; testable; auditable
    AudioService.play(sfx_stream)                       ← global; acceptable for ambient infra
```

### Godot Adaptation Notes

- A raw Autoload IS a Godot Singleton; the Service Locator pattern adds the `AudioProvider` abstraction layer only when swappability or a null service is a genuine requirement — not by default.
- Autoloads initialize at project startup in registration order; initialize `_provider = NullAudioProvider.new()` in `_ready()` so every forwarding method is safe from the first frame.
- GDScript has no interface keyword; use a `RefCounted` base class with `pass`-body methods as the provider contract. Type the `_provider` field explicitly (`var _provider: AudioProvider`) to retain IDE completion and catch assignment errors.
- The null provider should call `push_warning()` in debug builds when any method is invoked so that missing-registration bugs produce a visible editor warning rather than silent no-ops.
- The Decorator pattern maps cleanly to `LoggingAudioProvider extends AudioProvider` that stores an `_inner: AudioProvider` reference; swap it in by calling `provide(LoggingAudioProvider.new(current_provider))` and out by calling `provide(real_provider)` again.
- For testing: call `AudioService.provide(MockAudioProvider.new())` in the test's `_ready()` and restore with `provide(RealAudioProvider.new(...))` in `after_each()` — no test isolation scaffolding required.
- Scope the locator to the subsystem that needs it; not every project-wide service warrants a full provider abstraction. A plain Autoload with direct implementation is correct for services that will never need swapping.

### Gameplay-Level Usage

A `LoggingAudioProvider` wraps the `RealAudioProvider` during alpha and certification review builds; QA sees every sound trigger in the output log without any code change to game systems. A `NullAudioProvider` is registered automatically in headless server builds so that gameplay code that calls `AudioService.play()` compiles and runs without modification on a dedicated server with no audio hardware.

### Entity-Level Usage

A `StatusEffect` base class (Subclass Sandbox) calls `AudioService.play(on_apply_sound)` in its provided `_play_sound()` operation; swapping the registered provider to `LoggingAudioProvider` during a debugging session logs every status effect sound trigger without modifying any `StatusEffect` subclass. A test that validates status effect application registers a `MockAudioProvider` to count `play()` invocations without producing actual audio output.

### Engine/System-Level Usage

A bootstrap `Node` in the main scene's `_ready()` registers the real provider before `change_scene_to_packed()` loads any gameplay scene; all subsequent calls to `AudioService.play()` in any scene are guaranteed to reach the real implementation. A platform-specific `ConsoleAudioProvider` that wraps a console SDK is registered in a platform build step by swapping the provider registration script — no call-site changes across the entire project.

### Suggested Script Layout

```text
res://services/audio/
    audio_provider.gd           # RefCounted base — provider interface contract
    null_audio_provider.gd      # RefCounted — push_warning in debug; used as default
    real_audio_provider.gd      # RefCounted — actual SFX pool implementation
    logging_audio_provider.gd   # RefCounted — Decorator for development sessions
res://autoloads/
    audio_service.gd            # Autoload "AudioService" — locator shell; forwarding only
res://bootstrap/
    app_bootstrap.gd            # Node — registers real providers before first scene loads
```

### Godot Performance Notes

**SceneTree traversal cost** — The forwarding methods on the Autoload shell are one virtual dispatch through `_provider.method()`; negligible. The Decorator adds one additional level of indirection per wrapped call, still negligible for audio or logging frequency.

**Memory allocation patterns** — Provider objects are `RefCounted`; they remain alive as long as the Autoload shell holds `_provider`. The shell allocates `NullAudioProvider.new()` once at `_ready()` and replaces it once at registration. There is no per-call allocation.

**Signal connection overhead** — The Service Locator introduces no signal connections; it is a direct method delegation chain. If the provider emits signals (e.g., `played.emit(stream)`), connection overhead is O(1) per connection and O(n) per emission as with any signal.

### Godot Anti-Patterns

**Plain Autoload access treated as Service Locator** — Calling `AudioBus.play(stream)` directly on a concrete Autoload without a provider interface is a Singleton, not a Service Locator. The pattern's null-service safety, swap-at-runtime, and Decorator benefits require the `AudioProvider` abstraction layer; without it, the indirection adds cost without architectural benefit.

**Domain services in the locator** — Registering `CombatSystem`, `InventoryManager`, or `DialogueSystem` through a locator to avoid parameter passing creates the hidden global namespace anti-pattern. Service Locator is justified only for genuinely ambient infrastructure services.

**Lazy null-provider** — Defaulting `_provider` to `null` rather than `NullAudioProvider.new()` in `_ready()` means a missing-registration bug produces a `null` method call crash at the call site. The null provider must be the default from the first frame.

### GDScript Structural Example

```gdscript
# audio_provider.gd — provider interface contract; all implementations extend this
class_name AudioProvider
extends RefCounted

func play(stream: AudioStream, volume_db: float = 0.0) -> void: pass
func stop_all() -> void: pass
```

```gdscript
# audio_service.gd (Autoload "AudioService") — locator shell; never holds implementation
class_name AudioService
extends Node

var _provider: AudioProvider = null

func _ready() -> void:
    _provider = NullAudioProvider.new()  # always safe before real registration

func provide(impl: AudioProvider) -> void:
    assert(impl != null, "Pass NullAudioProvider.new() explicitly to reset the provider.")
    _provider = impl

func play(stream: AudioStream, volume_db: float = 0.0) -> void:
    _provider.play(stream, volume_db)

func stop_all() -> void:
    _provider.stop_all()
```

```gdscript
# logging_audio_provider.gd — Decorator: logs every call, then delegates to inner provider
class_name LoggingAudioProvider
extends AudioProvider

var _inner: AudioProvider

func _init(inner: AudioProvider) -> void:
    assert(inner != null, "LoggingAudioProvider requires a non-null inner provider.")
    _inner = inner

func play(stream: AudioStream, volume_db: float = 0.0) -> void:
    print("[AudioService] play: %s @ %.1f dB" % [stream.resource_path.get_file(), volume_db])
    _inner.play(stream, volume_db)

func stop_all() -> void:
    print("[AudioService] stop_all")
    _inner.stop_all()

# Bootstrap usage in app_bootstrap.gd _ready():
# var real  := RealAudioProvider.new(sfx_stream_players)
# AudioService.provide(LoggingAudioProvider.new(real))  ← wrap with logger
# AudioService.provide(NullAudioProvider.new())         ← revert for tests
```

### Related Patterns

Singleton, Null Object, Decorator, Subclass Sandbox

### Competing Patterns

Explicit Dependency Injection, Singleton (raw Autoload without provider abstraction)

### Key Implementation Notes

- A raw Autoload IS a Singleton; add the provider abstraction only when swappability or null-service safety is a genuine requirement.
- Initialize `_provider = NullAudioProvider.new()` in `_ready()`, never as a field default value; field initializers run before `_ready()` and may fire before other Autoloads are initialized.
- `NullAudioProvider` must call `push_warning()` on every method invocation in debug builds; a null service that silently absorbs calls turns missing-registration bugs invisible.
- The locator owns no provider lifetime; the code that calls `provide()` owns the provider object and is responsible for its lifecycle.
- Scope the locator pattern to genuinely ambient infrastructure — audio, logging, analytics; pass domain services explicitly as function parameters.
- Prefer `provide(NullAudioProvider.new())` over `provide(null)` for resetting the service; a null check on `_provider` is a runtime safety net, not the primary design.
- For tests: call `AudioService.provide(MockAudioProvider.new())` in the test's setup and restore it in teardown; no test isolation framework required.

---
