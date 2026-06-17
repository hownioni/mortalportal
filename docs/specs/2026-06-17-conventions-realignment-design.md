# Conventions Realignment — Design

Approved 2026-06-17. Two guidance changes, applied across the project's docs and memory:

1. **Reference policy** — stop treating `prerefactor` as the default behavior canon.
2. **Component-wiring convention** — codify the aviones-style pattern the player already uses.

Canonical home: `docs/refactor-architecture.md` (the architectural contract). Other docs
carry short pointers / reweighted lines (Approach A — single source of truth).

---

## Change 1 — Reference policy

**Problem:** `CLAUDE.md` and `refactor-roadmap.md` name `prerefactor` as "source of truth
for behavior" and `refactor-attempt-0` (r-a-0) as the secondary "what was tried" reference.
In practice r-a-0 stopped early but built things mostly right, and is sometimes the richer
implementation (e.g. player movement). Defaulting to prerefactor framed the better-built
version as an optional upgrade.

**Rule:**

- **Structure and code patterns** — model on r-a-0: folder layout, component wiring,
  naming, style.
- **Behavior and features** — neither branch is the default. When a feature exists in both,
  read both, start from whichever is more complete/better-built (often r-a-0), and surface
  the comparison instead of defaulting to prerefactor. Pull from prerefactor for features
  r-a-0 never built.
- Always read the relevant source(s) before writing new code. Reusing code is fine; ask
  before copying non-trivial chunks from r-a-0.

**Edits:**

- `CLAUDE.md` → "Branch structure": rewrite the branch list (drop the stale "clean slate"
  line) and add a "Reference policy" subsection with the rule above.
- `docs/refactor-roadmap.md:21-22`: replace the "Source of truth / reference for what was
  tried" lines with a structure-vs-behavior split pointing to CLAUDE.md "Reference policy".
- `docs/refactor-phase-1-tasks.md:14-16`: replace the global "Behavior source / reuse
  reference" sentences with a pointer to CLAUDE.md "Reference policy". Per-task
  "Behavior source: prerefactor X" lines stay as named starting files; the global policy
  governs how to treat them.

---

## Change 2 — Component-wiring convention

Codify the pattern already used by `PortalMovementComponent` + `player.gd` (and modeled on
the `aviones` project). Canonical text lives in `docs/refactor-architecture.md`.

**The convention:**

- **a. Component = thin `Node`.** `class_name XxxComponent extends Node`; tunables as
  `@export`; state as plain vars; behavior exposed as methods.
- **b. Owner → component access by unique name.** Each component node sets
  `unique_name_in_owner = true`; the owner holds `@onready var x := %ComponentName`.
  Never an owner-side `@export` for a fixed internal child.
- **c. Component → host by exported injection.** The component declares
  `@export var body: <Type>`, wired in the scene (Inspector drag produces
  `node_paths=PackedStringArray("body")` + `body = NodePath("..")`). Never `get_parent()`.
- **d. Owner orchestrates pipeline components; independent components self-drive.**
  Pipeline components (movement, jump, animation) expose `move(delta)` / `tick(delta)` and
  have NO `_physics_process`; the owner calls them in a deliberate order from its
  `_physics_process` and passes data between them. This keeps execution order explicit,
  keeps components ignorant of each other (no cross-component reach-through), and lets the
  host decide when to run them. Genuinely independent behaviors (off-screen despawn, timed
  VFX) may self-drive with their own `_process`.
- **e. Signals connect in the editor when possible.** When both emitter and receiver exist
  at edit time, connect in the `.tscn` (the connect dialog's "Deferred" checkbox provides
  `CONNECT_DEFERRED`). Reserve `connect()` in `_ready()` for runtime-instanced targets.

**Edits:**

- `docs/refactor-architecture.md`:
  - Component Rules: add item 6 (b + c, the two-direction access rule) and item 7 (d,
    orchestration vs self-drive).
  - Event Communication Rules: add item 6 (e, editor signal connections).
  - Dependency Rule #4 (host injection by export) stays; Component Rule 6 makes the `%`
    direction explicit alongside it.
- `CLAUDE.md` → "Composition over inheritance": add a one-line pointer to the architecture
  doc's Component Rules.

**Stale-doc fix:** `docs/refactor-phase-1-tasks.md:122` prescribes
`@export var movement: PortalMovementComponent` on `Player`, but the implemented
`player.gd:21` uses `@onready var portal_movement_component := %PortalMovementComponent`.
Update the task contract to describe the `%` accessor (matches Change 2b and the
`feedback-unique-name-accessor` memory).

---

## Memory

- Update `feedback-unique-name-accessor.md` to cover the full convention (2b–2e), not just
  the `%` accessor.
- Add `feedback-reference-policy.md` for Change 1 (don't default to prerefactor;
  richer-wins case-by-case; r-a-0 is the structural model).

---

## Out of scope

- `docs/specs/` and `docs/plans/` for completed Phase 1 work — left as historical records.
  The reweighting governs future specs, not done ones.
- No code changes. This is documentation/convention realignment only; `player.gd` and
  `portal_movement_component.gd` already follow the convention.
