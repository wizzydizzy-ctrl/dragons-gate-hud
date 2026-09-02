# Responsive List High-DPI Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep all Skills columns visible and the console gutters subtle across normal and high-DPI Mudlet displays.

**Architecture:** Replace the list-width character heuristic with a width derived from Mudlet's rendered fixed-width font measurement, while retaining a conservative fallback when measurement is unavailable. Cap the requested half-percent console gutter at a small logical-pixel maximum so high-resolution windows do not create oversized dead space.

**Tech Stack:** Lua, Mudlet/Geyser, repository Lua test harness.

**Spec:** User screenshot and request dated 2026-09-02 in this task.

## Global Constraints

- Preserve five visible, vertically scrollable Skills and Inventory rows.
- Preserve the `SKILLS`, `LVL`, and `USES` columns and their alignment.
- Do not modify user-created Mudlet triggers, aliases, scripts, maps, or packages.
- Keep existing normal-resolution behavior unless required to prevent clipping.
- Use test-first development and verify the complete Lua suite.

---

### Task 1: High-DPI list width calculation

**Files:**
- Modify: `tests/lua/test_view.lua`
- Modify: `src/view.lua`

**Interfaces:**
- Consumes: `list_measure:getSizeHint()`, `layout.list_font`, and the numeric Skills viewport width.
- Produces: a measured character width and a `skill_name_width` whose full header and every row fit before the scrollbar.

- [ ] **Step 1: Write failing tests** simulating fixed-width glyph metrics wider than `font * 0.62`, including scrollbar allowances representative of scaled Windows displays. Assert the complete header and rows fit the available pixel width and retain aligned numeric columns.
- [ ] **Step 2: Run `lua tests/run.lua` and verify the new test fails because the existing heuristic overestimates capacity.**
- [ ] **Step 3: Implement the minimum production change** to measure a representative fixed-width glyph run through `getSizeHint()`, derive per-character width, reserve conservative scrollbar space, and fall back safely when measurement is unavailable.
- [ ] **Step 4: Run `lua tests/run.lua` and verify all tests pass.**
- [ ] **Step 5: Commit the tested list-width fix.**

### Task 2: Resolution-safe console gutter

**Files:**
- Modify: `tests/lua/test_layout.lua`
- Modify: `src/layout.lua`

**Interfaces:**
- Consumes: logical Mudlet window width.
- Produces: `layout.console_gutter` equal to approximately 0.5% at ordinary sizes but capped at 12 logical pixels.

- [ ] **Step 1: Write failing tests** for 1920, 2560, 3840, and larger widths asserting the gutter never exceeds 12 logical pixels and the center console geometry remains internally consistent.
- [ ] **Step 2: Run `lua tests/run.lua` and verify the high-resolution case fails with the uncapped gutter.**
- [ ] **Step 3: Implement the minimum cap** in the shared layout metric calculation.
- [ ] **Step 4: Run `lua tests/run.lua` and verify all tests pass.**
- [ ] **Step 5: Commit the tested gutter fix.**

### Task 3: Release verification and documentation

**Files:**
- Modify only if required: `README.md`, `docs/MUDLET_ACCEPTANCE.md`, version fixtures.

**Interfaces:**
- Consumes: Tasks 1 and 2.
- Produces: a reviewed, buildable package candidate with explicit high-DPI acceptance coverage.

- [ ] **Step 1: Add or update acceptance instructions** for a scaled Windows display and a narrow window, if existing acceptance text does not cover them.
- [ ] **Step 2: Run `lua tests/run.lua`, `python3 tests/test_build.py`, `git diff --check`, and `python3 scripts/build.py`.**
- [ ] **Step 3: Independently review the full branch for correctness, scope, and user-content isolation.**
- [ ] **Step 4: Apply only review-required fixes with covering tests, then rerun complete verification.**
- [ ] **Step 5: Commit the release candidate changes.**
