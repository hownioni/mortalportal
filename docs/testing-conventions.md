# Testing Conventions

Tooling: GUT (Godot Unit Test) v9.6.0, vendored at `addons/gut/`. Rationale and history:
`docs/specs/2026-06-18-gut-integration-design.md`.

## Run the suite

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
```

Exit code 0 = all green, 1 = a test ran and failed. This is the completion gate for any task
that touches deterministic logic (below), run alongside the usual `--import` parse-check. Note
the gate needs both: a test file that fails to *parse* makes GUT report "Nothing was run" with
exit 0, so the `--import` parse-check is what catches a malformed test file.

## The deterministic vs. perceptual split

Every visual subsystem (camera, viewport, UI) divides into two buckets. The bucket decides
who owns correctness and whether a test applies.

- **Deterministic** — one correct, specifiable answer: viewport/SubViewport sizing from a
  window size, camera position math, clamping to world bounds, zoom from resolution, whether
  a `Control`'s rect fits inside the viewport. **Test-first with GUT. Claude owns
  correctness.** A test converts "does it look right?" into a numeric assertion the engine
  answers — no screenshot interpretation.
- **Perceptual** — no test can pick the right value: camera smoothing speed, deadzone size,
  lookahead distance, easing feel. **Exposed as `@export` fields / a tunable `Resource` so
  the user dials them live in the editor. The user owns the feel.** Do not guess-then-rerun
  these.

Pure scene wiring, physics feel, and input are validated by playtest, not unit tests.

## Pragmatic TDD

Test-first (RED-GREEN-REFACTOR) for the deterministic bucket: pure logic, `Resource`s,
`RefCounted` helpers, controller lifecycle (with doubles), and scene-tree integration
assertions. Skip TDD for the perceptual bucket and for scene/physics/input. "Where it fits"
means "is it in the deterministic bucket" — not a per-task mood.

## Extract logic from nodes so it is assertable

A `Camera2D`/`SubViewport` is hard to test; a plain function is trivial. When a deterministic
computation lives in a node, extract it into a `RefCounted` helper or a `Resource` that takes
inputs (player pos, world bounds, viewport size, zoom) and returns outputs (camera pos, zoom)
with zero node/render dependency. The node becomes a thin shell calling the helper. Only do
this when it makes a real computation assertable — not to shrink files.

## Layout

```
test/
├── unit/         # deterministic logic, no scene tree (pure functions, Resources, RefCounted)
│   └── <domain>/ # mirrors the game's domain folders
└── integration/  # instantiate node/scene, advance a frame, assert runtime state
    └── <domain>/
```

Test files and methods are prefixed `test_`. Fixtures that are not tests use a `_` prefix so
GUT does not collect them (see `test/integration/_poc_node.gd`). `test/` is tooling, not a
game domain — exclude it from game exports with a single `res://test/` filter.

## Writing a test

```gdscript
extends GutTest

func test_<behavior>() -> void:
	var node := SomeNode.new()
	add_child_autofree(node)        # adds to the runner tree, auto-frees after
	await wait_physics_frames(1)    # advance frames when behavior runs in _physics_process
	assert_eq(node.some_value, expected)
```

Key helpers: `add_child_autofree(node)`, `await wait_physics_frames(n)`, `assert_eq`,
`assert_almost_eq(got, expected, error_interval)` for floats, `assert_true`,
`assert_not_null`.

## Prescribed viewport/UI recipes (not yet built)

These named patterns exist so the camera/viewport task implements an agreed approach instead
of inventing one. They are recipes, not code — write them when the subsystem they test
exists.

- **Resolution sweep** — a parameterized integration test fed a list of window sizes (e.g.
  320x180, 1280x720, 1920x1080, and one deliberately non-16:9), asserting the same
  invariants at each size.
- **Control-fits-in-viewport** — after setting the viewport to size S and advancing a frame,
  assert every interactive `Control`'s `global_rect` lies within the viewport rect. This is
  the assertion that catches overflowing buttons, with no image recognition.
- **Viewport/zoom sizing** — assert the computed SubViewport size and camera zoom for a given
  window size match expected values (the deterministic core of runtime resolution settings).
