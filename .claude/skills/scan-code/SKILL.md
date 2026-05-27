---
name: scan-code
description: >
  Audits GDScript code in this Godot project for architectural violations, code smells, and
  convention errors defined in CLAUDE.md and docs/architecture-principles.md.

  TRIGGER THIS SKILL for any of the following:
  - User asks to scan, audit, check, review, look at, look over, look through, or inspect code
  - User asks if code is good, clean, correct, healthy, well-structured, or follows conventions
  - User mentions code quality, code health, code smells, bad code, messy code, spaghetti code
  - User mentions architecture issues, bad structure, design problems, coupling, or tech debt
  - User asks about type hints, naming conventions, magic numbers, or GDScript style
  - User asks about scene boundaries, autoloads, signals, exports, or inheritance depth
  - User finishes implementing a feature or refactor and might want a quality check
  - User says things like "is this okay?", "anything wrong here?", "does this look right?"
  - User asks for a "pass", "once-over", "second pair of eyes", or "sanity check" on code
  - User asks about folder structure or project organization

  Do NOT trigger for: adding features, fixing specific bugs (unless scanning for root cause),
  explaining code, writing tests, or tasks unrelated to code quality assessment.
---

# GDScript Code Scanner

Audits GDScript files against the rules in `CLAUDE.md` and `docs/architecture-principles.md`.

## Scope

If the user specifies a file, folder, or diff, scan that. Otherwise scan all `.gd` files in
the project (excluding `.godot/`):

```bash
find . -name "*.gd" -not -path "./.godot/*" | sort
```

When scanning the whole project, also check the folder structure at `res://` level.

---

## How to Work

Run the grep-based checks first (fast, parallel). Then read each file for semantic checks.
Do not speculate about a finding without reading the relevant code — if a grep hit looks
ambiguous, read the surrounding context before reporting it.

---

## Check 1 — Folder Structure

The top-level of `res://` must describe what the game **does**, not what Godot is.

**Forbidden top-level names:** `scripts/`, `scenes/`, `resources/`, `nodes/`, `autoloads/`

**Allowed domain names:** `combat/`, `inventory/`, `dialogue/`, `world/`, `characters/`,
`ui/`, `core/`, `assets/` (and any other game-domain name)

```bash
find . -maxdepth 1 -mindepth 1 -type d \
  -not -path "./.git" -not -path "./.godot" -not -path "./.claude" \
  -not -path "./addons"
```

Flag any result that is an engine-centric name.

**Severity: Error**

---

## Check 2 — Scene Boundary Violations

A script must never reach into another scene's internal nodes. The only safe `get_node()` calls
are within the node's own scene.

```bash
# Absolute root paths — always a violation
rg 'get_node\("/root/' -g "*.gd" -n

# Multi-level paths — likely crossing a scene boundary
rg 'get_node\("[^"]*\/[^"]*\/' -g "*.gd" -n

# Variable.get_node() — most common form: accessing internals of an injected/instantiated scene
rg '\b[a-z_]+\.get_node\(' -g "*.gd" -n
```

For each hit, read 5–10 lines of context to confirm it crosses a scene boundary.
`$Child` shorthand within the owning scene's `_ready()` is fine. The violation is calling
`get_node()` on a _variable_ that holds another scene — you're coupling to its internal
structure rather than its public interface.

**Severity: Error**

---

## Check 3 — Communication Anti-patterns

### 3a. Hardcoded node paths as dependencies

Dependencies should come via `@export`, not hardcoded `get_node()` strings.

```bash
# Variable assigned directly from get_node with a string literal
rg '= get_node\("' -g "*.gd" -n
```

Distinguish between `@onready var x = $Child` (fine — shorthand for own scene) and
`var x = get_node("/root/...")` or `= get_node("../OtherScene/...")` (violation).

**Severity: Warning** for any `get_node()` dependency that should be `@export`.

### 3b. EventBus overuse

EventBus is for game-wide broadcast events (e.g. `player_died`, `game_paused`). Anything
local should use direct signals or `@export`.

```bash
rg 'EventBus\.' -g "*.gd" -n
```

For each hit, read context. Flag if EventBus is used for something that isn't genuinely
game-wide (e.g. parent-child communication, same-scene events).

**Severity: Warning**

### 3c. Undeclared or unexpected autoloads

Only `EventBus`, `GameState`, and `AudioManager` are sanctioned autoloads. Other capitalized
bare names accessed like singletons are suspicious.

```bash
rg '\b[A-Z][A-Za-z]+\.[a-z_]' -g "*.gd" -n \
  | rg -v '^\s*#' \
  | rg -v 'ClassName\|PackedScene\|Vector\|Color\|Input\|OS\|Engine\|Time\|JSON\|FileAccess\|DirAccess\|ResourceLoader\|AnimationPlayer\|Node\|Callable\|Signal\|Array\|Dictionary\|String\|int\|float\|bool'
```

Read context for each hit and flag any autoload name that is not in the approved list.

**Severity: Warning** per non-sanctioned autoload. **Error** if something is clearly autoloaded
just to avoid passing a reference (should be `@export` instead).

---

## Check 4 — Inheritance Depth

Maximum 2 levels of inheritance from the project's own classes (Godot built-ins count as level 0).

**Detection:**

```bash
rg '^extends ' -g "*.gd" -n
```

For each `extends YourOwnClass`, look up whether `YourOwnClass` itself extends another of
your classes. Flag any chain of 3+ levels.

Built-in Godot classes (`CharacterBody2D`, `Node`, `Area2D`, `Resource`, etc.) = level 0.
Your class extending a built-in = level 1. Another class extending that = level 2. A third = violation.

**Severity: Error** for chains > 2 levels.

---

## Check 5 — GDScript Conventions

Run all these greps before reading files.

### 5a. Missing type hints on variables

```bash
rg '^(\s*)var [a-z_]+ =' -g "*.gd" -n | rg -v ': [A-Za-z\[\]]'
```

A variable declared as `var x = value` without `: Type` is missing a type hint.
`@onready var` and `@export var` follow the same rule.

**Severity: Warning**

### 5b. Missing return type hints on functions

```bash
rg '^(\s*)func [a-z_]+\([^)]*\)(\s*):' -g "*.gd" -n | rg -v '->'
```

Every function needs `-> Type` (use `-> void` if it returns nothing).

**Severity: Warning**

### 5c. Magic numbers

Bare numeric literals in expressions (not `const` assignments, not `0`, `1`, `-1`):

```bash
rg '[^=\s](\s+)?[+\-\*\/]=?(\s+)?[0-9]{2,}' -g "*.gd" -n | rg -v 'const ' | rg -v '^\s*#'
```

Also check for float literals in arithmetic:

```bash
rg '\b[0-9]+\.[0-9]+\b' -g "*.gd" -n | rg -v 'const ' | rg -v '^\s*#'
```

**Severity: Warning** per instance.

### 5d. Naming conventions

camelCase variables or functions (should be snake_case):

```bash
rg '^(\s*)(var|func) [a-z]+[A-Z]' -g "*.gd" -n
```

Constants not in ALL_CAPS:

```bash
rg '^(\s*)const [a-z]' -g "*.gd" -n
```

**Severity: Warning**

### 5e. Node references in `_init()`

```bash
rg -A 30 'func _init\(' -g "*.gd" | rg 'get_node\|= \$'
```

**Severity: Error**

---

## Check 6 — Code Smells (Read-based)

Read each file and check for these. Don't skip this step — it catches the problems grep can't.

### Long Method

A function doing more than ~20 lines almost certainly violates "do one thing". Count lines
between consecutive `func` declarations. If a function has a comment that separates "phases"
(e.g. `### INPUT`, `# Phase 2`), that's a guaranteed smell — each phase should be its own function.

### Section comments inside functions

```bash
rg '^\s*#{2,}|^\s*# ---' -g "*.gd" -n
```

Section dividers inside a function body mean the function has multiple responsibilities.

### Feature Envy

A method that calls methods on another object many times but touches very little of its own
state. The method probably belongs in the other class.

### Data Clumps

Three or more variables that always travel together as parameters or fields. They belong in
a Resource.

### Primitive Obsession

Using `int` or `String` for a concept that deserves an enum or Resource (e.g. `int damage_type`
instead of `DamageType` enum).

### Middle Man

A class that mostly just forwards calls to another object without adding logic.

### Divergent Change

A single script that handles multiple unrelated concerns — e.g., input handling, physics,
and save state all in one `_physics_process`. Use the method name list to identify this.

---

## Report Format

Structure findings like this:

```
# Code Scan Report
Files scanned: <N>

## Errors (must fix before merging)

[FOLDER_STRUCTURE] res://scenes/
  Rule: CLAUDE.md §Folder Structure — no engine-centric top-level folders
  Found: `scenes/` at project root

[SCENE_BOUNDARY] characters/player/level_controller.gd:47
  Rule: CLAUDE.md §Scene boundaries — never reach into another scene's internals
  Found: `_insted_lvl.get_node("PlayerSpawn")` — reaching into instantiated scene

## Warnings (should fix)

[MISSING_TYPE_HINT] characters/player/player.gd:12
  Rule: CLAUDE.md §GDScript Conventions — type hints everywhere
  Found: `var _alive = true` — missing `: bool`

[LONG_METHOD] world/level_controller.gd:_create_lvl()
  Rule: architecture-principles.md §3 — function should do one thing
  Found: 35 lines; split into _spawn_player() and _create_level_instance()

[CODE_SMELL:SectionComment] characters/player/player.gd:_physics_process
  Rule: architecture-principles.md §3 — section comment = multiple responsibilities
  Found: `### INPUT` comment inside _physics_process(); extract input to _get_input()

## Summary

<N errors>, <N warnings>. Start with the folder structure errors — they block everything else.
The scene boundary violation in level_controller.gd is the highest-risk bug.
```

Group by severity. Within each group, list by file. Be specific: name the rule, quote the
offending line, and say what to do about it.

---

## Depth options

- **Full scan** (default): all checks, all files.
- **Quick scan** (user says "quick" or specifies a single file): skip Check 6 (code smells),
  run only greps.
- **Targeted** (user gives a folder or diff): limit scope but run all checks on that scope.
