# GUT Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate GUT (Godot Unit Test v9.6.0, vendored at `addons/gut/`) as committed
tooling and a per-task TDD process, proving headless scene-tree assertion works before the
camera/viewport work depends on it.

**Architecture:** Enable + commit the vendored addon; add a centralized `test/` tree
(`unit/` + `integration/`) excluded from exports; pin a `.gutconfig.json` so one headless
command runs the suite; prove the instantiate-frame-advance-assert capability with one
integration test; write the authoritative policy to `docs/testing-conventions.md` with a
short rule + pointer in `CLAUDE.md`. No camera/viewport code is built here — only the safety
net and documented recipes.

**Tech Stack:** Godot 4.6, GDScript, GUT 9.6.0. Test base class `GutTest`. Headless runner
`addons/gut/gut_cmdln.gd`.

**Spec:** `docs/specs/2026-06-18-gut-integration-design.md` (source of all rationale).

**Verified API facts** (from reading `addons/gut/` this session):
- Test scripts `extends GutTest` (global class_name in `addons/gut/test.gd:1`).
- `add_child_autofree(node)` adds to the runner tree and auto-frees after the test.
- `await wait_physics_frames(n)` advances `n` physics frames (`wait_frames` is deprecated).
- `assert_eq(got, expected, text="")`, `assert_almost_eq(got, expected, error_interval, text="")`.
- Test methods are functions prefixed `test_`; test files prefixed `test_`.
- CLI flags (`addons/gut/cli/gut_cli.gd`): `-gconfig`, `-gdir`, `-ginclude_subdirs`, `-gexit`.
- `.gutconfig` keys present in `addons/gut/gut_config.gd`: `dirs`, `include_subdirs`,
  `prefix`, `suffix`.

---

### Task 1: Enable the GUT plugin and commit the vendored addon

**Files:**
- Modify: `project.godot` (add `[editor_plugins]` section)
- Add (track): `addons/gut/` (currently untracked)

- [ ] **Step 1: Add the `[editor_plugins]` section to `project.godot`**

Insert this block immediately after the existing `[editor]` section (after the
`version_control/autoload_on_startup=true` line, before `[input]`):

```ini
[editor_plugins]

enabled=PackedStringArray("res://addons/gut/plugin.cfg")
```

- [ ] **Step 2: Verify the project still imports cleanly**

Run:
```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error|error" || echo "CLEAN"
```
Expected: `CLEAN` (no script/parse errors from enabling the plugin).

- [ ] **Step 3: Confirm the plugin line is present**

Run:
```bash
rg -n 'addons/gut/plugin.cfg' /home/migu/repos/GitHub/mortalportal/project.godot
```
Expected: one match in the `enabled=` line.

- [ ] **Step 4: Commit the addon and the enable**

```bash
cd /home/migu/repos/GitHub/mortalportal
git add addons/gut/ project.godot
git commit -m "$(cat <<'EOF'
Vendor and enable GUT 9.6.0 addon

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Create the test tree and pin the headless runner config

**Files:**
- Create: `test/unit/.gitkeep`
- Create: `test/integration/.gitkeep`
- Create: `.gutconfig.json`

- [ ] **Step 1: Create the directory tree with tracked keep-files**

```bash
cd /home/migu/repos/GitHub/mortalportal
mkdir -p test/unit test/integration
touch test/unit/.gitkeep test/integration/.gitkeep
```

- [ ] **Step 2: Create `.gutconfig.json`**

Write `/home/migu/repos/GitHub/mortalportal/.gutconfig.json`:

```json
{
    "dirs": ["res://test/unit", "res://test/integration"],
    "include_subdirs": true,
    "prefix": "test_",
    "suffix": ".gd"
}
```

- [ ] **Step 3: Run the headless runner against the (empty) suite**

Run:
```bash
cd /home/migu/repos/GitHub/mortalportal
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit; echo "EXIT=$?"
```
Expected: GUT banner prints, reports 0 tests run (no scripts found), `EXIT=0`. This proves
the config + runner are wired before any test exists.

- [ ] **Step 4: Commit**

```bash
cd /home/migu/repos/GitHub/mortalportal
git add test/ .gutconfig.json
git commit -m "$(cat <<'EOF'
Add test/ tree and GUT runner config

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Proof-of-concept integration test (instantiate + frame-advance + assert)

This is the capability spike from the spec: prove GUT can instantiate a node in the scene
tree, advance a physics frame, and assert a runtime-set property — headless. The throwaway
node sets its position in `_physics_process`, so the assertion only holds *after* a frame
advance, forcing the capability to be exercised.

**Files:**
- Create: `test/integration/_poc_node.gd` (fixture; `_`-prefixed so GUT does not collect it as a test)
- Test: `test/integration/test_gut_capability.gd`

- [ ] **Step 1: Write the failing test**

Write `/home/migu/repos/GitHub/mortalportal/test/integration/test_gut_capability.gd`:

```gdscript
extends GutTest

const PocNode := preload("res://test/integration/_poc_node.gd")

func test_node_sets_position_after_one_physics_frame() -> void:
	var node: Node2D = PocNode.new()
	add_child_autofree(node)
	await wait_physics_frames(1)
	assert_eq(node.global_position, Vector2(10.0, 20.0))
```

- [ ] **Step 2: Run the test to verify it fails (RED)**

Run:
```bash
cd /home/migu/repos/GitHub/mortalportal
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit; echo "EXIT=$?"
```
Expected: the test script fails to load (`_poc_node.gd` does not exist yet) — GUT reports a
failing/erroring script, `EXIT=1`.

- [ ] **Step 3: Create the minimal fixture node (GREEN impl)**

Write `/home/migu/repos/GitHub/mortalportal/test/integration/_poc_node.gd`:

```gdscript
extends Node2D

func _physics_process(_delta: float) -> void:
	global_position = Vector2(10.0, 20.0)
```

- [ ] **Step 4: Run the test to verify it passes (GREEN)**

Run:
```bash
cd /home/migu/repos/GitHub/mortalportal
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit; echo "EXIT=$?"
```
Expected: `1 passing`, `EXIT=0`. This confirms instantiate + frame-advance + runtime-property
assertion works headless. If this fails, STOP — the spec's whole "assert instead of eyeball"
premise needs revisiting before proceeding.

- [ ] **Step 5: Commit**

```bash
cd /home/migu/repos/GitHub/mortalportal
git add test/integration/_poc_node.gd test/integration/test_gut_capability.gd
git commit -m "$(cat <<'EOF'
Prove headless scene-tree assertion via GUT capability test

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Write the authoritative testing policy doc

`docs/testing-conventions.md` is the canonical home (CLAUDE.md will point to it). Its content
expands the spec into reader-facing policy.

**Files:**
- Create: `docs/testing-conventions.md`

- [ ] **Step 1: Write `docs/testing-conventions.md`**

Write `/home/migu/repos/GitHub/mortalportal/docs/testing-conventions.md`:

````markdown
# Testing Conventions

Tooling: GUT (Godot Unit Test) v9.6.0, vendored at `addons/gut/`. Rationale and history:
`docs/specs/2026-06-18-gut-integration-design.md`.

## Run the suite

```bash
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit
```

Exit code 0 = all green, 1 = failures. This is the completion gate for any task that touches
deterministic logic (below), run alongside the usual `--import` parse-check.

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
````

- [ ] **Step 2: Verify the doc has the key anchors**

Run:
```bash
rg -n "deterministic vs. perceptual|Pragmatic TDD|Resolution sweep|Control-fits-in-viewport" /home/migu/repos/GitHub/mortalportal/docs/testing-conventions.md
```
Expected: all four headings/anchors present.

- [ ] **Step 3: Commit**

```bash
cd /home/migu/repos/GitHub/mortalportal
git add docs/testing-conventions.md
git commit -m "$(cat <<'EOF'
Document testing conventions (split, pragmatic TDD, layout, recipes)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Add the short Testing rule + pointer to CLAUDE.md

**Files:**
- Modify: `CLAUDE.md` (add a `## Testing` section under "Quick rule reference")

- [ ] **Step 1: Add the Testing section**

In `/home/migu/repos/GitHub/mortalportal/CLAUDE.md`, under the "# Quick rule reference"
heading (alongside "## Folder Structure", "## Architectural Rules", etc.), add:

```markdown
## Testing

GUT (`addons/gut/`). Full policy: `@docs/testing-conventions.md`.

- **Deterministic** behavior (sizing math, position/clamp/zoom, "does this `Control` fit the
  viewport") is **test-first with GUT** — Claude owns correctness. Run the suite as the
  completion gate:
  `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
- **Perceptual** behavior (camera feel: smoothing, deadzone, lookahead) is **not tested** —
  expose it as `@export` / a tunable `Resource` and let the user dial it in the editor.
- Scene wiring, physics, and input are validated by **playtest**, not unit tests.
- Tests live in `test/unit/` and `test/integration/`, mirroring domain folders.
```

- [ ] **Step 2: Verify**

Run:
```bash
rg -n "^## Testing|gut_cmdln.gd|@docs/testing-conventions.md" /home/migu/repos/GitHub/mortalportal/CLAUDE.md
```
Expected: the heading, run command, and pointer all present.

- [ ] **Step 3: Commit**

```bash
cd /home/migu/repos/GitHub/mortalportal
git add CLAUDE.md
git commit -m "$(cat <<'EOF'
Add Testing rule + testing-conventions pointer to CLAUDE.md

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Memory — record the integration, reconcile the plan-style memory

Memory files live under `~/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/`
and are outside the repo (no git commit).

**Files:**
- Create: `.../memory/project-testing-gut.md`
- Modify: `.../memory/feedback-per-task-session-workflow.md`
- Modify: `.../memory/MEMORY.md`

- [ ] **Step 1: Create the GUT project memory**

Write `.../memory/project-testing-gut.md`:

```markdown
---
name: project-testing-gut
description: GUT testing is integrated; pragmatic TDD on the deterministic bucket, tunables + playtest for perceptual
metadata:
  type: project
---

GUT 9.6.0 is vendored at `addons/gut/` and integrated as of 2026-06-18. Policy lives in
`docs/testing-conventions.md`; short rule in CLAUDE.md "## Testing".

- **Deterministic** behavior (viewport/sizing math, camera position/clamp/zoom, Control-fits-
  in-viewport) is **test-first with GUT**. Tests in `test/unit/` + `test/integration/`,
  mirroring domains. Run:
  `godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit`
- **Perceptual** behavior (camera smoothing/deadzone/lookahead feel) is **not tested** —
  exposed as `@export` / tunable `Resource`, dialed live by the user in-editor.
- Scene wiring / physics / input → playtest.

**Why:** the earlier r-a-0 attempt died on viewport/resolution coupling (menus broke on
resize, buttons overflowed the viewport) made unfixable by unreliable image-recognition
debugging and hard-to-specify perceptual feedback. GUT routes deterministic correctness
through engine assertions instead of screenshots; tunables route feel through the user
instead of Claude's guesses. See [[project-resolution-settings]].
```

- [ ] **Step 2: Reconcile the per-task-workflow memory**

Read `.../memory/feedback-per-task-session-workflow.md`. Remove the claim that plans are
"slim task contracts, no inlined code" — the user explicitly wants the standard
`writing-plans` skill behavior (complete inlined code, bite-sized TDD steps, frequent
commits). Keep the accurate parts: one sub-system task per session, cycle is
brainstorming -> writing-plans -> implement. Preserve the file's frontmatter `name`/`type`.

- [ ] **Step 3: Update MEMORY.md index**

In `.../memory/MEMORY.md`, add a pointer line:
```markdown
- [GUT testing integrated](project-testing-gut.md) — pragmatic TDD on deterministic logic; tunables + playtest for perceptual feel
```
And edit the existing `feedback-per-task-session-workflow` line to drop the "slim task
contracts, no inlined code" hook, e.g.:
```markdown
- [Per-task session workflow](feedback-per-task-session-workflow.md) — one sub-system task per session via brainstorming -> writing-plans -> implement (standard writing-plans: full inlined code)
```

- [ ] **Step 4: Verify**

Run:
```bash
ls /home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/project-testing-gut.md
rg -n "no inlined code|slim task contracts" /home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/
```
Expected: the file exists; the second command returns no output (the stale phrasing is gone
from both the memory body and the index).

---

### Task 7: Final verification

- [ ] **Step 1: Full suite green**

Run:
```bash
cd /home/migu/repos/GitHub/mortalportal
godot --headless -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json -gexit; echo "EXIT=$?"
```
Expected: `1 passing`, `0 failing`, `EXIT=0`.

- [ ] **Step 2: Parse-check still clean**

Run:
```bash
godot --headless --path /home/migu/repos/GitHub/mortalportal --import 2>&1 | rg -i "SCRIPT ERROR|Parse Error" || echo "CLEAN"
```
Expected: `CLEAN`.

- [ ] **Step 3: Working tree state**

Run:
```bash
cd /home/migu/repos/GitHub/mortalportal
git status --short
git log --oneline -6
```
Expected: Tasks 1-5 commits present (5 commits); the only dirty files are the pre-existing
`characters/player/player.gd` and `characters/player/player.tscn` (untouched by this plan).

---

## Self-Review

**Spec coverage:**
- Mechanical setup (enable + vendor) → Task 1.
- Test layout + `.gutconfig.json` + run command → Task 2.
- Proof-of-concept integration test → Task 3.
- Principles 1-3 + layout + recipes (authoritative doc) → Task 4.
- CLAUDE.md short rule + pointer → Task 5.
- Memory (project note) → Task 6; plus reconciling the plan-style memory the user corrected.
- Final verification → Task 7.
- Out-of-scope items (camera/viewport build, recipe test code, CI, retrofitting existing
  code) correctly absent.

**Placeholder scan:** No TBD/TODO. Every code/content step inlines the actual file content.
Commands have exact expected output.

**Type/name consistency:** `GutTest`, `add_child_autofree`, `wait_physics_frames`,
`assert_eq` match the verified API. `.gutconfig.json` keys (`dirs`, `include_subdirs`,
`prefix`, `suffix`) match `gut_config.gd`. The run command, config path, and `test/` dirs are
identical across Tasks 2-7 and both docs. Fixture `_poc_node.gd` is `_`-prefixed so the
`test_` collector ignores it, consistent with the doc's fixture rule.
