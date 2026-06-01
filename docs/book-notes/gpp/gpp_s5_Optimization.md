## Data Locality

### Core Intent

Arrange data that is processed together so it is contiguous in memory, maximizing CPU cache utilization and eliminating the stall cycles caused by cache misses.

### Problem It Solves

A game loop that updates entities by chasing object pointers through a scattered heap pays a cache miss penalty on every dereference; the same computation over contiguous data can be fifty times faster. Per-entity SceneTree dispatch in Godot is the observable equivalent: one `_physics_process` callback per Node per frame adds SceneTree traversal and virtual-call overhead that accumulates at high entity counts even when no cache miss occurs.

### Engineering Motivation

GDScript heap objects are pointer-scattered — `Array[Enemy]` is an array of Variant pointers, not a contiguous block of enemy data. `PackedFloat32Array`, `PackedVector2Array`, and other `Packed*Array` types are the exception: they store contiguous C-level data and are the closest GDScript equivalent of C++ flat arrays. Profile before restructuring; the Godot profiler reveals GDScript call-frame overhead, which is the user-visible symptom before cache misses become the actual bottleneck.

### When to Use

- A hot-path system node iterates hundreds or thousands of entities each `_physics_process` and profiler output shows that per-entity GDScript dispatch is the measured bottleneck.
- The system is homogeneous — all entities process the same fields in the same loop — making a packed parallel-array layout natural.
- Rendering thousands of identical mesh instances; `MultiMeshInstance3D` is the direct Godot-native SoA implementation.
- A GDExtension module is being written for a performance-critical subsystem; C/Rust layout control makes Data Locality fully achievable.

### When NOT to Use

- The system processes fewer than a few hundred entities per frame; SceneTree dispatch overhead is negligible and refactoring adds complexity for no measurable gain.
- Entities are accessed infrequently or on cold paths; restructuring for cache performance is premature optimization.
- Per-entity heterogeneity (wildly different behavior per entity) makes a homogeneous packed array impractical.

### Main Tradeoffs

| Benefit                                                                                                            | Cost                                                                                                               |
| ------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------ |
| `Packed*Array` types store contiguous C memory; straight-scan access has no Variant overhead per element           | GDScript cannot enforce struct field layout; true SoA requires GDExtension or careful `Packed*Array` decomposition |
| Replacing per-entity `_physics_process` callbacks with one system-node loop eliminates SceneTree dispatch overhead | Packed active-object arrays require an index-swap on deactivation; raw Node references into the pool become stale  |
| `MultiMeshInstance3D` uploads transform data in one GPU DMA transfer — the rendering SoA                           | Hot/cold splitting is manual; Godot provides no struct-field annotation for cache layout                           |
| GDExtension (C/Rust) achieves true struct-array layout with no GDScript overhead                                   | Code moved to GDExtension is no longer editable in the Godot editor; iteration cost increases                      |

### Common Misuse

Restructuring data for cache performance based on intuition rather than profiler output, then discovering the real bottleneck was GDScript arithmetic per element (which packing does not fix) or an unrelated system entirely.

### Failure Mode

A packed active-object array is introduced but activation and deactivation continue using `set_process(true/false)` on individual Nodes instead of the index-swap mechanic; active and inactive objects remain interleaved, the loop iterates both, and the cache benefit of contiguous active data is entirely lost.

### Structural Model

```text
[Per-entity Node dispatch — fine for moderate counts, measurable overhead at scale]

SceneTree → Enemy_001._physics_process()  ← one callback dispatch per entity per frame
         → Enemy_002._physics_process()
         ...
         → Enemy_256._physics_process()  ← 256 SceneTree dispatch calls, 256 virtual invocations

[System-node with Packed*Arrays — eliminates per-entity SceneTree overhead]

EnemySystem (one Node)
    _positions:  PackedVector2Array [MAX]   ← contiguous C float pairs
    _velocities: PackedVector2Array [MAX]   ← contiguous C float pairs
    _health:     PackedFloat32Array [MAX]   ← contiguous C floats
    _active_count: int

    _physics_process: for i in _active_count: _positions[i] += _velocities[i] * delta
    → One _physics_process callback, straight scan over contiguous memory.

[Packed active objects — swap-on-deactivate keeps active prefix contiguous]
[live][live][live]...[live] | [dead][dead]...[dead]
             ↑ _active_count               ↑ dead region
despawn(idx): swap idx ↔ (_active_count−1), _active_count -= 1  ← O(1); no isActive check

[MultiMeshInstance3D — engine-native rendering SoA for thousands of instances]
MultiMesh.instance_transforms: PackedFloat32Array  ← one flat array, one GPU upload
→ Replace 1 000 individual MeshInstance3D nodes with one MultiMeshInstance3D.
→ No SceneTree node per instance; transform data written directly into the flat array.

[GDExtension — the only path to true C-level struct layout control]
C/Rust:  struct EnemyData { float x, y, vx, vy, hp; }  data[MAX];
         for (int i = 0; i < active; i++) update(&data[i], delta);
→ Use when profiler confirms GDScript throughput is the bottleneck, not dispatch.
```

### Godot Adaptation Notes

- `PackedFloat32Array`, `PackedVector2Array`, `PackedInt32Array`, and the other `Packed*Array` types store contiguous C-level memory; they are the GDScript equivalent of C++ flat arrays for numeric data.
- `Array[MyClass]` is an array of Variant pointers — each element access involves pointer indirection equivalent to the "AoS pointer-chasing" layout the pattern warns against.
- Replace per-entity `_physics_process` overrides with one system Node that iterates a typed `Array` or `Packed*Array` for the same pattern benefit; SceneTree dispatch elimination is the measurable equivalent of cache-miss reduction.
- `MultiMeshInstance3D` is the direct engine-native rendering SoA; replace a population of individual `MeshInstance3D` nodes with one `MultiMeshInstance3D` at counts above a few dozen instances.
- `RenderingServer` and `PhysicsServer2D`/`PhysicsServer3D` expose direct low-level APIs that bypass SceneTree node overhead entirely; use them for systems that need maximal throughput without GDExtension.
- The hot/cold split maps to separating per-frame fields (positions, velocities) into `Packed*Arrays` on the system node and leaving rarely-accessed fields (loot tables, display names) in per-entity `Resource` objects.
- Godot's built-in profiler (`Debugger → Profiler`) reports per-function GDScript time; use it to confirm the iteration loop is the bottleneck before any restructuring.
- True struct layout control requires GDExtension; move only the profiler-confirmed hot path, not entire systems speculatively.

### Gameplay-Level Usage

A projectile system maintains `PackedVector2Array` for positions and velocities and an `int _active_count` cursor; `_physics_process` runs one tight loop over the contiguous active prefix. Deactivated bullets swap with the last active index in O(1), keeping the active prefix tight without any gaps or branch-predicted `is_alive()` checks.

### Entity-Level Usage

A crowd-simulation component replaces individual `Enemy` nodes with a single `EnemySystem` node holding parallel `Packed*Arrays`. The scene hierarchy loses one Node per enemy; the update loop gains cache efficiency at the cost of per-enemy SceneTree identity (groups, signals, and unique node names become the component of the entity model, not the node itself).

### Engine/System-Level Usage

A particle effects layer uses `MultiMeshInstance3D` with instance transforms written from a `PackedFloat32Array` each `_physics_process`; the CPU writes transform data and the GPU reads it in one DMA transfer, replacing the per-`GPUParticles2D`-node update path entirely. A GDExtension physics integration module processes `EnemyData` structs in tight C loops, writing back updated positions into a `PackedVector2Array` that the GDScript rendering layer reads for visual updates.

### Suggested Script Layout

```text
res://systems/
    enemy_system.gd         # Node — PackedVector2Array positions/velocities; one _physics_process
    projectile_system.gd    # Node — packed active-array with swap-on-despawn
    crowd_renderer.gd       # Node — writes MultiMesh transform array from system data
res://extensions/
    physics_ext/            # GDExtension — C/Rust hot loop for CPU-critical simulation
```

### Godot Performance Notes

**Typed vs. untyped Array performance** — `PackedVector2Array` is a contiguous C array of `Vector2`; `Array[Vector2]` is an array of Variant-boxed `Vector2` values with per-element unboxing on access. Prefer `Packed*Arrays` for all numeric data in hot-path loops.

**SceneTree traversal cost** — Each Node with an active `_physics_process` override contributes one callback dispatch per frame. Collapsing N enemy nodes into one system node removes N−1 dispatch costs; this is the dominant gain before memory layout becomes the bottleneck.

**Node count implications** — `MultiMeshInstance3D` is one SceneTree node regardless of instance count; a forest of 10 000 trees that previously required 10 000 `MeshInstance3D` nodes collapses to one node with no per-tree SceneTree overhead.

**Memory allocation patterns** — Pre-allocate `Packed*Arrays` to `MAX_COUNT` at `_ready()` with `resize()`; never call `append()` or `push_back()` during gameplay frames on the hot-path arrays.

### Godot Anti-Patterns

**Assuming `Array[MyClass]` is cache-friendly** — `Array[MyClass]` holds Variant-wrapped object references; every element access involves a pointer dereference to the heap-allocated object. Use `Packed*Arrays` for the numeric fields and keep object identity (`Array[Node]`) separate.

**Premature packing** — Converting a system with 30 entities per frame from per-entity nodes to a system node based on a performance assumption rather than a profiler measurement. At 30 entities, per-node dispatch overhead is sub-microsecond; the refactor cost far exceeds any frame-time improvement.

**Ignoring MultiMeshInstance3D for visual populations** — Creating individual `MeshInstance3D` nodes for every tree, bullet spark, or crowd member when `MultiMeshInstance3D` would render the same population with one node and one GPU draw call.

### GDScript Structural Example

```gdscript
# enemy_system.gd — SoA-style system node; Packed*Arrays are contiguous C memory
class_name EnemySystem
extends Node

const MAX_ENEMIES: int = 256

var _positions:  PackedVector2Array
var _velocities: PackedVector2Array
var _health:     PackedFloat32Array
var _active_count: int = 0

func _ready() -> void:
    # Pre-allocate at startup — no resize during gameplay
    _positions  = PackedVector2Array(); _positions.resize(MAX_ENEMIES)
    _velocities = PackedVector2Array(); _velocities.resize(MAX_ENEMIES)
    _health     = PackedFloat32Array(); _health.resize(MAX_ENEMIES)

func spawn(pos: Vector2, vel: Vector2, hp: float) -> int:
    assert(_active_count < MAX_ENEMIES, "EnemySystem: capacity exceeded.")
    var idx: int = _active_count
    _positions[idx]  = pos
    _velocities[idx] = vel
    _health[idx]     = hp
    _active_count   += 1
    return idx

func despawn(idx: int) -> void:
    # Swap-with-last: keeps active prefix contiguous in O(1)
    _active_count -= 1
    _positions[idx]  = _positions[_active_count]
    _velocities[idx] = _velocities[_active_count]
    _health[idx]     = _health[_active_count]

func _physics_process(delta: float) -> void:
    # Straight scan over contiguous memory — one loop, no per-entity dispatch
    for i: int in _active_count:
        _positions[i] += _velocities[i] * delta
```

### Related Patterns

Component, Object Pool, Update Method

### Competing Patterns

Per-entity Node with `_physics_process` (default; correct for moderate counts), ECS framework via GDExtension (full SoA for extreme scale)

### Key Implementation Notes

- Profile with Godot's built-in profiler before restructuring; confirm the system loop is the bottleneck before eliminating per-entity nodes.
- `Packed*Arrays` are contiguous C memory; use them for all numeric fields in hot-path iteration — position, velocity, health, timers.
- Swap with the last active element on deactivation (O(1)); store entity IDs separately if stable external references into the pool are needed.
- `MultiMeshInstance3D` eliminates per-instance SceneTree overhead for any visually instanced population above a few dozen objects; use it before building custom systems.
- For true struct layout control, implement the hot loop in a GDExtension module; keep GDScript for orchestration and cold-path logic.
- The packed-active-prefix mechanic requires that external code hold indices, not Node references, into the system — indices into a swap-sorted array are invalidated by every despawn.

---

## Dirty Flag

### Core Intent

Avoid recomputing expensive derived data by marking it stale when primary data changes and deferring recomputation until the derived data is actually needed.

### Problem It Solves

Recalculating a derived value on every primary-data change wastes computation when the derived value is only consumed once regardless of how many changes occurred upstream — multiple transform changes in one frame all feed a single render call, but eager recomputation pays the matrix-multiply cost for each change rather than once. The general form is: primary data changes more often than derived data is consumed.

### Engineering Motivation

Godot's `Node2D` and `Node3D` already implement Dirty Flag internally for world transforms: setting `position` marks the world transform dirty and the engine recomputes it lazily at the next render pass. User-space Dirty Flag is warranted for derived data that Godot does not manage — cached navigation paths, pre-baked spatial queries, network-sync property masks, and any computed value whose derivation cost is non-trivial.

### When to Use

- Primary data changes far more frequently than derived data is consumed; deferral collapses multiple upstream changes into one downstream recomputation per consumption.
- Deriving the data is expensive enough — matrix chains, spatial queries, file sync round-trips — that redundant recomputation has a measurable cost.
- Incremental update is not practical; if the derived value can be maintained with an O(1) delta from each primary change, do that instead.

### When NOT to Use

- The derived data is cheap to recompute and the flag adds code complexity exceeding the savings.
- Primary data changes every frame without exception; the flag is always set and becomes pure overhead.
- Deferred computation at access time would cause a visible frame spike when derivation is slow and access timing is unpredictable.

### Main Tradeoffs

| Benefit                                                                                 | Cost                                                                                            |
| --------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------- |
| Multiple primary changes in one frame trigger one derived recomputation                 | Every setter on primary data must set the flag; a missed set causes silently stale derived data |
| Objects whose primary data did not change pay zero derivation cost                      | The most recently derived value must be kept in memory at all times, even when it is not needed |
| Works for computation (transforms, paths) and I/O (network sync, file sync) equally     | Flag granularity is a design decision; too coarse wastes computation, too fine wastes memory    |
| `queue_redraw()` on `CanvasItem` is a built-in single-bit dirty flag for custom drawing | Lazy deferred computation can cause a frame hitch at first access if derivation is heavy        |

### Common Misuse

Placing dirty flags on data that changes every single frame — a physics position updated in `_physics_process` is always dirty — so the flag is never clear, adding the check-and-set overhead on every frame with no benefit.

### Failure Mode

A setter modifies primary data and forgets to set the dirty flag; the derived value silently remains from the previous computation cycle, appearing plausible because it is close to the correct value. The bug only manifests as wrong rendering or logic errors and is extremely difficult to trace because the stale value looks almost right.

### Structural Model

```text
[Transform hierarchy dirty propagation — Godot handles this internally; understand, don't reimplement]

Node3D.position = new_pos    ← sets internal _dirty_transform = true
                             ← children NOT marked; propagated lazily at render
Engine _process_frame():
    Node3D._update_transform(parent_world, parent_dirty):
        dirty |= _dirty_transform
        if dirty: world_transform = parent_world * local_transform; _dirty_transform = false
        for child: child._update_transform(world_transform, dirty)
→ Each affected node recomputed exactly once per frame regardless of upstream change count.

[User-space Dirty Flag — for derived data Godot does not manage]

BakedPathCache (Resource)
    _waypoints: Array[Vector2]       ← primary data
    _dirty: bool = true              ← starts dirty: no cache yet
    _cached_path: PackedVector2Array ← derived data

    add_waypoint(pos):     _waypoints.append(pos); _dirty = true
    get_path():            if _dirty: _cached_path = _compute(); _dirty = false
                           return _cached_path

[Bitmask dirty flag — one int tracks multiple independent dirty properties]
SyncState
    _dirty_mask: int = 0
    PROP_POSITION: int = 1 << 0;  PROP_HEALTH: int = 1 << 1
    set position: _dirty_mask |= PROP_POSITION
    flush_dirty() → int:  mask = _dirty_mask; _dirty_mask = 0; return mask

[CanvasItem — built-in dirty flag for custom 2D drawing]
func _my_setter(v):  _value = v;  queue_redraw()  ← marks canvas item dirty
func _draw():        draw_line(...)                ← called once per frame after queue_redraw()
```

### Godot Adaptation Notes

- `Node2D` and `Node3D` transform dirty flags are handled internally by the engine; do not reimplement the transform propagation pattern in user scripts.
- `queue_redraw()` on any `CanvasItem` (including `Node2D`) IS a single-bit dirty flag: it marks the canvas layer dirty and triggers one `_draw()` call per frame regardless of how many times `queue_redraw()` was called.
- `MultiplayerSynchronizer` uses property dirty flags internally for network sync; use it before implementing custom property-mask synchronization.
- Encapsulate all writes to primary data behind setters (GDScript property `set:` syntax) that also set the flag; this is the only reliable way to prevent missed invalidations as the codebase grows.
- The scene graph propagation trick — passing `parent_dirty: bool` down the render traversal and OR-ing it with each node's own flag — avoids O(subtree_size) recursive flag setting on `set_transform()`. This is already what the engine does; replicate it only in custom scene graph implementations.
- Starting `_dirty = true` at object creation is mandatory: the derived data has not yet been computed, so it is already stale before any call.
- For deferred derivation that might spike a frame, compute dirty objects at a known checkpoint (loading screen, level start) rather than lazily on first access during gameplay.

### Gameplay-Level Usage

A `WaypointPath` resource holds an `Array[Vector2]` of designer-placed waypoints; `_dirty` is set whenever the array changes. `get_smoothed_path()` recomputes a Chaikin-smoothed `PackedVector2Array` only when `_dirty` is true, collapsing any number of waypoint edits made before the first read into one smoothing pass. An `InfluenceMap` recomputes its heatmap only on the frame after a faction's territory changed, not after each individual unit's position update.

### Entity-Level Usage

A `SyncState` resource attached to each networked entity tracks a `_dirty_mask: int` whose bits correspond to individual properties (position, health, animation state). At the end of each `_physics_process`, the sync system calls `flush_dirty()` and sends only the changed properties over the network, avoiding redundant bandwidth for static entities.

### Engine/System-Level Usage

A procedural level generator caches expensive computed outputs (navigation mesh patches, light contribution arrays) in Resource objects with dirty flags; any change to the level geometry sets the relevant flag, and the next level-load checkpoint recomputes all dirty caches in a loading-screen batch rather than on demand mid-game.

### Suggested Script Layout

```text
res://resources/
    baked_path_cache.gd     # Resource — dirty-flagged path cache; _dirty = true at init
    sync_state.gd           # Resource — bitmask dirty flags for network property sync
    influence_map.gd        # Resource — dirty-flag driven heatmap recomputation
res://entities/
    networked_entity.gd     # Node — flushes SyncState dirty mask each physics tick
```

### Godot Performance Notes

**Memory allocation patterns** — The cached derived value must remain allocated even when clean. For large derived structures (navigation mesh patches, packed path arrays), profile whether the memory holding the cache is preferable to recomputing it lazily on each access.

**SceneTree traversal cost** — The engine's internal transform dirty system traverses the full scene tree depth each render frame for nodes with dirty transforms. User-space dirty flags avoid this traversal entirely by deferring computation to the moment of consumption.

**Signal connection overhead** — Emitting a signal from a setter to notify observers of primary-data change is a valid pattern; it adds O(n receivers) dispatch cost per setter call. If the derived consumer is the only observer, a direct `_dirty = true` in the setter is simpler and cheaper.

### Godot Anti-Patterns

**Re-implementing transform dirty flags** — Reproducing the Node2D/Node3D transform invalidation pattern in user scripts duplicates engine infrastructure and may desync with the engine's own dirty tracking. Trust Godot's internal transform system; apply user-space dirty flags only to data the engine does not manage.

**Dirty flag on per-frame-updated data** — Setting `_position_dirty = true` inside `_physics_process` for a value that changes every frame means the flag is always set, making its check-and-clear cost pure overhead. Dirty flags are only beneficial when primary data is stable for multiple frames between changes.

**Exposing primary data fields directly** — Making `_waypoints: Array[Vector2]` a `@export` public field allows external code to modify it without setting the dirty flag. All writes to primary data must go through a setter; the flag discipline fails the moment one direct-write path exists.

### GDScript Structural Example

```gdscript
# baked_path_cache.gd — dirty flag for expensive path derivation
class_name BakedPathCache
extends Resource

var _waypoints: Array[Vector2] = []
var _dirty: bool = true             # starts true: no path computed yet
var _cached_path: PackedVector2Array = PackedVector2Array()

func add_waypoint(pos: Vector2) -> void:
    _waypoints.append(pos)
    _dirty = true

func remove_waypoint(index: int) -> void:
    _waypoints.remove_at(index)
    _dirty = true

# Multiple add/remove calls → one recomputation per consumption point.
func get_path() -> PackedVector2Array:
    if _dirty:
        _cached_path = _smooth(_waypoints)
        _dirty = false
    return _cached_path

func _smooth(pts: Array[Vector2]) -> PackedVector2Array:
    var out: PackedVector2Array = PackedVector2Array()
    for i: int in range(1, pts.size()):
        out.append(pts[i - 1].lerp(pts[i], 0.25))
        out.append(pts[i - 1].lerp(pts[i], 0.75))
    return out
```

```gdscript
# sync_state.gd — bitmask dirty flag for network property sync
class_name SyncState
extends Resource

const PROP_POSITION:  int = 1 << 0
const PROP_HEALTH:    int = 1 << 1
const PROP_ANIMATION: int = 1 << 2

var _dirty_mask: int = 0

var position: Vector2 = Vector2.ZERO:
    set(v): position = v; _dirty_mask |= PROP_POSITION

var health: int = 100:
    set(v): health = v; _dirty_mask |= PROP_HEALTH

var animation: StringName = &"idle":
    set(v): animation = v; _dirty_mask |= PROP_ANIMATION

# Returns bitmask of changed properties; clears all dirty bits.
func flush() -> int:
    var mask: int = _dirty_mask
    _dirty_mask = 0
    return mask

func is_dirty() -> bool:
    return _dirty_mask != 0
```

### Related Patterns

Data Locality, Object Pool

### Competing Patterns

Eager recomputation (simpler; correct when primary and derived are accessed at the same rate), Incremental update (O(1) delta maintenance; better when changes are additive and composable)

### Key Implementation Notes

- `_dirty` must start `true` at construction; the derived value has not been computed and is stale by definition.
- All writes to primary data must go through setters that set the flag; a single exposed field that bypasses the setter silently breaks the invariant.
- Use GDScript property `set:` syntax for setters that set dirty flags; it keeps the flag logic co-located with the primary field declaration.
- `queue_redraw()` is the built-in single-bit dirty flag for `CanvasItem` custom drawing; use it for any `_draw()` override rather than a manual `_dirty` field.
- For network sync, use a bitmask dirty flag (`_dirty_mask |= PROP_X`) rather than a single boolean to track which individual properties changed, enabling per-property selective transmission.
- Never compute derived data inside a setter; set the flag and compute lazily on first access to preserve the "one computation per consumption" guarantee.

---

## Object Pool

### Core Intent

Pre-allocate a fixed-size array of objects and reuse them by resetting their state, eliminating per-object heap allocation and preventing memory fragmentation.

### Problem It Solves

Frequently allocating and freeing complex scene instances — projectiles, enemies, visual effects — incurs non-deterministic `instantiate()` latency and GC pressure in GDScript; on low-memory platforms, high allocation frequency can trigger mid-frame GC collection pauses. Objects that encapsulate expensive resources (audio channels, animation state machines, shader instances) should not be reconstructed on every creation.

### Engineering Motivation

`PackedScene.instantiate()` is expensive: it parses the full node tree, runs all `_init()` calls, and notifies the SceneTree. Pre-instantiating N copies at load time front-loads this cost to a loading screen where latency is acceptable. Reactivating a dormant pooled node via `process_mode = PROCESS_MODE_INHERIT` costs a few property writes; it is orders of magnitude cheaper than `instantiate()`.

### When to Use

- Objects are created and destroyed at high frequency during gameplay — projectiles, particles without `GPUParticles`, sound effects, flying text, enemies.
- The object encapsulates an expensive resource (audio channel, animation player, collision shape) that is costly to construct but cheap to reset.
- `instantiate()` latency is measurable in the profiler during the spawning path.
- Platform memory constraints make heap fragmentation across many small allocations a concern.

### When NOT to Use

- `GPUParticles2D` or `GPUParticles3D` covers the use case — these are built-in pool-based particle systems; never re-implement a particle pool manually.
- Object count is small and spawn frequency is low; pool complexity and fixed memory overhead are not justified.
- Objects vary significantly in node hierarchy structure; one pool per scene type is necessary, which may fragment into more complexity than plain `instantiate()`.

### Main Tradeoffs

| Benefit                                                                                   | Cost                                                                                               |
| ----------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------- |
| `instantiate()` cost paid once at load time; acquire is O(1) via Array pop                | Fixed capacity: pool exhaustion must be handled explicitly (drop silently, evict, or assert)       |
| All pooled nodes pre-exist in the SceneTree as disabled children; no allocation mid-frame | Pool memory held for entire scene lifetime even when all objects are inactive                      |
| Reactivating a node is a property write; constructors and `_ready()` do not re-run        | `_ready()` runs only once at pool warm-up; a `reset()` method must re-initialize all per-use state |
| Pooled nodes remain in a predictable SceneTree position; group membership is stable       | References held by "dead" pooled nodes prevent GC from collecting those referenced objects         |

### Common Misuse

Building a generic heterogeneous pool that accepts any node type, sized to the largest possible object, wasting memory on every smaller object and losing the cache benefit of homogeneous contiguous storage.

### Failure Mode

`reset()` is incomplete; a bullet from the pool retains its velocity, target reference, or damage modifier from a prior lifetime. The bug only surfaces as erratic behavior on shots fired after the pool has cycled — the first N shots are correct, shots beyond N exhibit phantom prior-lifetime state.

### Structural Model

```text
[Flat pre-instantiated node pool — all objects pre-exist as disabled SceneTree children]

BulletPool (Node)                    ← pool manager; parent of all pooled nodes
├── Bullet_000 (Node)                ← PROCESS_MODE_DISABLED; waiting in pool
├── Bullet_001 (Node)                ← PROCESS_MODE_DISABLED
...
├── Bullet_k   (Node)                ← PROCESS_MODE_INHERIT; currently live
...
└── Bullet_N-1 (Node)                ← PROCESS_MODE_DISABLED

_available: Array[Node]  ← LIFO stack of disabled nodes
acquire()  → pop from _available; set PROCESS_MODE_INHERIT; call reset()  → live
release(n) → call reset(); set PROCESS_MODE_DISABLED; push to _available → dead

[Pool exhaustion strategies — choose per object type]
drop:   return null; caller checks and skips (particles, decorative hits)
evict:  release the least-important live node; acquire its slot (sound channels)
assert: push_error(); abort (enemies where losing one is a gameplay bug)

[GPUParticles2D/3D — built-in pool; never replace with a custom pool]
GPUParticles2D.emitting = true  ← internal pool of GPU instances; O(1) activation
→ Use GPUParticles for all visual particle effects; custom pools for gameplay objects only.

[GC reference clearing — dead pooled nodes must null all held references]
reset():
    target = null          ← allow GC to reclaim the previously targeted object
    collision_exception = null
    velocity = Vector2.ZERO
```

### Godot Adaptation Notes

- `process_mode = PROCESS_MODE_DISABLED` is the Godot equivalent of the C++ "dead object in pool" state; it stops all callbacks on the node and its children with a single property write.
- `process_mode = PROCESS_MODE_INHERIT` on acquire restores full processing; no `_ready()` re-run occurs, so all pooled objects share one `_ready()` initialization and differ only by what `reset()` sets per-use.
- Pre-instantiate the pool during the loading screen — in `_ready()` of a loading scene or in a dedicated `_load_pool()` call triggered before gameplay begins — to front-load `PackedScene.instantiate()` cost.
- GDScript's GC means fragmentation is not the C++ concern, but allocation latency and GC pressure from frequent `instantiate()` calls are real and measurable; pools eliminate both.
- Dead pooled nodes must null out all object references they hold (`target = null`, `owner = null`); GDScript's GC cannot reclaim objects that are reachable through a pool member's fields, even when that member is "dead."
- For audio channel pools (`AudioStreamPlayer` pool), the pool exhaustion strategy should be eviction: find the playing channel with the lowest volume and release it, assigning the slot to the incoming request. Never silently drop audio without a warning.
- Size the pool to the true worst-case simultaneous count; add 10–20% headroom, then profile memory and trim if over-allocated.

### Gameplay-Level Usage

A bullet pool pre-instantiates 128 bullet nodes at level load; each `fire()` call pops from the available stack, calls `bullet.reset(origin, direction, damage)`, and sets `PROCESS_MODE_INHERIT`. On hit or timeout, the bullet calls `pool.release(self)`, clears its target reference, and returns to the stack. Spawn and despawn are each one Array pop and one property write — no `instantiate()`, no `queue_free()`, no GC pressure during combat.

### Entity-Level Usage

An `EnemyPool` pre-instantiates enemy scenes; the wave system acquires enemies from the pool rather than calling `instantiate()`. On death, the enemy's `_die()` method calls `pool.release(self)` after playing a death animation — the node is disabled mid-animation rather than freed, and the animation completes correctly because `PROCESS_MODE_DISABLED` does not interrupt animation frames already queued.

### Engine/System-Level Usage

A project-wide `PoolRegistry` Autoload holds typed pools (`bullet_pool`, `enemy_pool`, `sfx_pool`) initialized at game startup. Systems request objects from the registry by type name; the registry tracks utilization and emits a warning signal when any pool exceeds 80% capacity, allowing designers to adjust `POOL_SIZE` constants before the pool exhausts during soak testing.

### Suggested Script Layout

```text
res://systems/pools/
    bullet_pool.gd          # Node — typed pool for Bullet scene
    enemy_pool.gd           # Node — typed pool for Enemy scene
    sfx_pool.gd             # Node — AudioStreamPlayer pool (AudioBus from Batch A Singleton)
res://autoloads/
    pool_registry.gd        # Autoload — typed accessors for all project pools
res://entities/bullet/
    bullet.gd               # Node — reset() method; nulls all references on release
    bullet.tscn
```

### Godot Performance Notes

**PackedScene instancing cost** — `PackedScene.instantiate()` is O(node_count × depth) and involves scene format parsing, `_init()` and `_ready()` calls, and SceneTree notifications. This cost should appear in the profiler only during loading screens; any `instantiate()` in `_physics_process` during gameplay is a pool candidate.

**Node count implications** — All pooled nodes exist in the SceneTree simultaneously as disabled children; N pooled bullets add N SceneTree entries. Disabled nodes with `PROCESS_MODE_DISABLED` do not receive callbacks, but they do participate in tree operations like `find_children()` and group queries. Keep pool parent nodes outside groups they should not affect.

**Memory allocation patterns** — The `_available` array grows only during pool warm-up and never during gameplay; pre-size it with `_available.reserve(POOL_SIZE)` after initial population to avoid Array resize during the acquire/release cycle.

**Signal connection overhead** — Connect pooled nodes' signals once in `_ready()` during warm-up; do not disconnect and reconnect on each acquire/release cycle. Signal connections on disabled nodes are safe and do not fire while the node is disabled.

### Godot Anti-Patterns

**`queue_free()` for pooled objects** — Calling `queue_free()` on a pooled node removes it from the SceneTree permanently; subsequent `pool.release()` calls push a freed node back onto the stack, producing a dangling reference crash on the next acquire. Pooled nodes are NEVER freed; they return to the pool's disabled-child list.

**Skipping `reset()` for "simple" objects** — An object whose state looks like it resets automatically (velocity set in `_physics_process`, target set in `fire()`) still holds references from the prior lifetime until those fields are overwritten. A `reset()` that explicitly clears all fields and nulls all references is mandatory; it cannot be skipped for "simple" cases.

**One heterogeneous pool for all object types** — Mixing enemy scenes, bullet scenes, and effect scenes in a single pool requires padding all slots to the largest type, destroying the memory efficiency and cache-locality benefits. Maintain one pool per scene type.

### GDScript Structural Example

```gdscript
# bullet_pool.gd — typed pool; acquire/release with process_mode lifecycle
class_name BulletPool
extends Node

const POOL_SIZE: int = 128

@export var bullet_scene: PackedScene
var _available: Array[Node] = []

func _ready() -> void:
    # Front-load instantiate() cost to load time — never during gameplay
    _available.reserve(POOL_SIZE)
    for i: int in POOL_SIZE:
        var bullet: Node = bullet_scene.instantiate()
        bullet.process_mode = Node.PROCESS_MODE_DISABLED
        add_child(bullet)
        _available.append(bullet)

func acquire() -> Node:
    if _available.is_empty():
        push_warning("BulletPool exhausted (POOL_SIZE = %d); dropping request." % POOL_SIZE)
        return null
    var bullet: Node = _available.pop_back()
    bullet.process_mode = Node.PROCESS_MODE_INHERIT
    return bullet

func release(bullet: Node) -> void:
    if bullet.has_method(&"reset"):
        bullet.reset()          # mandatory: clears state, nulls all references
    bullet.process_mode = Node.PROCESS_MODE_DISABLED
    _available.append(bullet)

func utilization() -> float:
    return float(POOL_SIZE - _available.size()) / float(POOL_SIZE)
```

### Related Patterns

Flyweight, Data Locality, Update Method

### Competing Patterns

`PackedScene.instantiate()` + `queue_free()` (simplest; correct when spawn frequency is low), `GPUParticles2D/3D` (built-in pool for visual particles; always prefer over a custom particle pool)

### Key Implementation Notes

- Use `process_mode = PROCESS_MODE_DISABLED` for the "dead" state; it stops all callbacks on the node and its children in one write.
- `_ready()` runs only once at warm-up; per-use initialization belongs in a `reset()` method called on every `acquire()`.
- Null all object references in `reset()` — `target = null`, `owner_ref = null` — to prevent GC hold-aliveness through dead pool slots.
- Size the pool to worst-case simultaneous count; add 10–20% headroom; assert in `acquire()` rather than returning `null` silently if exhaustion is a gameplay bug.
- For audio channel pools, evict the quietest playing channel when the pool is full rather than dropping silently.
- `_available.reserve(POOL_SIZE)` after warm-up prevents Array resize during the acquire/release cycle.
- Never call `queue_free()` on a pooled node; pooled nodes live for the lifetime of their pool parent.

---

## Spatial Partition

### Core Intent

Store objects in a spatial data structure organized by position so that proximity queries find relevant objects in sublinear time instead of scanning the full population.

### Problem It Solves

A brute-force proximity check — every entity against every other — is O(n²); with hundreds of units on a battlefield this dominates the frame budget. Organizing objects by position limits each query to the spatially adjacent partition cells rather than all n objects.

### Engineering Motivation

Godot's physics engine (`PhysicsServer2D`/`PhysicsServer3D`) and `Area2D`/`Area3D` already implement spatial partitioning internally for collision queries; using `Area2D.get_overlapping_bodies()` is using a spatial partition without any custom infrastructure. A custom partition is warranted only for query domains that the physics engine does not cover — non-collision proximity, influence fields, vision, sound propagation, or RTS-style unit interaction at object counts that exceed practical `Area2D` usage.

### When to Use

- Proximity queries involve object counts large enough that O(n²) brute force is measurable in the profiler.
- The query domain is non-physical (influence radii, fog of war, territory control) and `Area2D` overlap queries are not applicable.
- The game has an RTS or simulation context where thousands of units query for neighbors every frame.

### When NOT to Use

- Object count is small enough that a linear scan completes in microseconds; partition bookkeeping overhead is not justified.
- `Area2D` with `PhysicsLayer` masks covers the query — always use Godot's built-in physics queries before building a custom partition.
- `PhysicsDirectSpaceState2D.intersect_circle()` / `intersect_shape()` covers the spatial query — use it before building a custom grid.
- Objects move so frequently that grid update cost exceeds query savings.

### Main Tradeoffs

| Benefit                                                                               | Cost                                                                                                                                               |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| Proximity queries reduce from O(n) or O(n²) to O(k) where k is cells per query radius | Cell granularity is a tuning parameter; cells too large for the interaction radius recover O(n²) in densely populated cells                        |
| Move updates are O(1) for a flat grid when the object stays in the same cell          | Additional memory for cell arrays; for a sparse world, most cells are empty                                                                        |
| Separating static geometry from dynamic objects into different structures is explicit | The partition must be notified of every position change; a move without a `grid.move()` call desynchronizes world position from partition position |
| Flat grid with typed `Array` cells is straightforward to implement in GDScript        | Adaptive structures (quadtree, k-d tree) provide better balance for non-uniform distributions but are more complex to maintain in GDScript         |

### Common Misuse

Setting cell size much larger than the interaction radius so that most objects share one cell, causing the proximity query for that cell to degenerate into an O(n²) scan of nearly the entire population.

### Failure Mode

A unit moves via `global_position = ...` but `grid.move(unit, old_pos)` is not called; the unit's partition cell is its position at the time of last `insert()`. Subsequent queries near the unit's new position miss it entirely, and queries near its old position still find it — the invisible-unit bug where attacks pass through enemies that have drifted out of their cells.

### Structural Model

```text
[Godot-native spatial queries — use these first before building a custom partition]

Area2D / Area3D with PhysicsLayer masks:
    area.get_overlapping_bodies()         ← returns all bodies in this Area's shape
    area.get_overlapping_areas()          ← returns overlapping Areas
    → Built-in broadphase; handles moving objects, collision masks, and shape intersection.

PhysicsDirectSpaceState2D.intersect_circle(pos, radius, max_results, params):
    → Direct spatial query bypassing scene nodes; correct for non-Area-based queries.

TileMapLayer.get_cells_in_rect(rect):
    → Built-in spatial query for tile grids; O(1) per cell in the rect.

[Custom fixed-cell grid — for non-physics proximity at high object counts]

SpatialGrid2D (RefCounted)
    CELL_SIZE: float                    ← must be ≥ max interaction radius
    _cells: Array[Array[Node2D]]        ← indexed by cy * _width + cx

    insert(obj): _cells[_idx(obj.pos)].append(obj)
    move(obj, old_pos):
        old_idx = _idx(old_pos);  new_idx = _idx(obj.pos)
        if old_idx == new_idx: return          ← same cell; no bookkeeping
        _cells[old_idx].erase(obj)             ← O(n_cell) — keep cells small
        _cells[new_idx].append(obj)
    query_cell_and_neighbors(pos):
        → collects 3×3 cell neighborhood → caller does distance filtering

[Half-neighbor trick — avoids processing each pair twice in melee resolution]
    for each cell (cx, cy):
        for unit A in cell:
            compare A vs rest of same cell (forward pairs only)
            compare A vs 4 of 8 neighbors (right, down-left, down, down-right)

[Static vs. dynamic partitions]
Static geometry (level art, obstacles):  NavigationRegion2D, TileMapLayer,
                                         PhysicsBody2D with StaticBody — built in.
Dynamic objects (units, projectiles):    custom SpatialGrid2D or Area2D — user choice.
```

### Godot Adaptation Notes

- For collision-based proximity queries, `Area2D.get_overlapping_bodies()` and `PhysicsDirectSpaceState2D.intersect_circle()` are built-in spatial partitions that cover the majority of use cases with no custom infrastructure.
- `TileMap` / `TileMapLayer` provides built-in cell-based queries via `get_cells_in_rect()`, `get_cell_tile_data()`, and similar; use it for any grid-based proximity in tile games.
- A custom fixed-cell grid (`SpatialGrid2D`) is warranted for non-collision proximity at high object counts — influence radii, sound propagation, territory control — where `Area2D` per-unit overhead becomes measurable.
- GDScript `Array.erase()` is O(n) in the number of objects in the cell; keep cells small (CELL_SIZE ≤ 2–4× the interaction radius) to bound the erase cost per move.
- Use a flat typed `Array[Node2D]` per cell rather than a doubly-linked intrusive list — GDScript lacks the pointer-embedding that makes O(1) intrusive-list removal efficient in C++; at small per-cell counts (< 20 objects), `Array.erase()` is fast enough.
- Maintain a separate `Array[Node2D]` of all live objects alongside the partition for operations that must iterate everything (like `update()`) without scanning all cells including empty ones.
- For static geometry, Godot's `NavigationServer`, `PhysicsServer`, and `TileMapLayer` provide highly optimized partitioned queries; never build a custom static partition for these domains.

### Gameplay-Level Usage

An RTS game with 500 units per faction uses a `SpatialGrid2D` with `CELL_SIZE = 64.0`; each unit calls `grid.move(self, last_pos)` at the end of its `_physics_process` after resolving movement. Melee range checks query `grid.query_cell_and_neighbors(unit.global_position)` and filter by distance rather than iterating all 1 000 units every frame. The partition brings melee resolution from O(n²) to O(k²) where k is the average cell occupancy.

### Entity-Level Usage

A sound propagation system queries a `SpatialGrid2D` to find all entities within audible range of a sound source without using `Area2D`; the query touches only the adjacent grid cells rather than iterating all entities in the scene. After each query, the system calls `grid.move(source, old_pos)` to keep the sound source's cell current.

### Engine/System-Level Usage

A `BattlefieldPartition` system node initializes a `SpatialGrid2D` at level load from level dimensions, inserts all units on spawn, removes them on death, and calls `move()` for each unit that changed cell during the previous frame. It exposes `query_units_near(pos, radius)` as its public API; all proximity queries in the game route through it rather than through raw physics queries.

### Suggested Script Layout

```text
res://systems/
    spatial_grid_2d.gd      # RefCounted — fixed-cell grid; insert/move/query_neighbors
    battlefield_partition.gd # Node — project-level wrapper; manages unit lifecycle
res://entities/unit/
    unit.gd                 # CharacterBody2D — calls BattlefieldPartition.move(self, old_pos)
```

### Godot Performance Notes

**SceneTree traversal cost** — The grid is a `RefCounted`; no SceneTree traversal occurs during insert, move, or query. The query inner loop iterates raw `Array` elements — one pass over each cell's list, no Node dispatch.

**Memory allocation patterns** — `Array.erase()` shifts subsequent elements; for cell arrays with many concurrent objects (> 50 per cell), profile whether the move cost dominates. If so, use an unsorted swap-erase: swap the target with the last element and pop, making removal O(1) at the cost of losing order.

**Typed vs. untyped Array performance** — Inner cell arrays typed as `Array[Node2D]` avoid per-element Variant overhead on iteration. Type the cell elements consistently; untyped inner arrays require coercion on every proximity loop iteration.

**Node count implications** — The partition is one `RefCounted` object; it adds no SceneTree nodes. The query result array is allocated fresh per query; for high-frequency queries (every unit every frame), consider passing a pre-allocated output array to avoid per-query allocation.

### Godot Anti-Patterns

**Building a custom partition when `Area2D` would work** — Creating a custom grid for collision-based enemy detection when `Area2D.get_overlapping_bodies()` with a physics mask would produce identical results in fewer lines with better engine integration. Always reach for the physics engine's spatial queries first.

**Cell size larger than interaction radius** — Setting `CELL_SIZE = 256.0` for a game where units attack within 32 units places all units in one or two cells, degenerating the query to O(n) or O(n²) and eliminating the partition's benefit.

**Moving objects without calling `grid.move()`** — Setting `obj.global_position = new_pos` directly without notifying the partition through `grid.move(obj, old_pos)` desynchronizes the world position from the partition cell. Every position-update path must include a partition update; a wrapper method on the entity is the reliable enforcement point.

### GDScript Structural Example

```gdscript
# spatial_grid_2d.gd — fixed-cell flat grid; O(1) cell lookup, O(k) neighbor query
class_name SpatialGrid2D
extends RefCounted

const CELL_SIZE: float = 64.0
var _w: int
var _h: int
var _cells: Array = []      # flat Array[Array]; each slot is Array[Node2D]

func _init(grid_width: int, grid_height: int) -> void:
    _w = grid_width
    _h = grid_height
    _cells.resize(_w * _h)
    for i: int in _cells.size():
        _cells[i] = []

func _cell(pos: Vector2) -> int:
    return clampi(floori(pos.y / CELL_SIZE), 0, _h - 1) * _w + \
           clampi(floori(pos.x / CELL_SIZE), 0, _w - 1)

func insert(obj: Node2D) -> void:
    (_cells[_cell(obj.global_position)] as Array).append(obj)

func remove(obj: Node2D) -> void:
    (_cells[_cell(obj.global_position)] as Array).erase(obj)

func move(obj: Node2D, old_pos: Vector2) -> void:
    var oc: int = _cell(old_pos)
    var nc: int = _cell(obj.global_position)
    if oc == nc: return                   # same cell; caller updated position only
    (_cells[oc] as Array).erase(obj)
    (_cells[nc] as Array).append(obj)

func query_neighbors(pos: Vector2) -> Array[Node2D]:
    var cx: int = clampi(floori(pos.x / CELL_SIZE), 0, _w - 1)
    var cy: int = clampi(floori(pos.y / CELL_SIZE), 0, _h - 1)
    var out: Array[Node2D] = []
    for dy: int in range(-1, 2):
        for dx: int in range(-1, 2):
            var nx: int = cx + dx
            var ny: int = cy + dy
            if nx >= 0 and nx < _w and ny >= 0 and ny < _h:
                out.append_array(_cells[ny * _w + nx])
    return out
```

### Related Patterns

Object Pool, Data Locality

### Competing Patterns

`Area2D` + physics layer masks (built-in; always prefer for collision-based queries), `PhysicsDirectSpaceState2D.intersect_circle()` (built-in point-radius query), Brute-force scan (correct for small n; no bookkeeping)

### Key Implementation Notes

- Use `Area2D`, `PhysicsDirectSpaceState2D`, and `TileMapLayer` built-in queries before building a custom partition; custom grids are warranted only for non-physics proximity at high object counts.
- `CELL_SIZE` must be at least as large as the maximum interaction radius; objects in adjacent cells must be within one cell boundary crossing of each other.
- GDScript `Array.erase()` is O(n) in cell occupancy; keep cell sizes small (≤ 20 objects) to bound removal cost, or use swap-erase for O(1) unordered removal.
- Maintain a separate flat `Array[Node2D]` of all live objects alongside the partition for full-population iteration (update loops, serialization) that should not scan all grid cells.
- Every position-update code path must call `grid.move(obj, old_pos)` — the partition's invariant breaks silently the moment any movement bypasses the notification.
- For static obstacles and level geometry, `NavigationServer` and `PhysicsServer` provide optimized static partitions; build at load time, never rebuild per frame.

---
