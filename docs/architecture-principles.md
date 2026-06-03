# Architecture Principles Reference

> **Usage in Claude Code:** Reference this file on demand with `@docs/architecture-principles.md`.
> It is _not_ loaded every session — use it when you need deeper rationale or a decision framework.
> The source canon for these principles is documented in the project's curated reading list.

---

## 1. Project & File Organization

### The Screaming Architecture Rule

_(Source: Robert C. Martin, "Screaming Architecture")_

The top-level folder structure should announce what the game _does_, not what engine it runs on.
A glance at `res://` should tell you "this is a combat RPG" — not "this uses Godot."

**Apply it:** When creating a new system, ask: "does this folder name describe a game concept or an engine concept?" Game concepts win.

### Folder ownership

Each domain folder is self-contained:

- Its `.gd` scripts, `.tscn` scenes, and `.tres` resources all live together.
- A feature can be understood, moved, or deleted by working within one folder.
- Cross-domain dependencies are explicit (signals, exported variables), never implicit (hardcoded paths into another domain's internals).

### File naming

Name files after what they _do_, not what they _are_. `damage_calculator.gd` > `calculator.gd`. `enemy_health_component.tscn` > `health.tscn`.

---

## 2. Programming Patterns

### When to use each pattern (Godot-specific)

| Situation                            | Pattern         | Godot mechanism                                            |
| ------------------------------------ | --------------- | ---------------------------------------------------------- |
| "Notify others when X happens"       | Observer        | `signal` + `connect()`                                     |
| "Swap behavior at runtime"           | Strategy        | Pass a Resource or a child node with a shared interface    |
| "Queue and replay player actions"    | Command         | `Action` class with `execute()` / `undo()`                 |
| "Entity transitions through states"  | State Machine   | Dedicated `StateMachine` child node + `State` resources    |
| "Compose entity from behaviors"      | Component       | Child nodes (`HealthComponent`, `MovementComponent`, etc.) |
| "One shared instance"                | Service Locator | Autoload — use sparingly, prefer `@export` injection       |
| "Build complex objects step by step" | Builder         | Factory function or `_create_()` static method on a class  |

### Observer / Signals

- Declare signals at the **top** of the file.
- Name signals in **past tense**: `health_depleted`, `item_picked_up`, `level_completed`.
- A signal communicates _that_ something happened, not _what to do about it_. The emitter does not know its listeners.
- For game-wide events, route through `EventBus` autoload. For local parent–child communication, connect directly.

### Strategy (swappable behavior)

Use when the same entity needs different algorithms at runtime — damage formulas, AI behaviors, movement types.

```gdscript
# DamageFormula is a Resource subclass with a `calculate(attacker, target) -> float` method.
# Swap the formula without touching the combatant.
@export var damage_formula: DamageFormula
```

### State Machine

Prefer an explicit state machine over a tangle of `if` / `elif` chains for entity behavior.
Each state is a Resource or inner class with `enter()`, `update(delta)`, and `exit()` methods.
The machine node owns the transition logic.

### Component (Composition over Inheritance)

_(Source: Mick West, "Evolve Your Hierarchy")_

Add capabilities to entities by attaching child nodes, not by subclassing.

```
Enemy (CharacterBody2D)
├── HealthComponent      ← handles HP, death signal
├── HurtboxComponent     ← detects incoming damage
├── AIComponent          ← state machine, pathfinding
└── LootComponent        ← drops on death
```

A player and an enemy can both have a `HealthComponent` without sharing a base class. A barrel can have `HealthComponent` and `LootComponent` without being an "entity."

**When inheritance IS appropriate:**

- A clear "is-a" relationship exists (not just "shares some code").
- You have 2 or fewer levels.
- The subclass only _extends_ the parent — it does not override or suppress behavior.

Any subclass hierarchy that grows wide rather than deep quickly produces the **brittle base class problem** — a change to any shared base risks breaking all derived classes simultaneously.

---

## 3. Coding Practices

### The ETC Principle — Easier to Change

_(Source: The Pragmatic Programmer, Hunt & Thomas)_

The primary measure of good design is: _how easy is it to change this later?_
Before every design decision, ask: "if requirements change (and they will), will this be easy to modify?"
Decoupling, good naming, and small interfaces all serve ETC.

### Pragmatism Over Purity

Architectural cleanliness should yield when code is explicitly prototypal and will be discarded, or when the time cost of getting the architecture right exceeds the shipping deadline's tolerance.

"Good enough" means the minimum structure that lets the current work proceed without creating _irreversible_ technical debt. The threshold is whether the team can still freely change the affected code next week without heroics — not whether it would earn high marks in a code review.

### DRY — Don't Repeat Yourself

_(Source: The Pragmatic Programmer)_

Every piece of knowledge has a **single, authoritative representation**.

- Stats and constants → one `.tres` Resource, not copy-pasted across scripts.
- A damage formula → one function, not duplicated in player scripts and enemy scripts.
- DRY applies to _knowledge_, not just code. Two functions that happen to look alike but represent different concepts are fine.

### Performance-Aware Design

_(Source: Mike Acton, "Data-Oriented Design"; Game Programming Patterns, Nystrom)_

Hot paths and cold paths require different design postures. Game loops, entity update paths, and physics systems are hot paths where cache misses, per-frame heap allocation, and virtual dispatch overhead directly affect frame stability. Most code is cold path and should be written for clarity first.

**Rules:**

- Let profiler data, not intuition, drive optimization decisions. Identify the actual bottleneck before restructuring.
- Premature abstraction that fragments data in memory or adds pointer indirection in tight loops can cost more performance than the design flexibility it gains.
- Distinguish hot from cold at the system level: damage formulas, inventory rules, and quest logic are cold; bullet update loops and particle systems are hot. Design them accordingly.

### The "Deep Module" Ideal

_(Source: A Philosophy of Software Design, Ousterhout)_

A good module has a **simple interface** hiding a **complex implementation**.
The combat system's public surface might be three methods. The 500 lines of resistance math, status-effect stacking, and animation triggers behind it are implementation details callers never see.

**Red flags for shallow modules (avoid):**

- A class with one method that does one obvious thing.
- A wrapper that adds no abstraction — just passes calls through.
- A function whose name and signature together fully describe its body.

**Red flags for complexity (avoid):**

- _Change amplification:_ one logical change requires edits in many places.
- _Cognitive load:_ a reader needs to hold many things in mind simultaneously to understand one piece of code.
- _Unknown unknowns:_ it's not obvious what you need to know to make a change safely.

### Code Smell Catalog

_(Source: Refactoring, Fowler)_

Recognize these as signals to refactor — not emergencies, but scheduled maintenance:

| Smell                      | What it looks like                                  | Move to make                           |
| -------------------------- | --------------------------------------------------- | -------------------------------------- |
| **Long Method**            | Function > ~20 lines, does multiple things          | Extract Method                         |
| **Feature Envy**           | Method uses another object's data more than its own | Move Method                            |
| **Data Clumps**            | Same 3+ variables always appear together            | Introduce Parameter Object or Resource |
| **Primitive Obsession**    | `int damage_type` instead of `enum DamageType`      | Replace Primitive with Object/Enum     |
| **Shotgun Surgery**        | One change requires edits in many unrelated files   | Move related code together             |
| **Divergent Change**       | One class changes for many different reasons        | Split class by responsibility          |
| **Middle Man**             | A class that mostly delegates to another            | Remove Middle Man                      |
| **Inappropriate Intimacy** | Class A accesses Class B's internals                | Move fields, use signals instead       |
| **Parallel Inheritance**   | Adding a subclass requires adding one elsewhere too | Collapse hierarchy with composition    |

### Naming

- Names reveal **intent**, not implementation: `get_damage_after_resistance()` > `calc_dmg()`.
- Booleans are assertions: `is_alive`, `has_target`, `can_attack`.
- Don't abbreviate unless the abbreviation is universal (`hp`, `id`, `ui`).
- If you need a comment to explain a variable's name, rename the variable.

### Function discipline

- A function does **one thing**. If you need a section comment (`# Phase 2: apply effects`), that section is a function.
- Functions don't have side effects callers don't expect. A function named `get_health()` should not modify state.
- Prefer returning values over mutating arguments.

---

## 4. Software Architectures

### Dependency Direction

_(Source: Clean Architecture, Martin)_

Dependencies point **inward** — toward game logic, away from the engine.

```
Engine (Godot)  →  Interface Adapters (your nodes)  →  Game Rules (pure GDScript classes)
```

Your damage formula, quest logic, and inventory rules should be testable without running the engine. They should not call `get_tree()`, emit signals to the scene, or reference specific nodes. Nodes _use_ the logic; logic doesn't _know_ about nodes.

**Practical Godot form:**

- Pure GDScript classes (no `extends Node`) hold game rules.
- Nodes hold scene state and wire signals.
- Resources hold data.

### Event-Driven / Decoupled Architecture

Use events (signals) to decouple systems that would otherwise create circular dependencies.

**Good pattern:**

```
CombatSystem  →  emits: damage_applied(target, amount)
HealthSystem  →  listens: updates HP, emits health_depleted
UISystem      →  listens: updates health bar
VFXSystem     →  listens: plays hit effect
```

No system knows the others exist. Adding a new system (e.g. `AchievementSystem`) requires zero changes to existing systems — it just connects to the signals it cares about.

**When not to use events:**

- When the result is needed _synchronously_ (return values are better).
- When the flow becomes impossible to trace. Events are for "fire and forget" notifications, not for driving control flow.
- When both systems _always_ change together — if system A and system B are tightly co-evolved in practice, the indirection of a signal delivers no flexibility benefit and only obscures the relationship. Direct coupling is honest; reserve events for things that actually need to vary independently.

### ECS (Entity-Component-System)

_(Source: Sander Mertens, ECS-FAQ; Mike Acton, CppCon 2014)_

ECS separates **data** (components) from **logic** (systems) and **identity** (entities).
Godot's node system is not pure ECS, but you can approximate ECS thinking:

- **Entities** = nodes (identified by NodePath or RID).
- **Components** = child nodes or Resources holding _only data_ (no logic).
- **Systems** = Autoloads or manager nodes that iterate entities and process component data.

**When ECS pays off in games:**

- Many entities of the same kind (hundreds of bullets, enemies, particles).
- Performance-critical loops (damage resolution, collision, pathfinding).
- Systems that need to process all entities of a type at once (turn-based resolution, simulation tick).

**When ECS is overkill:**

- You have fewer than ~50 entities of a type.
- Entity behavior is highly individual (the player, the boss).
- Your game is not performance-bottlenecked on entity iteration.

Godot's built-in scene system + signals handles most indie-scale games well. Reach for ECS discipline when you hit specific problems, not preemptively.

### MVC in Godot

Model-View-Controller maps naturally:

- **Model** = Resource (data) + pure GDScript class (rules). No engine dependencies.
- **View** = Node subtree responsible for display only. Reads from Model, emits UI events.
- **Controller** = Node that owns the Model, responds to View events, updates Model, notifies View via signals.

The key rule: the Model never references the View. The View never modifies the Model directly — it signals intent to the Controller.

### Dependency Injection

_(Source: Dependency Injection Principles, Practices, and Patterns — Seemann & van Deursen)_

Inject dependencies rather than creating them internally.

```gdscript
# Bad: CombatSystem creates its own DamageCalculator.
# Changing the formula requires editing CombatSystem.
func _ready():
    _calculator = PhysicalDamageCalculator.new()

# Good: CombatSystem receives its calculator from outside.
# Swap formulas without touching CombatSystem.
@export var damage_formula: DamageFormula
```

In Godot, `@export` is your primary DI mechanism. Autoloads are a Service Locator — acceptable for truly global services, but overuse hides dependencies and makes systems hard to test.

When a global service (audio, logging, analytics) cannot reasonably be passed via `@export`, a Service Locator Autoload is acceptable — but back it with a **null-object fallback** so every call site is safe before registration and in tests. A raw Autoload that can return `null` is an unguarded singleton waiting to crash.

---

## 5. Decision Guides

### "Should this be a child node or a new class?"

- Does it need to exist in the scene tree (physics, input, rendering, timers)? → **Child node.**
- Is it pure logic or data with no scene presence? → **GDScript class or Resource.**

### "Should I use inheritance or composition?"

Ask: _Is this genuinely an "is-a" relationship, or is it "has-a / can-do"?_

- `Enemy` **is-a** `CharacterBody2D` → inheritance is fine.
- `Enemy` **can take damage** → `HealthComponent` child node.
- `Enemy` **can drop loot** → `LootComponent` child node.
- `FlyingEnemy` **is-a** `Enemy` with added flight behavior → prefer composition (`FlightComponent`) over subclassing.

### "Should this be an Autoload?"

Only if all three are true:

1. It is needed by many scenes that don't share a common ancestor.
2. It has meaningful state that must persist across scene transitions.
3. You cannot reasonably pass it via `@export`.

If only #1 is true, pass it via `@export`. If only #2 is true, use a Resource saved to disk.

### "Is my module too coupled?"

Signs you've crossed the line:

- You can't unit-test this class without loading a scene.
- A change in `InventorySystem` requires a change in `CombatSystem`.
- You find yourself passing `get_tree()` or `get_parent()` deep into a utility function.
- You need to `call_deferred` to avoid call-order problems that shouldn't exist.

### "Is this pattern solving a real problem?"

Before introducing a pattern or abstraction layer, ask:

- Does this solve a present, concrete problem — not a hypothetical future one?
- Is the abstraction cost proportional to the actual benefit at the current codebase scale?
- Would a simpler, more direct approach work given the current size?
- Is this pattern being applied because it _fits_, or because it's _familiar_?

A pattern that adds indirection without delivering concrete flexibility, testability, or change-isolation is complexity, not architecture.

---

## 6. Refactoring Approach for Existing Code

_(Source: Working Effectively with Legacy Code, Feathers; Refactoring, Fowler)_

When you need to change code you (or AI) wrote previously:

1. **Characterize first.** Write a test (or at minimum, document the current behavior) before changing anything. You need to know what you're preserving.
2. **Find the seam.** A seam is a place where you can change behavior without editing the calling code — usually a signal connection, an `@export` slot, or a virtual method.
3. **Scratch-refactor to understand.** Make exploratory refactoring changes, understand the structure, then _revert_ and do it properly. Never ship exploratory code.
4. **One smell at a time.** Pick one smell (e.g. Data Clumps), refactor it completely, confirm behavior is unchanged, then pick the next.
5. **Rename ruthlessly.** A better name is always worth the rename refactor. Future readers (including you) will thank you.
