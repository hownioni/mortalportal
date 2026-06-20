# Project: Mortal Portal

Action/Puzzle platformer in Godot 4.x. GDScript unless otherwise specified. Full-refactor.

Godot 4.6 -- GL Compatibility renderer -- Jolt Physics.

For deeper architectural rationale, reference: `@docs/architecture-principles.md`

## Branch structure

- `prerefactor` branch: original source — more complete, but messier code.
  - mounted at `../mortalportal-prerefactor/` (git worktree, reference only).
- `refactor-attempt-0` branch: earlier Claude-assisted attempt — stopped early,
  but what it built was done mostly right.
  - mounted at `../mortalportal-refactor-attempt-0/` (git worktree, reference only).
- `full-refactor` branch (current): active refactor target.

### Reference policy

- **Structure and code patterns:** model on `refactor-attempt-0` — folder layout,
  component wiring, naming, style.
- **Behavior and features:** neither branch is the default. When a feature exists in
  both, read both, start from whichever is more complete/better-built (often
  `refactor-attempt-0`), and surface the comparison instead of defaulting to
  `prerefactor`. Pull from `prerefactor` for features `refactor-attempt-0` never built.
- Always read the relevant source(s) before writing new code. Reusing code is fine;
  ask before copying non-trivial chunks from `refactor-attempt-0`.
- When creating a new domain folder or subsystem, copy the matching assets (textures,
  `.tres` resources, source files) from `refactor-attempt-0` into the equivalent path in
  `full-refactor` as part of the same task. Do not copy `.import` sidecars -- Godot
  regenerates those. Do not copy `.tres` files that reference stale or wrong asset paths
  without verifying first.

---

# Quick rule reference

## Folder Structure

Organize by **game domain**, not file type. The folder tree should describe what the game does.
The structure below is an example -- actual folders are named after the game's specific domains.

```
res://
├── combat/           # damage, stats, status effects, targeting
├── inventory/        # items, equipment, loot
├── dialogue/         # conversation trees, speakers
├── world/            # maps, environment, spawning
├── characters/       # player, enemies, NPCs (each in a subfolder)
├── ui/               # menus, HUD, popups
├── core/             # autoloads, base classes, shared utilities
└── assets/           # textures, audio, fonts — mirrors above structure
```

Never use engine-centric top-level folders like `scripts/`, `scenes/`, `resources/`, or `nodes/`.
Each domain folder owns its own `.gd` files, `.tscn` scenes, and `.tres` resources.

---

## Architectural Rules

### Scene boundaries

- A scene must never reach into another scene's internal nodes (`$SubNode/Child` is fine inside the owner scene; `get_node("/root/SomeOtherScene/InternalNode")` is forbidden).
- Expose behavior through methods and signals only. Internal node structure is private.

### Communication

- Use **signals** for "something happened" events crossing scene or node boundaries.
- Use **exported variables** (`@export`) to inject dependencies rather than hardcoding node paths.
- Reserve `EventBus` autoload for game-wide broadcast events (e.g. `player_died`, `game_paused`). Don't route everything through it.

### Autoloads (singletons)

Only create an autoload for systems that are genuinely global and stateful across scenes:

- `EventBus` — signal hub for cross-scene events
- `GameState` — persisted data (score, progression, settings)
- `AudioManager` — pooled audio playback

Do **not** autoload something just to avoid passing a reference. Use `@export` instead.

### Composition over inheritance

- Prefer child nodes as components over subclassing. Add behavior by adding a child node.
- Maximum **2 levels** of class inheritance. If you need a 3rd, use composition instead.
- When an entity needs a new behavior (e.g. "can take damage"), add a `HealthComponent` child node — don't subclass the entity.
- Component wiring (access, host injection, orchestration, signals) follows
  `@docs/refactor-architecture.md` Component Rules.

### Data lives in Resources

- Stats, item definitions, damage formulas, and tunable constants belong in `.tres` Resource files, not hardcoded in scripts.
- Scripts reference Resources via `@export` — this keeps logic and data separated and makes data editable in the Inspector without touching code.

### Module depth (interfaces)

- Each system (combat, inventory, etc.) should expose a **small, clear interface** and hide its implementation.
- Example: `CombatSystem.apply_damage(target: Node, amount: float, type: DamageType)` — callers don't know or care about resistances, shields, VFX, or animation triggers happening inside.
- Do not extract tiny helper nodes just to reduce line count. Meaningful encapsulation > many small files.

### Change cost test

If implementing a change requires editing **3 or more unrelated files**, stop and question the design before proceeding. That's a coupling smell.

---

## Testing

GUT (`addons/gut/`). Full policy: `@docs/testing-conventions.md`.

- **Deterministic** behavior (sizing math, position/clamp/zoom, "does this `Control` fit the viewport") is **test-first with GUT** -- Claude owns correctness. Run the suite as the completion gate (alongside the `--import` parse-check):
  `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
- **Perceptual** behavior (camera feel: smoothing, deadzone, lookahead) is **not tested** -- expose it as `@export` / a tunable `Resource` and let the user dial it in the editor.
- Scene wiring, physics, and input are validated by **playtest**, not unit tests.
- Tests live in `test/unit/` and `test/integration/`, mirroring domain folders.

---

## GDScript Conventions

- **Indentation:** 4 spaces, never tabs. Convert any tab-indented file to spaces when you modify it.
- **Naming:** `snake_case` for variables/functions, `PascalCase` for classes/nodes, `ALL_CAPS` for constants.
- **Signals** declared at the top of the file, before variables.
- **No magic numbers.** Every numeric constant gets a named `const` or a Resource field.
- **Function length:** A function should do one thing. If you need a comment to separate "phases" inside a function, split it.
- **Type hints everywhere** on new or modified code. Do not retrofit hints onto code not being changed. Use `: Type` on all variables and `-> Type` on all function signatures.
- **`@onready`** for node references; never assign node references in `_init()`.

---

## What to Do When Uncertain

1. **New system needed?** Start from the domain boundary — what is the minimal public interface? Build that first, fill internals second.
2. **Existing code smells?** Check `@docs/architecture-principles.md` §3 (Coding Practices) for the smell catalog and refactoring moves.
3. **Unsure which architecture pattern fits?** Check `@docs/architecture-principles.md` §4 (Architectures) for the decision table.
4. **Inheritance vs. composition?** Default to composition. Justify inheritance explicitly in a comment if you use it.

## Output

- Return code first. Explanation after, only if non-obvious.
- No inline prose. Use comments sparingly - only where logic is unclear.
- No boilerplate unless explicitly requested.

## Code Rules

- Simplest working solution. No over-engineering.
- Simplicity applies within a system's internals. Composition and interface rules in the architectural section govern structure between systems — those take precedence.
- Prefer self-documenting code over excessive comments
- No abstractions for single-use operations.
- No speculative features or "you might also want..."
- No docstrings or type annotations on code not being changed.
- No error handling for scenarios that cannot happen.
- Three similar lines is better than a premature abstraction.

## Review Rules

- State the bug. Show the fix. Stop.
- No suggestions beyond the scope of the review.

## Debugging Rules

- Never speculate about a bug without reading the relevant code first.
- State what you found, where, and the fix. One pass.
- If cause is unclear: say so. Do not guess.
