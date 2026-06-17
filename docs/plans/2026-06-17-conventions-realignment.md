# Conventions Realignment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps
> use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the two guidance changes from `docs/specs/2026-06-17-conventions-realignment-design.md`
(reference policy + component-wiring convention) across the project's docs and memory.

**Architecture:** Documentation/convention realignment only — no code changes. The
architecture doc is the canonical home for the component-wiring convention; other docs carry
reweighted lines or short pointers (Approach A). Exact replacement wording lives in the spec;
each task points to the relevant spec section rather than duplicating it.

**Tech Stack:** Markdown. No build, no tests. Verification = grep/read-back of the edited
anchors. The `godot --import` parse-check does NOT apply (no `.gd` files change).

**Spec:** `docs/specs/2026-06-17-conventions-realignment-design.md` (source of all wording).

---

### Task 1: CLAUDE.md — branch structure, reference policy, composition pointer

**Files:**
- Modify: `CLAUDE.md` ("## Branch structure" section; "### Composition over inheritance" list)

- [ ] **Step 1: Rewrite "Branch structure"**
  Replace the existing `## Branch structure` block (the three branch bullets +
  the "When refactoring a system always read the original..." paragraph) with the new
  branch list and `### Reference policy` subsection from spec **Change 1 → Edits → CLAUDE.md**.
  Drop the stale "clean slate: only docs/, addons/, project.godot exist" line.

- [ ] **Step 2: Add component-wiring pointer**
  Under `### Composition over inheritance`, append the one-line pointer from spec
  **Change 2 → Edits → CLAUDE.md** (points to `@docs/refactor-architecture.md` Component Rules).

- [ ] **Step 3: Verify**
  Run: `rg -n "Reference policy|Component wiring \(access" CLAUDE.md`
  Expected: both lines present; no remaining "source of truth for behavior" / "clean slate" text
  (`rg -n "clean slate|source of truth" CLAUDE.md` → no output).

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Reweight reference policy; add component-wiring pointer (CLAUDE.md)"
```

---

### Task 2: refactor-architecture.md — codify the component-wiring convention

**Files:**
- Modify: `docs/refactor-architecture.md` ("## Component Rules", "## Event Communication Rules")

- [ ] **Step 1: Add Component Rules 6 and 7**
  After the existing Component Rule **5** ("Don't extract a component to reduce line count"),
  add items **6** and **7** verbatim from spec **Change 2 → Edits → refactor-architecture.md**.

- [ ] **Step 2: Add Event Communication Rule 6**
  After the existing Event Communication Rule **5** (`EventBus`...), add item **6**
  ("Prefer editor (.tscn) signal connections...") verbatim from the same spec section.

- [ ] **Step 3: Verify**
  Run: `rg -n "unique_name_in_owner|orchestrates pipeline|editor \(.tscn\) signal" docs/refactor-architecture.md`
  Expected: all three anchors present. Confirm Dependency Rule #4 is untouched
  (`rg -n "Components receive their host" docs/refactor-architecture.md` → still present).

- [ ] **Step 4: Commit**

```bash
git add docs/refactor-architecture.md
git commit -m "Codify component-wiring convention (access, host injection, orchestration, signals)"
```

---

### Task 3: refactor-roadmap.md — reweight the reference line

**Files:**
- Modify: `docs/refactor-roadmap.md:21-22` (the "Source of truth for behavior / Reference for
  what was tried" lines, under "## Context")

- [ ] **Step 1: Replace the two reference lines**
  Replace lines 21-22 with the structure-vs-behavior block from spec
  **Change 1 → Edits → refactor-roadmap.md** (ends with "See CLAUDE.md 'Reference policy'.").

- [ ] **Step 2: Verify**
  Run: `rg -n "Structure/patterns reference|Reference policy" docs/refactor-roadmap.md`
  Expected: present. `rg -n "Source of truth for behavior" docs/refactor-roadmap.md` → no output.

- [ ] **Step 3: Commit**

```bash
git add docs/refactor-roadmap.md
git commit -m "Reweight reference policy line (roadmap)"
```

---

### Task 4: refactor-phase-1-tasks.md — reweight contracts + fix stale @export

**Files:**
- Modify: `docs/refactor-phase-1-tasks.md` (global "**Contracts:**" block ~lines 13-16;
  Task C Player interface ~line 122)

- [ ] **Step 1: Reweight the global Contracts block**
  In the `**Contracts:**` paragraph, replace the "Behavior source of truth: prerefactor /
  Reuse reference (ask first): r-a-0" sentences with a pointer to CLAUDE.md "Reference policy"
  per spec **Change 1 → Edits → refactor-phase-1-tasks.md**. Leave the per-task
  "Behavior source: prerefactor X" lines unchanged.

- [ ] **Step 2: Fix the stale @export on the Player interface**
  In Task C's Player bullet, replace `@export var movement: PortalMovementComponent` with the
  `%`-accessor wording from spec **Change 2 → Stale-doc fix**
  ("accesses its `PortalMovementComponent` via `%` unique name (not an owner-side export)").

- [ ] **Step 3: Verify**
  Run: `rg -n "@export var movement" docs/refactor-phase-1-tasks.md`
  Expected: no output. `rg -n "% unique name" docs/refactor-phase-1-tasks.md` → present.

- [ ] **Step 4: Commit**

```bash
git add docs/refactor-phase-1-tasks.md
git commit -m "Reweight contracts; fix stale @export movement -> % accessor (phase-1-tasks)"
```

---

### Task 5: Memory — update accessor note, add reference-policy note, update index

**Files:**
- Modify: `/home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/feedback-unique-name-accessor.md`
- Create: `/home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/feedback-reference-policy.md`
- Modify: `/home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/MEMORY.md`

- [ ] **Step 1: Read the existing accessor memory**
  Read `feedback-unique-name-accessor.md` to preserve its frontmatter `name`/`type`.

- [ ] **Step 2: Expand the accessor memory**
  Rewrite its body to cover the full convention (spec Change 2 a–e): `%` access (owner→component),
  `@export` host injection (component→host), owner-orchestration vs self-drive, editor signal
  connections. Link `[[feedback-reference-policy]]`. Keep one fact = one file: this file owns
  "component-wiring convention".

- [ ] **Step 3: Create the reference-policy memory**
  Write `feedback-reference-policy.md` (type: feedback) capturing spec Change 1: neither branch
  is the default behavior canon; per feature compare both and start from the richer/better-built
  one (often r-a-0), surface the diff, don't default to prerefactor; r-a-0 is the structural model.
  Include **Why:** and **How to apply:** lines. Link `[[feedback-unique-name-accessor]]`.

- [ ] **Step 4: Update MEMORY.md index**
  Edit the accessor line to reflect the broadened scope, and add a new one-line pointer for
  `feedback-reference-policy.md`.

- [ ] **Step 5: Verify**
  Run: `ls /home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/feedback-reference-policy.md`
  Expected: file exists. Confirm MEMORY.md has both pointers
  (`rg -n "reference-policy|unique-name-accessor" /home/migu/.claude/projects/-home-migu-repos-GitHub-mortalportal/memory/MEMORY.md`).

- [ ] **Step 6: (no commit)**
  Memory files live outside the repo (`~/.claude/...`); nothing to commit here.

---

### Task 6: Final verification

- [ ] **Step 1: Confirm working tree is clean and commits landed**
  Run: `git -C /home/migu/repos/GitHub/mortalportal status` (clean) and
  `git -C /home/migu/repos/GitHub/mortalportal log --oneline -5` (Tasks 1–4 commits present).

- [ ] **Step 2: Cross-doc consistency sweep**
  Run: `rg -n "source of truth for behavior|@export var movement|clean slate" CLAUDE.md docs/`
  Expected: no output (all stale phrasings removed; spec file may legitimately mention
  "@export var movement" when describing the fix — exclude it: add `-g '!docs/specs/2026-06-17-*'`).

---

## Self-Review

**Spec coverage:** Change 1 → Tasks 1, 3, 4. Change 2 → Tasks 1 (pointer), 2 (canonical text),
4 (stale fix). Memory → Task 5. Out-of-scope items (completed specs/plans, code) correctly
untouched. No gaps.

**Placeholder scan:** No TBD/TODO. Each task names exact files + anchors; verbatim wording is
in the committed spec (single source, intentionally not duplicated per the project's slim-plan
convention).

**Type consistency:** N/A (no code). Doc anchor names match the spec section headers exactly
("Change 1 → Edits → ...").
