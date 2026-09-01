# Whole-Branch Review Fix Report

Branch: `feature/special-submaps-zoom`

Worktree: `/Users/ricwall/Documents/Codex/2026-08-31/cre/dragons-gate-hud/.worktrees/special-submaps-zoom`

Review findings fixed: 1, 2, 3, 4, 6, and 7.

Previously completed findings 5 and 8 from commit `8069685` were preserved. No merge, push, tag, release, live Mudlet edit, or subagent operation was performed.

## Corrections

1. Added `special_transition` to the package preload list and entry-time module eviction list. The Python package test now derives and checks the complete runtime dependency closure, loads the built preloads in an isolated Lua process, requires the real packaged `main`, and executes the packaged entry twice with generation sentinels to prove initial stale-cache eviction and reload.
2. Changed the map adapter to scan all existing special-exit destination buckets for the exact command before mutation. An exact command/destination tuple is idempotent; the same command assigned to any different destination is rejected before `addSpecialExit`. The map fake now models Mudlet's one-destination-per-command storage and exposes the production `getSpecialExits(..., true)` shape.
3. Required `dghud.owner=DragonsGateHUD` on both the canonical room and its area before reading or changing per-area zoom.
4. Preserved exact trimmed special-command case and bytes through candidate capture, automapper handoff, persistence, reload lookup, route validation, and walker sending. Lowercase copies are used only for direction and control classification. Non-direction route matching is exact and case-sensitive.
6. Defined replacement cancellation policy: a cancellation failure clears candidate ownership, returns a bounded error of at most 200 bytes, and aborts scheduling the replacement. Token identity keeps a stale callback inert, including after a later candidate is created. Runtime diagnostics receive the bounded error through `Main:callSpecialTransition`.
7. Enforced an effective zoom minimum of `max(configured_min, 3.0)` and reject any configured maximum below that effective minimum before zoom state is read or mutated.

## TDD Evidence

Each production correction was preceded by a regression test and an observed failure:

- Finding 1: `python3 -m unittest tests.test_build.BuildTest.test_build_emits_verified_owned_package -v` failed because the package was missing `special_transition`; it passed after both module lists were fixed.
- Finding 2: the Lua suite failed `never replaces a different-destination special exit with the same command` (`expected nil, got true`); after the collision scan, 292 tests passed.
- Finding 3: the Lua suite failed `zoom refuses an unowned area even when the room is HUD owned` (`expected nil, got 20`); after area authorization, 293 tests passed.
- Finding 7: the Lua suite failed both absolute-bound tests (`expected 3, got 1.5`; `expected nil, got 2.5`); after effective-bound validation, 295 tests passed.
- Finding 4: the Lua suite failed at candidate capture, adapter persistence, automapper handoff, exact route validation, and reload acceptance; after preserving exact trimmed commands end to end, 296 tests passed.
- Finding 6: the Lua suite failed both unit and runtime replacement-cancellation tests (`expected nil, got true` and a retained candidate); after the bounded abort policy and stale-token guard were enforced, 298 tests passed.

## Final Verification Evidence

- Focused Lua suites (`special_transition`, `map_adapter`, `automapper`, `map_walker`, `runtime`, and mapper acceptance): **140 tests, 0 failures**.
- Full Lua suite: **298 tests, 0 failures**.
- Full Python suite: **1 test, OK**.
- Lua syntax: **47 files passed `luac -p`**.
- Python syntax: **2 changed Python files compiled successfully in memory**.
- Release package build: **version 0.2.53**, **38,334 bytes**.
- Package contents: `special_transition` preload present; isolated preload/`main` load and entry reload are exercised by the Python suite.
- Manifest/package SHA-256 match: `d1a06a9832abd42accb0b6f32cdf44e6e0289e02558e71f46d550414984fe65f`.
- `git diff --check`: **PASS**.

The first ad-hoc checksum inspection wrapper contained an f-string quoting syntax error after the build step. It was corrected and the complete build/checksum/content command was rerun successfully; the successful evidence above comes from that fresh rerun.

## Finding 9 Follow-Up

Finding 9 from `whole-branch-rereview.md` was fixed by making outbound transition ownership uniform in `Automapper:onOutgoing`: a valid direction replaces directional pending state, while every non-direction command clears any prior directional pending state before `SpecialTransition` classifies or owns the command. The later successful `onSpecialTransition` handoff remains responsible for installing arbitrary-special pending state. The obsolete portal/door/gate/arch-only clearing table was removed.

Four integrated runtime regressions exercise observable persisted graph behavior through `Main`, `Automapper`, `SpecialTransition`, and the map adapter boundary:

1. `north` → `climb rope` → candidate expiry → room `900` creates no directional or special edge.
2. `north` → `climb rope` → timer creation failure → room `900` creates no directional or special edge.
3. `north` → excluded `look` → room `900` creates no directional or special edge.
4. `north` → `Climb RuneRope` → room `900` creates only the exact observed `100 --Climb RuneRope--> 900` special edge and no directional edge.

### Finding 9 TDD Evidence

Before the production change, the focused runtime suite reported **52 tests, 3 failures**. The expiry, scheduler-failure, and excluded-control regressions each failed with `expected 0, got 1` for persisted directional links. The successful arbitrary-special regression already passed, protecting the behavior that must remain intact. After the minimal non-direction clearing change and dead-code refactor, the runtime-focused suite reported **52 tests, 0 failures**.

### Finding 9 Final Verification

- Focused automapper/runtime suites: **72 tests, 0 failures**.
- Full Lua suite: **302 tests, 0 failures**.
- Full Python suite: **1 test, OK**.
- Lua syntax: **47 files passed `luac -p`**.
- Python syntax: **2 Python files compiled successfully in memory**.
- Release package build: **version 0.2.53**, **38,263 bytes**.
- Package contents: `special_transition` preload present.
- Manifest/package SHA-256 match: `ec448b97ad6d5c46028e4d952f6c311d4911fe0e809ba9d0439e762742055946`.
- `git diff --check`: **PASS**.
