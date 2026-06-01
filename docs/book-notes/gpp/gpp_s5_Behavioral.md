## Bytecode

### Core Intent

Give behavior the flexibility of data by encoding it as instructions for a virtual machine, sandboxing it from the host engine while enabling runtime loading and designer authoring.

### Problem It Solves

Defining all behavior in engine scripts requires a programmer for every designer tweak, and any bug in game-logic code can reach engine internals directly. Behaviors that must be moddable, downloaded post-ship, or authored by untrusted parties cannot safely run as native scripts without exposing the full engine to that code.

### Engineering Motivation

A VM whose instruction set is fully defined by the engine provides a hard security boundary: bytecode can only invoke operations explicitly listed as opcodes. Godot's own GDScript is a bytecode VM that covers most designer-iteration needs — the custom Bytecode pattern is warranted only when GDScript's unrestricted engine access is itself a security or sandboxing concern.

### When to Use

- Content is authored by untrusted parties (user-generated content, community mods) and must not be able to reach engine internals.
- The game supports post-ship behavior patching or downloadable spells/abilities encoded as data.
- A graphical authoring tool will compile a visual graph or DSL into a controlled instruction stream.
- GDScript's full engine access is unacceptable for the content type — the full surface is the threat.

### When NOT to Use

- Designer iteration is the only goal — GDScript, `@tool` scripts, and hot-reload already address this with no VM overhead.
- Formulas or expressions are the extent of dynamic behavior — use Godot's `Expression` class, which is purpose-built and avoids a full VM.
- The team cannot sustain both a VM and a front-end authoring tool; a VM without an authoring tool shifts the authoring problem onto the designers in a worse form.
- Execution is on a hot path; GDScript bytecode interpreted via a GDScript VM stacks two interpreter layers and will be unacceptably slow.

### Main Tradeoffs

| Benefit                                                                           | Cost                                                                                                    |
| --------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Hard sandbox: bytecode reaches only explicitly exposed opcodes                    | Interpreted via a GDScript VM, execution is two interpreter layers deep — strictly for cold paths       |
| Content hot-reloadable and patchable post-ship as `PackedByteArray` in a Resource | Requires a front-end authoring tool; without one, the bytecode format becomes a new undocumented DSL    |
| Designers iterate on behavior without triggering a build cycle                    | Standard debuggers are useless; custom instruction-trace tooling must be built from the start           |
| Instruction set scope is explicit and auditable by construction                   | VM grows organically with each "one more opcode" addition; scope discipline requires active enforcement |

### Common Misuse

Starting with a minimal VM for spell effects and adding opcodes incrementally until the instruction set has become an undesigned scripting language — at which point GDScript (or an embedded Lua via GDExtension) would have been a better foundation.

### Failure Mode

The VM ships without a way to map a failing execution back to its source form — no instruction trace, no opcode-to-source mapping, no step-through. Designer-authored behavior becomes a black box that produces wrong results with no actionable diagnostic.

### Structural Model

```text
[Full custom VM — for sandboxed or untrusted content]

Authoring layer
    Designer uses graphical tool or text DSL
                        ↓ compile
Bytecode (PackedByteArray stored in a Resource .tres file)
    0x00  PUSH_INT  0        ← push actor index (caster = 0)
    0x01  PUSH_INT  50       ← push amount
    0x02  GET_HEALTH         ← pop(actor_id) → push(sandbox.get_health(id))
    0x03  ADD                ← pop(b), pop(a) → push(a + b)
    0x04  SET_HEALTH         ← pop(amount), pop(actor_id) → sandbox.set_health
    0x05  PLAY_SOUND         ← pop(sound_id) → sandbox.play_sound

SpellVM (RefCounted)               SpellSandbox (RefCounted)
    _stack: Array[int]                 get_health(actor_id: int) → int
    interpret(bytecode, sandbox)       set_health(actor_id, amount)
    MAX_STEPS execution budget         play_sound(sound_id: int)
                                       ← ONLY these methods are reachable from bytecode

[Security boundary: engine internals are unreachable — no opcode = no access]

[Expression alternative — for formula-level behavioral variation only]
    "base_damage + (caster_level * 2.5)"   ← string stored in Resource
    Expression.parse(text, param_names)
    Expression.execute([param_values])
    → limited to arithmetic, comparisons, and built-in functions
    → no side effects, no flow control, no state mutation
    → correct for: damage formulas, stat scaling, AI utility scoring
    → NOT correct for: sequenced effects, triggers, mutation pipelines
```

### Godot Adaptation Notes

- GDScript is already a bytecode VM implemented in C++; use it for all designer iteration that does not require sandboxing — hot-reload, `@export` parameters, and `@tool` scripts cover most of the pattern's stated motivation.
- Godot's `Expression` class evaluates arithmetic and logical expressions from strings at runtime with no custom VM; it is the correct solution for damage formulas, stat scaling, and condition trees.
- GDScript scripts loaded with `load()` run with full, unrestricted engine access — they are NOT sandboxed. For modding or user-generated content, a custom VM with an explicit instruction set is required.
- A custom GDScript VM stacks two interpreter layers: the Godot bytecode VM running GDScript, which then dispatches your opcodes. This is significantly slower than native GDExtension; reserve GDScript VMs for low-frequency execution (spell cast, on-hit, on-death triggers).
- For performance-sensitive sandboxed scripting, implement the VM as a `GDExtension` in C or Rust; the GDScript layer only assembles bytecode into `PackedByteArray` Resources and hands them to the native interpreter.
- `PackedByteArray` stored in a `Resource` is the natural bytecode container: designer-editable via `@export`, serializable to `.tres`, hot-reloadable on resource change.
- Cap execution steps per invocation from day one; a `MAX_STEPS` guard prevents infinite loops and keeps frame-time budget for untrusted content bounded.

### Gameplay-Level Usage

A spell system stores each spell's effect as a `PackedByteArray` in a `SpellResource`; designers compile spells in a visual graph tool that emits opcodes, and the resulting `.tres` files ship as DLC without any source rebuild. A turn-based tactics game encodes unit AI routines as bytecode so players can program their units in a sandboxed visual scripting interface.

### Entity-Level Usage

A buff/debuff component holds a `PackedByteArray` for its on-tick effect; the VM executes up to `MAX_STEPS` opcodes per entity per tick through a `SpellSandbox` that limits access to the entity's own stats. The sandbox wraps only the exact stat fields the system designer chose to expose — health, mana, and status — leaving physics, rendering, and audio unreachable.

### Engine/System-Level Usage

A mod loader reads `.tres` files from a user directory at startup; each file contains a `PackedByteArray` and a `SpellSandbox` configuration. The loader validates bytecode against a whitelist of safe opcodes before registration. The VM runs in a deferred call so a runaway script cannot stall the engine mid-frame.

### Suggested Script Layout

```text
res://systems/vm/
    spell_vm.gd         # RefCounted — stack machine; interpret(bytecode, sandbox)
    spell_sandbox.gd    # RefCounted — security boundary; only callable API
res://resources/spells/
    spell_resource.gd   # Resource — @export bytecode: PackedByteArray
    data/
        fireball.tres
        heal.tres
res://tools/spell_compiler/
    spell_compiler.gd   # @tool — compiles graphical nodes to PackedByteArray
```

### Godot Performance Notes

**SceneTree traversal cost** — The VM and sandbox are `RefCounted` objects; no SceneTree traversal occurs. Instantiation cost per invocation is one `RefCounted` allocation; amortize by pre-allocating the VM at system startup.

**Memory allocation patterns** — Pre-allocate `_stack` with `resize()` to `MAX_STACK_DEPTH` at construction. Never append to the stack in an unbounded loop; growing the array mid-execution defeats the fixed-cost guarantee.

**Signal connection overhead** — If the sandbox emits signals to notify the game world of spell effects (preferred over direct method calls on game entities), connection cost is O(1). Emit deferral via `call_deferred` isolates execution from the current call stack.

### Godot Anti-Patterns

**Using GDScript as a sandbox** — Calling `load("res://mods/user_spell.gd")` and running it trusts the script with full engine access: file I/O, node deletion, Autoload mutation. If sandboxing is required, a custom VM is not optional.

**VM opcodes for hot-path behavior** — Running the VM in `_physics_process` for hundreds of entities every tick creates a two-interpreter bottleneck. Bytecode execution belongs in cold paths: on-cast, on-hit, on-death, on-equip.

**Growing the instruction set without a front-end** — Adding opcodes faster than the authoring tool supports them produces a bytecode format that only engineers can write; the pattern's designer-authoring benefit is lost entirely.

### GDScript Structural Example

```gdscript
# spell_vm.gd — stack machine; instruction set defines the security boundary
class_name SpellVM
extends RefCounted

enum Op { PUSH_INT = 0, GET_HEALTH = 1, SET_HEALTH = 2, ADD = 3, PLAY_SOUND = 4 }
const MAX_STEPS: int = 256  # execution budget — prevents infinite loops

var _stack: Array[int] = []

func _init() -> void:
    _stack.resize(32)  # pre-allocate; clear with _stack.clear() per invocation

func interpret(bytecode: PackedByteArray, sandbox: SpellSandbox) -> bool:
    _stack.clear()
    var ip: int = 0
    var steps: int = 0
    while ip < bytecode.size() and steps < MAX_STEPS:
        steps += 1
        match bytecode[ip]:
            Op.PUSH_INT:
                ip += 1
                _stack.append(bytecode[ip])
            Op.GET_HEALTH:
                _stack[-1] = sandbox.get_health(_stack[-1])
            Op.SET_HEALTH:
                var amt: int = _stack.pop_back()
                sandbox.set_health(_stack.pop_back(), amt)
            Op.ADD:
                var b: int = _stack.pop_back()
                _stack[-1] += b
            Op.PLAY_SOUND:
                sandbox.play_sound(_stack.pop_back())
        ip += 1
    return steps < MAX_STEPS   # false = budget exceeded; caller should log warning
```

```gdscript
# spell_sandbox.gd — security boundary: bytecode reaches ONLY these methods
class_name SpellSandbox
extends RefCounted

var _caster: CharacterBody2D
var _targets: Array[CharacterBody2D]

func _init(caster: CharacterBody2D, targets: Array[CharacterBody2D]) -> void:
    _caster = caster
    _targets = targets

func get_health(actor_index: int) -> int:
    return _resolve_actor(actor_index).current_health

func set_health(actor_index: int, amount: int) -> void:
    _resolve_actor(actor_index).current_health = clampi(amount, 0, 9999)

func play_sound(sound_id: int) -> void:
    AudioBus.play_by_id(sound_id)  # only the AudioBus Autoload is reachable here

func _resolve_actor(index: int) -> CharacterBody2D:
    return _caster if index == 0 else _targets[clampi(index - 1, 0, _targets.size() - 1)]
```

### Related Patterns

Subclass Sandbox, Type Object, Interpreter (GoF)

### Competing Patterns

GDScript with hot-reload, Godot `Expression` class, Subclass Sandbox, Type Object, Embedded scripting via GDExtension (Lua, Wren)

### Key Implementation Notes

- Use GDScript and `Expression` before building a custom VM; the pattern is only warranted when GDScript's full engine access is itself the problem.
- `PackedByteArray` is the natural bytecode container in Godot: compact, serializable to `.tres`, and passable across `@rpc` boundaries for networked execution.
- Cap `MAX_STEPS` from the first line of the VM; retrofitting a step budget after content is authored is a breaking change.
- The sandbox class is the security contract; every engine API the bytecode may reach must appear as an explicit method on the sandbox — nothing else.
- For production sandboxing, implement the VM in `GDExtension`; a GDScript VM running GDScript is two interpreter layers deep and unsuitable for any path hotter than on-cast.
- Plan instruction-trace logging and source-line mapping at design time; diagnosing misbehaving bytecode without them is nearly impossible at content scale.

---

## Subclass Sandbox

### Core Intent

Define behavior in a subclass by calling a set of protected operations provided by the base class, isolating subclasses from all direct coupling to the rest of the engine.

### Problem It Solves

When many subclasses each reach directly into engine systems, any system change can break any subclass; coupling is scattered invisibly across the hierarchy. Behavioral overlap between subclasses produces duplicated code with no shared invariant enforcement.

### Engineering Motivation

Concentrating all engine coupling into a single base class makes the subclass-to-engine dependency surface one auditable point: changing an engine system means modifying the base class, not hunting through dozens of subclasses. In Godot, Autoloads and `get_tree()` calls scattered across many power/ability scripts create the same hidden coupling problem the pattern addresses.

### When to Use

- A large, open-ended set of behaviors (powers, spells, abilities, items) must all interact with the same engine systems — audio, VFX, physics, world state.
- New behaviors are added frequently by different developers; you need to constrain the surface each author must understand.
- Behavioral overlap exists and you want shared implementations rather than per-subclass duplication.
- Subclass authors should not need to know how AudioBus, ParticleSystem, or physics are structured internally.

### When NOT to Use

- The base class cannot be fully defined up front because subclasses will need engine systems not yet known; the base class will accrete without bound.
- Behavior is better expressed as data rather than code — use Type Object or Bytecode instead.
- The inheritance hierarchy is already deep; Subclass Sandbox on a deep tree worsens the brittle base class problem.

### Main Tradeoffs

| Benefit                                                                                | Cost                                                                                              |
| -------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| Subclasses are fully isolated from engine systems they do not need to know about       | Base class is coupled to every engine system any subclass requires                                |
| All coupling lives in one visible, auditable location                                  | Brittle base class: any change risks breaking all subclasses simultaneously                       |
| Protected provided operations enforce invariants across all subclasses                 | Base class accretes over time; each new system requirement forces a base class edit               |
| Behavioral overlap factored into shared operations rather than duplicated per-subclass | Wide, flat hierarchy scales well; deep extension of the hierarchy breaks the pattern's guarantees |

### Common Misuse

Adding so many provided operations to the base class that it becomes a God Object and is itself unmaintainable — defeating the purpose of centralizing coupling by making the central point the worst-coupled class in the project.

### Failure Mode

The base class grows without discipline until it directly references every Autoload and engine system in the project; changing any of them requires touching the base class, which in turn risks breaking all subclasses — the brittle base class collapse the pattern was meant to prevent.

### Structural Model

```text
Superpower (Node)                         ← single engine coupling point
    @export owner_body: CharacterBody3D   ← injected; invisible to subclasses
    PROTECTED provided operations:
    _move(direction, speed)          ──→  owner_body.velocity, move_and_slide()
    _play_sound(stream, vol)         ──→  AudioBus.play()          [Autoload call]
    _spawn_particles(scene, pos)     ──→  scene.instantiate() + add_child()
    _get_owner_position() → Vector3  ──→  owner_body.global_position
    ABSTRACT protected:
    _activate()                           ← sandbox method; subclasses implement

SkyLaunch extends Superpower         FrostRay extends Superpower
    _activate():                         _activate():
        _play_sound(launch_sfx, 1.0)         _play_sound(ice_sfx, 0.8)
        _spawn_particles(dust, pos)          _spawn_particles(frost, pos)
        _move(Vector3.UP, 20.0)              EventBus.freeze_applied.emit(target)

[subclasses call only _protected methods; zero direct Autoload or engine-API import]

[When base class grows too large — extract into helpers]
Superpower._sfx: SoundHelper  → groups _play_sound, _play_music, _play_impact
Superpower._vfx: VFXHelper    → groups _spawn_particles, _flash_sprite, _screen_shake
→ subclasses still interact with one object; base class surface stays manageable
```

### Godot Adaptation Notes

- Godot's own `CharacterBody2D`, `RigidBody2D`, and `Area2D` are Subclass Sandbox implementations — they provide `move_and_slide()`, `apply_impulse()`, and collision callbacks as protected-equivalent provided operations, hiding `PhysicsServer2D` calls from subclasses.
- Autoload access (`AudioBus.play()`, `EventBus.spell_cast.emit()`) replaces C++ constructor injection of engine references; the base class calls Autoloads directly, simplifying setup but introducing a dependency on those Autoloads being present and registered.
- Use `@export` on the base class for engine references that vary per instance (the owner body, particle parent node); use Autoloads for project-wide services (audio, events) that are genuinely ambient.
- Provided operations should be non-virtual `func` methods prefixed with a single underscore (`_move`, `_play_sound`) as a naming convention signal that subclasses call but do not override them — GDScript has no `protected` keyword, so the convention is enforced by documentation and code review.
- When the provided operation set grows beyond ten to fifteen methods, extract related groups into helper `RefCounted` objects (`SoundHelper`, `VFXHelper`) exposed via a single accessor on the base class; this compresses the visible surface without dispersing coupling.
- The sandbox method (`_activate()`) frequently coincides with `_physics_process` override; the base class can call `_activate()` from `_physics_process` to unify both patterns.

### Gameplay-Level Usage

A `StatusEffect` base class provides `_apply_to_target(target)`, `_remove_from_target(target)`, `_play_status_sound()`, and `_spawn_status_vfx()` as its provided operations; each status effect subclass (`BurnEffect`, `FreezeEffect`, `PoisonEffect`) implements only `_activate()` and `_on_tick()` using those primitives, with no direct coupling to AudioBus, ParticleSystem, or health components. Adding a new status effect is adding one file.

### Entity-Level Usage

A `Projectile` base class holds references to its emitter, target, and collision shape, and provides `_explode()`, `_home_toward(target)`, `_pierce()`, and `_deflect()` as operations; each projectile type (`HomingMissile`, `BouncingBolt`, `PiercingArrow`) implements `_on_hit()` by composing those primitives. No projectile type ever calls `PhysicsServer2D` or `AudioBus` directly.

### Engine/System-Level Usage

An `EditorTool` base class (in `@tool` scripts) provides `_select_nodes_in_group(group)`, `_mark_scene_dirty()`, and `_emit_tool_notification(msg)` as provided operations; each editor plugin subclass implements its specific tool behavior through those primitives with no direct `EditorInterface` or `EditorPlugin` API coupling, simplifying the upgrade path when Godot's editor API changes.

### Suggested Script Layout

```text
res://systems/powers/
    superpower.gd           # Node base — all provided operations and engine coupling
    sky_launch.gd           # extends Superpower — _activate() only
    frost_ray.gd            # extends Superpower — _activate() only
    ground_slam.gd          # extends Superpower — _activate() only
res://systems/status_effects/
    status_effect.gd        # Node base — provided ops for target mutation + VFX
    burn_effect.gd          # extends StatusEffect
    freeze_effect.gd        # extends StatusEffect
res://helpers/
    sound_helper.gd         # RefCounted — extracted SFX provided operations
    vfx_helper.gd           # RefCounted — extracted VFX provided operations
```

### Godot Performance Notes

**Node count implications** — Each `Superpower` or `StatusEffect` is a `Node` child of the entity it belongs to. For entities with many simultaneous powers, consider using `RefCounted` for the base class if the provided operations do not require SceneTree presence (no `_process`, no child nodes).

**Signal connection overhead** — If provided operations emit signals (e.g., `_play_sound` emits on `EventBus`), connection cost is O(1) per connection. Avoid connecting and disconnecting signals inside `_activate()` on every activation; connect in `_ready()` and leave them wired.

**SceneTree traversal cost** — Provided operations that call `get_tree().get_nodes_in_group()` inside `_activate()` traverse the group registry each invocation. Cache group results in the base class at `_ready()` if the group membership is stable.

### Godot Anti-Patterns

**Autoload calls in subclass `_activate()`** — Calling `AudioBus.play()` or `EventBus.spell_cast.emit()` directly inside a subclass bypasses the sandbox entirely; every such call is hidden coupling that the base class was meant to centralize. All engine-system calls belong in base class provided operations.

**Virtual provided operations** — Defining provided operations as `virtual` (or leaving them overridable in GDScript, which has no `final`) allows subclasses to override the engine access points, breaking the centralization guarantee. Provided operations should never be overridden; document this constraint explicitly.

**Bypassing the base class for "just this one call"** — A single direct `get_tree().get_node("AudioBus").play(sfx)` in one subclass creates a precedent; within weeks every subclass has direct couplings and the auditable single point is lost.

### GDScript Structural Example

```gdscript
# superpower.gd — all engine coupling lives here; subclasses see only _protected methods
class_name Superpower
extends Node

@export var owner_body: CharacterBody3D  # injected in Inspector; invisible to subclasses
@export var particle_root: Node3D        # VFX child nodes parented here

# Public entry point — never overridden
func use() -> void:
    _activate()

# --- Provided operations — underscore prefix = call-only contract for subclasses ---

func _move(direction: Vector3, impulse: float) -> void:
    if is_instance_valid(owner_body):
        owner_body.velocity += direction.normalized() * impulse

func _play_sound(stream: AudioStream, volume_db: float = 0.0) -> void:
    AudioBus.play(stream, volume_db)

func _spawn_particles(scene: PackedScene, at: Vector3) -> void:
    var node: Node = scene.instantiate()
    particle_root.add_child(node)
    (node as Node3D).global_position = at

func _get_owner_position() -> Vector3:
    return owner_body.global_position if is_instance_valid(owner_body) else Vector3.ZERO

# --- Sandbox method — subclasses override ONLY this ---
func _activate() -> void:
    pass
```

```gdscript
# sky_launch.gd — zero direct engine coupling; calls only provided operations
class_name SkyLaunch
extends Superpower

@export var launch_sound: AudioStream
@export var dust_vfx: PackedScene

func _activate() -> void:
    var pos: Vector3 = _get_owner_position()
    if pos.y < 0.05:
        _play_sound(launch_sound, 1.0)
        _spawn_particles(dust_vfx, pos)
        _move(Vector3.UP, 20.0)
    else:
        _move(Vector3.DOWN, pos.y * 3.0)
```

### Related Patterns

Template Method, Facade, Component, Update Method

### Competing Patterns

Bytecode, Type Object, Component

### Key Implementation Notes

- Provided operations should never be overridable; use underscore-prefix naming as a GDScript convention for call-only methods.
- When the base class exceeds fifteen provided operations, extract cohesive groups into helper `RefCounted` objects exposed via accessor methods; the subclass API remains compact.
- Prefer `@export` + Inspector injection over Autoload access for engine references that vary per instance; prefer Autoload calls directly in the base class for truly ambient services.
- Autoload presence is an implicit precondition of every subclass; document required Autoloads in the base class `## doc` comment so new subclass authors know the project requirements.
- Use `@export var enabled: bool = true` on the base class to give designers the ability to disable individual powers without removing the node.
- If provided operations are used by only one or two subclasses and have no side effects, allowing those subclasses to call the external system directly is a pragmatic tradeoff; add to the base class only when sharing is justified.

---

## Type Object

### Core Intent

Allow flexible creation of new "classes" by representing each logical type as an instance of a TypeObject class, so types can be defined in data and created at runtime without recompiling.

### Problem It Solves

Representing each monster breed as a code subclass makes adding or modifying breeds a programmer task requiring a recompile; designers cannot tune values without engineer involvement. A parallel class hierarchy for hundreds of enemy variants is a maintenance burden where each new type is multiple files of boilerplate.

### Engineering Motivation

Godot's `Resource` system is a native Type Object implementation: a `Resource` subclass with `@export` fields is designer-editable in the Inspector, serializable to `.tres` files, loaded at runtime without recompiling, and shared as a Flyweight across all instances via `ResourceLoader`. The C++ infrastructure the pattern required (registry, factory, lifetime management) is already provided by the engine.

### When to Use

- The set of types will change frequently or is not fully known at compile time — designers will add new variants without programmer involvement.
- Multiple entity instances share a fixed profile of attributes that varies only by type (breed, item class, weapon tier, spell school).
- Types should be editable in the Inspector, loadable from data files, or patchable without a full rebuild.
- Single-inheritance between type objects is needed so designers can define variants from a base profile without duplicating fields.

### When NOT to Use

- Each type requires meaningfully different behavior implemented in code rather than different data values; the Resource-based Type Object handles data variation well but behavioral variation requires GDScript subclasses of the Resource or explicit `Callable` delegation.
- The type set is small, fixed, and never changes — language-level subclassing or a plain enum is simpler and gives free compile-time type safety.
- The types differ by scene structure (different node hierarchies), not data — use `PackedScene` prototypes instead.

### Main Tradeoffs

| Benefit                                                                                        | Cost                                                                                                                          |
| ---------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| New types defined in the Inspector with no recompile — designers work independently            | Behavioral variation (code differences per type) requires GDScript Resource subclasses or enum dispatch, not just data fields |
| `ResourceLoader.load()` IS the type registry — uniqueness guaranteed, no custom infrastructure | Inheritance chains resolved lazily (dynamic) or manually at load time (copy-down); neither is automatic                       |
| `@export var parent: EnemyType` provides designer-level single inheritance                     | Circular parent chains are not detected at load time; a guard in `resolve_*` methods is required                              |
| Factory method on the type object (`spawn_scene: PackedScene`) centralizes allocation          | Type objects destroyed or hot-reloaded while instances hold references produce stale attribute values                         |

### Common Misuse

Using Type Object when types differ primarily by behavior rather than data, then attempting to encode behavioral logic in data fields (AI strategy names as strings, encoded state machine transitions) — manually reconstructing a vtable in `.tres` files with no compiler assistance.

### Failure Mode

A type Resource is reloaded or freed while typed instances still hold a reference to it; `resolve_*` calls return zero or empty values, entity behavior silently degrades, and the root cause is a `.tres` file that changed on disk without the instances being notified.

### Structural Model

```text
[Resource IS the Type Object — designer authoring via Inspector, no custom infrastructure]

enemy_type.gd (Resource subclass)     goblin_wizard.tres (edited in Inspector)
    @export max_health: int                max_health  = 35
    @export move_speed: float              move_speed  = 0.0    ← 0 = inherit from parent
    @export attack_name: String            attack_name = "casts fireball"
    @export parent: EnemyType    ────────▶ parent      = goblin_base.tres
    @export spawn_scene: PackedScene       spawn_scene = goblin_wizard.tscn

goblin_base.tres                       [copy-down resolution — walk parent chain at query]
    max_health  = 20                   goblin_wizard.resolve_health()  → 35  (override)
    move_speed  = 120.0                goblin_wizard.resolve_speed()   → 120.0 (inherit)
    attack_name = "punches"            goblin_wizard.resolve_attack()  → "casts fireball"

Enemy instances (many):
    Enemy_01.type ──▶ goblin_wizard.tres   ← shared Resource; Flyweight sharing is automatic
    Enemy_02.type ──▶ goblin_wizard.tres   ← same object in memory
    Enemy_03.type ──▶ goblin_base.tres

[Registry: ResourceLoader.load("res://types/goblin_wizard.tres") returns the same object]
[No custom registry, no manual lifetime management required]

[Behavioral variation — options in Godot]
  A. GDScript subclass of the Resource:  goblin_mage_type.gd extends EnemyType
     Override resolve_attack_behavior() in GDScript — strongest type safety
  B. Enum dispatch: @export var ai_strategy: AIStrategy
     match type.ai_strategy in enemy.gd — closed behavior set, data-driven
  C. Callable field (not serializable to .tres — runtime-only assignment only)
```

### Godot Adaptation Notes

- `Resource` with `@export` fields IS Type Object — no custom infrastructure is needed; the Inspector provides the authoring tool and `ResourceLoader` provides the registry.
- `ResourceLoader.load("res://types/goblin_warrior.tres")` always returns the same cached object for the same path; the uniqueness guarantee from the C++ implementation is automatic.
- The copy-down inheritance strategy maps to explicit `resolve_*` methods on the Resource that walk the `parent` chain; Godot provides no automatic field inheritance, so the delegation logic must be written once per field.
- The dynamic inheritance strategy (walk chain on every query) is the GDScript default and requires a circular-chain guard (`if parent == self or parent == null`).
- For behavioral variation, GDScript subclasses of the Resource are the most ergonomic option: a `GoblinMageType` that extends `EnemyType` overrides only the behavior methods relevant to mages; the Inspector still works, and `class_name` ensures type safety throughout the codebase.
- The factory method maps to `@export var spawn_scene: PackedScene` on the type Resource; `type.spawn_scene.instantiate()` gives the type control over the instantiated structure, enabling different node hierarchies per type.
- Callable fields cannot be serialized to `.tres`; use an `@export` enum with match dispatch in the entity script, or GDScript Resource subclasses, for persistent behavioral variation.

### Gameplay-Level Usage

An item system defines `WeaponType`, `ArmorType`, and `ConsumableType` Resources that designers author in the Inspector; the entire item database is a folder of `.tres` files. A content patcher replaces individual `.tres` files in a DLC directory; `ResourceLoader` picks up the new definitions on next load without any code change. A spell school system defines `SpellSchool` Resources with `@export resistance_mod: float` and `@export weakness_mod: float`; the damage formula reads these from the target's type chain at resolution time.

### Entity-Level Usage

An `Enemy` node holds `@export var type: EnemyType`; its `_ready()` reads `type.resolve_health()` for starting health and assigns `type.spawn_scene` to a spawner pool. Instance-level overrides (current health, aggro state, loot roll) stay on the `Enemy` node — the `EnemyType` Resource is never mutated at runtime. Calling `is_instance_valid(type)` before any `resolve_*` call guards against hot-reload races during development.

### Engine/System-Level Usage

A loot table system holds `Array[ItemType]` and `Array[float]` (weight) arrays populated at startup from a folder scan; `ResourceLoader.load_threaded_request()` loads all `.tres` type files in the background during the loading screen. A balance tuning workflow uses `@tool` scripts to read and compare `EnemyType` stats across the full type hierarchy from the editor, generating a spreadsheet-format report without running the game.

### Suggested Script Layout

```text
res://resources/types/
    enemy_type.gd           # Resource — @export fields + resolve_*() methods
    weapon_type.gd          # Resource — weapon variant of the pattern
    spell_type.gd           # Resource — spell variant
    data/
        enemies/
            goblin_base.tres
            goblin_warrior.tres     # parent = goblin_base.tres
            goblin_wizard.tres      # parent = goblin_base.tres
            troll.tres              # parent = null (root type)
        weapons/
            sword_base.tres
            longsword.tres          # parent = sword_base.tres
res://entities/enemy/
    enemy.gd                # CharacterBody2D — @export type: EnemyType
    enemy.tscn
```

### Godot Performance Notes

**Resource sharing vs. per-instance duplication** — Every enemy instance that references `goblin_warrior.tres` shares one `EnemyType` object in memory. Calling `resource.duplicate()` on a type Resource creates a per-instance copy and removes the Flyweight benefit; never duplicate type objects.

**SceneTree traversal cost** — `resolve_*()` methods walk the parent chain; for a chain of depth three, this is three property reads. For very hot-path resolution (called every `_physics_process`), cache the resolved value on the entity in `_ready()` rather than calling `resolve_*()` per tick.

**PackedScene instancing cost** — `type.spawn_scene.instantiate()` parses the full node tree each call; for high-frequency spawning, wrap the instancing in an Object Pool and use the type's `spawn_scene` as the pool's prototype.

**Memory allocation patterns** — Type Resources are reference-counted; they remain in memory as long as any instance holds them. If a type is unloaded from disk (hot-reload in editor, DLC unload), all instances holding that type must be notified or invalidated before the reference count drops to zero.

### Godot Anti-Patterns

**Mutating type Resources at runtime** — Writing to an `EnemyType` field at runtime (e.g., `enemy.type.max_health -= 5`) modifies the shared type object, affecting all instances of that type simultaneously. All mutable per-instance state must live on the entity node, never on the shared Resource.

**Calling `resource.duplicate()` for per-instance copies** — Duplicating a type Resource per entity instance eliminates the Flyweight sharing that makes the pattern efficient and creates independent copies that diverge from designer-authored values on hot-reload. Do not duplicate type Resources.

**Encoding behavioral logic in string fields** — Using a string field `ai_script_name = "patrol_then_chase"` and matching against it in entity code is a hidden enum with no type safety. Use a typed `@export` enum or a GDScript subclass of the Resource for behavioral variation.

### GDScript Structural Example

```gdscript
# enemy_type.gd — Type Object: a runtime "class" defined entirely in data
class_name EnemyType
extends Resource

@export var display_name: String = ""
@export var max_health: int = 0         # 0 = inherit from parent
@export var move_speed: float = 0.0     # 0.0 = inherit from parent
@export var attack_name: String = ""    # "" = inherit from parent
@export var parent: EnemyType = null    # single-inheritance chain; null = root
@export var spawn_scene: PackedScene    # factory: controls instantiated node structure

func resolve_health() -> int:
    if max_health > 0: return max_health
    return parent.resolve_health() if parent != null else 0

func resolve_speed() -> float:
    if move_speed > 0.0: return move_speed
    return parent.resolve_speed() if parent != null else 0.0

func resolve_attack_name() -> String:
    if not attack_name.is_empty(): return attack_name
    return parent.resolve_attack_name() if parent != null else "attacks"

func spawn(at: Vector3, parent_node: Node) -> Node:
    assert(spawn_scene != null, "EnemyType '%s' has no spawn_scene." % display_name)
    var instance: Node = spawn_scene.instantiate()
    parent_node.add_child(instance)
    if instance is Node3D:
        (instance as Node3D).global_position = at
    return instance
```

```gdscript
# enemy.gd — typed instance; per-instance state here, shared data via type reference
class_name Enemy
extends CharacterBody2D

@export var type: EnemyType  # assign goblin_warrior.tres in Inspector

var current_health: int = 0

func _ready() -> void:
    assert(is_instance_valid(type), "Enemy requires an EnemyType resource.")
    current_health = type.resolve_health()  # cache resolved value — never call per-tick

func get_current_attack_name() -> String:
    # Instance override: injured enemies display a different attack.
    if current_health < type.resolve_health() * 0.2:
        return "flails weakly"
    return type.resolve_attack_name()   # reads shared type data; never mutates it

func get_speed() -> float:
    return type.resolve_speed()
```

### Related Patterns

Flyweight, Prototype, State, Factory Method

### Competing Patterns

Language-level subclassing, Bytecode, Prototype, Flyweight

### Key Implementation Notes

- `Resource` with `@export` fields IS the Godot Type Object — no custom registry, no manual lifetime management, no factory scaffolding.
- Never mutate a type `Resource` at runtime; all per-entity mutable state belongs on the entity node.
- Cache `resolve_*()` results in the entity's `_ready()` for any field read in `_physics_process`; parent-chain traversal is cheap but unnecessary on the hot path.
- Add a circular-chain guard (`assert(parent != self)` in `_init()` or `resolve_*()`) — the Inspector does not prevent circular `parent` assignments.
- For behavioral variation, GDScript Resource subclasses (override `resolve_attack_behavior()`) are preferred over enum dispatch; they maintain the Inspector workflow and add no runtime overhead.
- `ResourceLoader.load()` caches by path — assign the same `.tres` to all instances of a type in the Inspector; the engine guarantees they reference the same object.
- `type.spawn_scene.instantiate()` is the factory method; use it for spawning from type-controlled templates and wrap in an Object Pool for high-frequency spawning.

---
