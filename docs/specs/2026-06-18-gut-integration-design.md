# GUT Integration — Design

Approved 2026-06-18. Integrate GUT (Godot Unit Test, v9.6.0, already vendored at
`addons/gut/`) into the project as both tooling and a per-task process change.

**Motivation (the real one):** the camera/viewport work killed the earlier `refactor-attempt-0`
attempt. Root cause, on reflection, was **resolution/viewport coupling**, not the camera
itself: menus worked at one resolution and broke on window resize, buttons overflowed the
viewport, and camera behavior looked wrong. Two compounding failures made it unfixable:
(1) image-recognition-based debugging was unreliable, and (2) perceptual "it feels/looks
wrong" feedback was hard to specify. The game became unusable and had to be rolled back.

GUT alone would **not** have saved it. The design below aims at the actual failure modes,
with GUT as one of three legs.

---

## Principle 1 — Deterministic vs. perceptual split

Every visual subsystem (camera, viewport, UI) divides into two buckets:

- **Deterministic** — has a single correct, specifiable answer: viewport/SubViewport
  sizing from a window size, camera position math, clamping to world bounds, zoom from
  resolution, whether a `Control`'s rect fits inside the viewport. **GUT-asserted. Claude
  owns correctness here.** These convert "does it look right?" (a question answered by
  squinting at a screenshot) into a numeric assertion the engine answers.
- **Perceptual** — no test can pin the right value: camera smoothing speed, deadzone size,
  lookahead distance, easing feel. **Exposed as `@export` fields / a tunable `Resource` so
  the user dials them live in the editor while the game runs. The user owns the feel.**
  Claude does not guess-then-rerun on these.

This split is the backbone. It routes around both failure modes: deterministic correctness
stops going through Claude's eyes; perceptual tuning stops going through Claude's guesses.

## Principle 2 — Extract logic from nodes so it is assertable

A `Camera2D` / `SubViewport` is hard to unit-test; a plain function is trivial. Where a
deterministic computation lives inside a node, extract it into a plain `RefCounted` helper
or a `Resource` that takes inputs (player pos, world bounds, viewport size, zoom) and
returns outputs (camera pos, zoom value) with zero node/render dependency. The node becomes
a thin shell that calls the helper. This is in service of Principle 1's deterministic
bucket, not a goal in itself — only extract when it makes a real computation assertable.

## Principle 3 — Pragmatic TDD, not strict, not test-after

Test-first (RED-GREEN-REFACTOR, via the superpowers TDD skill) for the deterministic
bucket: pure logic, resources, `RefCounted` helpers, controller lifecycle (with doubles),
and scene-tree integration assertions. **Skip TDD for the perceptual bucket and for pure
scene wiring / physics feel / input** — those are validated by playtest, not unit tests.

The boundary is a written rule (below), not a per-task judgment call, so "where it fits"
never becomes an excuse to skip a test that belongs in the deterministic bucket.

---

## Mechanical setup

**Enable the plugin.** Add GUT to `project.godot` `[editor_plugins]` `enabled`. Commit the
vendored `addons/gut/` as-is (Godot has no lockfile-based package manager; vendoring is the
standard way to get a reproducible, AssetLib-free, drift-free version for clones and any
future CI).

**Test layout** — centralized `test/` mirroring the domain tree internally:

```
test/
├── unit/         # pure logic, resources, RefCounted helpers (deterministic, no scene tree)
│   ├── world/
│   └── characters/
└── integration/  # instantiate node/scene, advance a frame, assert runtime state
    └── world/
```

Rationale: the "organize by game domain, never by file type" rule targets engine-centric
folders (`scripts/`, `scenes/`). Test code is tooling, not a game domain — same category as
`addons/` and `docs/`, which are already non-domain top-level folders. A top-level `test/`
is consistent with that, and is excluded from game exports with a single `res://test/`
filter (co-locating `*_test.gd` next to source ships test code in the build unless filtered
file-by-file). The `unit/` vs `integration/` split maps onto Principle 1: pure-logic tests
in `unit/`, instantiate-and-assert tests in `integration/`.

**Config** — committed `res://.gutconfig.json` pins `dirs=["res://test/unit",
"res://test/integration"]`, `prefix="test_"`, `suffix=".gd"`, `include_subdirs=true`.

**Headless run command** (flags verified against `addons/gut/cli/gut_cli.gd` v9.6.0):

```
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
```

Exit code reflects pass/fail. This is the one copy-pasteable line for the per-task
verification step.

**Proof-of-concept integration test** — one test this session, NOT viewport-specific:
instantiate a trivial node (a 3-line throwaway script is fine), add it to the scene tree via
`add_child_autofree`, `await` a frame, and assert a runtime property (e.g. its
`global_position` after a set). Purpose: prove GUT 9.6 can do scene-tree instantiate +
frame-advance + runtime-property assertion **headless**, before the camera work bets on
that capability. If it can't, we find out now, not mid-camera-build.

---

## Process change — per-task cycle

The cycle stays brainstorming -> writing-plans -> implement. TDD is added inside *implement*:

- For deterministic-bucket work, write the failing GUT test first.
- The headless run command is the task's completion gate alongside the existing
  parse-check. A task touching deterministic logic is not done until its tests are green.
- Perceptual-bucket work ships tunables (`@export` / `Resource`), no test, validated by
  user playtest.

---

## Prescribed viewport/UI recipes (documented, NOT built this session)

The camera/viewport system is built in a later session (Task E and the deferred runtime
resolution settings). To stop that session from falling back to eyeballing under pressure,
`docs/testing-conventions.md` describes these recipes as named patterns now, in prose,
without implementing them:

- **Resolution sweep** — run an integration test across a list of window sizes (e.g.
  320x180, 1280x720, 1920x1080, and one deliberately non-16:9), asserting the same
  invariants at each. The harness is a parameterized GUT test fed the resolution list.
- **Control-fits-in-viewport** — after setting the viewport to size S and advancing a frame,
  assert every interactive `Control`'s `global_rect` lies within the viewport rect. This is
  the exact assertion that would have caught the overflowing-buttons bug, with no image
  recognition.
- **Viewport/zoom sizing** — assert the computed SubViewport size and camera zoom for a
  given window size match expected values (the deterministic core of resolution settings).

These are recipes, not code. The future task implements an agreed pattern instead of
inventing one.

---

## Documentation home

Follows the project's established shape (short rule in `CLAUDE.md` + pointer; depth in
`docs/`, as with `@docs/architecture-principles.md`):

- **`docs/testing-conventions.md`** (new) — authoritative policy: the deterministic-vs-
  perceptual split, extract-logic-from-nodes, pragmatic-TDD boundary, `test/` layout,
  naming, the headless run command, and the prescribed viewport/UI recipes above.
- **`CLAUDE.md`** — a short "Testing" section: the one-line boundary rule (deterministic =
  GUT-tested test-first; perceptual = tunable + playtest; scene wiring/physics =
  playtest), the run command, and a `@docs/testing-conventions.md` pointer.

---

## Memory

- Add a `project-` memory: GUT integrated; pragmatic TDD on the deterministic bucket;
  perceptual tuning via exported Resource/@export + playtest; test layout and run command;
  the r-a-0 viewport-coupling failure as the motivation.

---

## Out of scope

- Building the camera/viewport system, Main.tscn, or runtime resolution settings — those are
  their own later tasks. This session gives them the safety net and the recipes, not the
  implementation.
- The resolution-sweep / fits-in-viewport / zoom-sizing **test code** — documented as
  recipes only; written when the subsystem they test exists (avoids speculative test infra
  against scenes that do not yet exist).
- CI wiring — the headless command is defined; hooking it to a CI runner is deferred until a
  CI need exists.
- Retrofitting tests onto existing Phase 1 code (player, portal, level) — add tests when that
  code is next modified, per the "don't retrofit" convention.
