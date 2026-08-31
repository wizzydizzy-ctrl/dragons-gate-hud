# Final Review Fix Report — Persistent Top-Center Chatbox

**Date:** 2026-08-31
**Worktree:** `.worktrees/chatbox-mapper`
**Branch:** `feature/chatbox-mapper`
**Reviewed head:** `152f03793c140c0557fa3fca0f5f537134ae1d01`
**Scope:** One integrated local fix pass for all four findings in `final-code-review.md`.

## Result

All four findings are fixed with regression coverage. No live Mudlet install, updater execution, personal-content mutation, push, tag, or publication was performed.

## Finding Evidence

### 1. Sanitized character transitions hydrate recent history

- `Main:refresh()` now synchronizes chat identity after the normalized state becomes current.
- `Controller:syncCharacter()` compares storage-owned sanitized keys, including `unknown` to a real character, and loads each key at most once per controller lifetime.
- `History:hydrate()` prepends chronological persisted history to current-session entries, removes exact overlap, rebuilds deterministic category order, and retains only its bounded newest entries.
- Hydration writes directly to the model and never calls the storage append pipeline.
- Regressions cover unavailable startup identity, `unknown` to `dace_alterac`, equivalent sanitized names (`Dace/Alterac` and `Dace Alterac`), ordering, overlap dedupe, and unchanged append count.

### 2. Direct capture calls fail safely during replacement failure/rollback

- `entry.lua` preserves an existing `DGHUD.chat` table when available, or creates one, immediately after old-runtime shutdown and before the first replacement `require`.
- Fail-safe `capture`, `setFilter`, and `status` methods return `nil,error` throughout a failed load/rollback window.
- `Main.installChatApi()` reuses that table and replaces the stubs only after module loading succeeds.
- Regressions evaluate the documented direct expression `DGHUD.chat.capture(...)` after a forced replacement `require` failure, with and without a prior wrapper table.

### 3. The effective visible limit cannot exceed 1,000

- `History.visibleLimit()` normalizes user values to `1..1000`; `Main:startChat()` passes that same effective value to storage and history.
- `Storage.new()` and `History.new()` independently enforce the hard maximum as defense in depth.
- Regressions verify an override of `1500` retains/loads exactly entries `502..1501`, controller status reports `1000`, render input starts at `line-2` for 1,001 loaded entries, and a lower override of `2` remains honored.

### 4. Wrapping uses live Mudlet MiniConsole metrics

- `View:applyChatWrap()` runs after MiniConsole resize and font application, reads the live character width through `MiniConsole:calcFontSize()` (with Mudlet global fallback), reads the live console width when available, subtracts the configured scrollbar allowance, and applies `floor(usableWidth/fontWidth)`.
- The previous deterministic layout estimate remains only as a compatibility fallback when no live metric API exists.
- Regressions use a real metric width different from the heuristic. At a 644 px live output width with an 18 px scrollbar allowance, widths `12`, `16`, and `10` produce wraps `52`, `39`, and `62`; omitting the allowance would produce the wrong first result (`53`).
- The same regression verifies the existing content-entry anchor while reading history and bottom pinning while tailing across metric-driven reflows.
- API compatibility was checked against official Mudlet 5.0.0 and current Geyser MiniConsole sources: both expose `calcFontSize()`, `get_width()`, manual `setWrap()`, and the same scrollbar-aware auto-wrap formula.

## Test-First Record

| Cycle | RED evidence | GREEN evidence |
|---|---|---|
| Character transition/hydration | 140 tests, 3 expected failures: missing `History:hydrate`, missing `Controller:syncCharacter`, no Main identity reload | 140 tests, 0 failures |
| Fail-safe direct wrapper | 142 tests, 2 expected failures: missing preserved/created direct API | 142 tests, 0 failures |
| Hard 1,000 cap | 145 tests, 3 expected failures: Main passed 1,500, history retained 1,500, storage loaded 1,500 | 145 tests, 0 failures |
| Live font metrics | 146 tests, 1 expected failure: metric callback was not used | 146 tests, 0 failures |

## Fresh Final Verification

- Baseline before edits: host Lua 5.5.1 — **137 tests, 0 failures**; Python build test — **1 passed**.
- `lua tests/run.lua` under host Lua 5.5.1 — **146 tests, 0 failures**.
- Official Lua 5.1.5 temporary `/tmp` build, `lua tests/run.lua` — **146 tests, 0 failures**.
- Host Lua 5.5.1 and temporary Lua 5.1.5 `luac -p src/*.lua tests/lua/*.lua tests/run.lua` — **passed**.
- `python3 -m unittest tests/test_build.py -v` — **1 test passed**.
- `python3 scripts/build.py` to `/tmp/dghud-package.hrInns` — **passed**.
- Package inspection — **one archive member**, version **0.2.36**, minimum Mudlet **5.0.0**, entry script and chat/layout/view/main/updater modules present.
- Package SHA-256 matched its generated manifest: `3bc54ef6e072c768e1d3a23fffd54f02d537f7ad64b36e941461f51c81dded0f`.
- `git diff --check` — **passed**.

The temporary Lua compiler emitted only warnings from upstream Lua 5.1.5 C source; repository tests and Lua syntax emitted no warnings or failures.

## Self-Review

- Scope is limited to the six affected production modules, six focused test files, and this report. Updater code, defaults, release metadata, personal runtime ownership, storage root/path validation, and append-only file behavior were not changed.
- Mutation check: removing refresh synchronization, using unsanitized identity comparison, or routing hydration through `accept()` breaks the transition/non-persistence regressions; removing the pre-require stub breaks both direct-call regressions; raising any effective limit breaks the history/storage/status regressions; using the heuristic or omitting scrollbar allowance breaks the live-metric regression.
- Full runtime/updater tests still cover owned-trigger cleanup, rollback behavior, unrelated alias/event/timer preservation, package identity, checksum rejection, and asynchronous update rollback.
- No additional product behavior, release step, or personal-content operation was introduced.

## Deferred by Instruction

Live disposable-profile installation and visual resize acceptance remain deferred. No install, updater run, push, tag, release, or publication occurred in this pass.
