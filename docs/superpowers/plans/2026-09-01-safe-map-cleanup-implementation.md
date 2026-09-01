# Safe Map Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add previewed, expiring, ownership-safe commands that delete one DragonsGateHUD room, one special submap, or one HUD mapper area without mutating personal Mudlet map content.

**Architecture:** `map_adapter.lua` owns persisted ownership and mapper-mutation primitives. A new `map_cleanup.lua` module builds immutable plans, manages one-use confirmation tokens, revalidates state, and executes deterministic room-first cleanup. `main.lua` owns runtime hazards and aliases, while `mudlet_adapter.lua` supplies time, token entropy, and refresh boundaries.

**Tech Stack:** Lua 5.1, Mudlet 5.0 mapper APIs, GMCP, existing Lua TAP-style tests, Python package builder, GitHub Actions releases.

**Spec:** `docs/superpowers/specs/2026-09-01-safe-map-cleanup-design.md`

## Global Constraints

- Persisted `dghud.owner == "DragonsGateHUD"` is the sole ownership authority.
- Never delete or mutate an unowned room, area, ordinary exit, special exit, name, coordinate, label, or metadata value.
- Never delete the physical current room or any room intersecting active/pending movement.
- Never delete an area before its rooms; delete an area only after it is empty and still HUD-owned.
- All destructive operations require an exact preview and a one-use token expiring after 30 seconds.
- Confirmation rebuilds the plan and performs zero mutation when the plan is stale.
- No force option or ownership bypass exists.
- Live deletion acceptance runs only in the disposable `Dragons Gate HUD` profile.
- Preserve user triggers, aliases, scripts, settings, chat logs, unrelated packages, and personal map content.

---

### Task 1: Ownership-Safe Mapper Inspection and Deletion Primitives

**Files:**
- Modify: `src/map_adapter.lua`
- Modify: `tests/lua/test_map_adapter.lua`

**Interfaces:**
- Consumes: existing `MapAdapter:roomRecord(roomID)` and guarded Mudlet API invocation helpers.
- Produces:
  - `MapAdapter:areaRecord(areaID) -> record | nil, error`
  - `MapAdapter:roomsInArea(areaID) -> sortedRoomIDs | nil, error`
  - `MapAdapter:inboundSources(roomIDs) -> sortedSourceIDs | nil, error`
  - `MapAdapter:deleteOwnedRoom(roomID) -> true | nil, error`
  - `MapAdapter:deleteEmptyOwnedArea(areaID) -> true | nil, error`
  - `MapAdapter:invalidateDeleted(roomIDs, areaID) -> true`

- [ ] **Step 1: Add failing ownership and mutation tests**

Extend the fake Mudlet API with `getAreaRooms1`, `getRooms`, and exit/special-exit inspection. Add literal tests proving:

```lua
test("individual deletion accepts only a persisted HUD-owned room",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0}))
  eq(map:deleteOwnedRoom(100),true); eq(api.rooms[100],nil)
end)

test("unowned inbound sources block deletion without mutation",function()
  -- room 50 is personal and exits to HUD room 100
  local sources=assert(map:inboundSources({100}))
  eq(sources[1],50)
  eq(api.rooms[50].exits.n,100); eq(api.rooms[100]~=nil,true)
end)

test("empty area deletion requires persisted area ownership",function()
  eq(map:deleteEmptyOwnedArea(personalArea),nil)
  eq(api.areas["Personal"],personalArea)
end)
```

- [ ] **Step 2: Run adapter tests and verify RED**

Run: `lua tests/run.lua`

Expected: the new tests fail because the six adapter methods do not exist.

- [ ] **Step 3: Implement guarded inspection**

`areaRecord` must read area existence and `dghud.owner`; `roomsInArea` must normalize zero- or one-indexed Mudlet tables into unique sorted positive IDs. `inboundSources` must scan every existing room's ordinary and special exits and return only sources outside the deletion set.

```lua
function MapAdapter:areaRecord(areaID)
  local owner,err=read(self.api,"getAreaUserData",areaID,"dghud.owner")
  if owner==nil and err then return nil,err end
  return {id=areaID,owned=owner==self.owner,owner=owner}
end
```

All API errors fail closed.

- [ ] **Step 4: Implement guarded room-first deletion**

`deleteOwnedRoom` re-reads `roomRecord` immediately before `deleteRoom`. `deleteEmptyOwnedArea` re-reads area ownership and requires `roomsInArea` to return zero rooms before calling `deleteArea`. Neither method accepts cached ownership.

- [ ] **Step 5: Expose required Mudlet APIs through `MapAdapter.mudletApi`**

Add guarded wrappers for `getAreaRooms1` and any exit-query APIs used by inspection. Do not add exit-removal mutations.

- [ ] **Step 6: Run full tests and commit**

Run: `lua tests/run.lua && python3 tests/test_build.py`

Expected: PASS.

Commit:

```bash
git add src/map_adapter.lua tests/lua/test_map_adapter.lua
git commit -m "feat: add ownership-safe map deletion primitives"
```

### Task 2: Immutable Cleanup Planner and Confirmation Controller

**Files:**
- Create: `src/map_cleanup.lua`
- Create: `tests/lua/test_map_cleanup.lua`
- Modify: `tests/run.lua`
- Modify: `src/entry.lua`
- Modify: `scripts/build.py`

**Interfaces:**
- Consumes Task 1 adapter methods and a runtime safety provider.
- Produces:
  - `Cleanup.new(map, runtime, clock, tokenFactory, ttlSeconds) -> cleanup`
  - `cleanup:previewRoom(roomID) -> preview | nil, error`
  - `cleanup:previewArea(target) -> preview | nil, error`
  - `cleanup:previewSubmap(rootRoomID) -> preview | nil, error`
  - `cleanup:confirm(token) -> result | nil, error`
  - `cleanup:cancel() -> true`
  - `cleanup:pending() -> preview | nil`

`runtime:safetySnapshot(roomIDs)` returns `{current_room,walking,route_rooms,pending_automap,pending_special}`. `runtime:beforeDelete(plan)` and `runtime:afterDelete(result)` perform lifecycle integration.

- [ ] **Step 1: Add failing planner tests**

Cover room, exact area, and `special:<root>` scope resolution; sorted immutable IDs; current/route/pending blockers; personal inbound blockers; 30-second expiry; cancellation; token reuse; and stale ownership/membership.

```lua
test("confirmation rebuilds the plan and rejects changed membership",function()
  local preview=assert(cleanup:previewSubmap(900))
  map.areaRooms={900,901,902}
  local result,err=cleanup:confirm(preview.token)
  eq(result,nil); eq(err,"cleanup preview is stale"); eq(map.deleteCalls,0)
end)
```

- [ ] **Step 2: Run cleanup tests and verify RED**

Run: `lua tests/run.lua`

Expected: module-not-found or missing-interface failures for `map_cleanup`.

- [ ] **Step 3: Implement exact planners**

Plans contain only serializable scalar/table data:

```lua
{
  operation="clear_submap", target="900", area_id=42,
  partition="special:900", room_ids={900,901},
  created_at=clock(), token=tokenFactory(), blockers={}
}
```

Area names resolve only by exact match or exact numeric ID. Submaps require exact persisted partition on every room. Preview refuses any blocker instead of issuing a token.

- [ ] **Step 4: Implement expiry, one-use confirmation, and stale comparison**

Consume the token before execution. Rebuild the plan without generating a new token and compare operation, target, area, partition, sorted IDs, inbound sources, and safety snapshot. Any mismatch returns `cleanup preview is stale` with zero mutations.

- [ ] **Step 5: Implement deterministic execution and partial-failure results**

Delete ascending room IDs. Stop on first failure. Return:

```lua
{deleted={100,101},failed=102,untouched={102,103},area_deleted=false}
```

Delete an area only after all room deletions succeed and the area is reverified empty/owned. Always call `afterDelete` with actual results.

- [ ] **Step 6: Register module, run full tests, and commit**

Run: `lua tests/run.lua && python3 tests/test_build.py`

Commit:

```bash
git add src/map_cleanup.lua tests/lua/test_map_cleanup.lua tests/run.lua src/entry.lua scripts/build.py
git commit -m "feat: add confirmed map cleanup planner"
```

### Task 3: Runtime Safety Boundary and User Commands

**Files:**
- Modify: `src/main.lua`
- Modify: `src/mudlet_adapter.lua`
- Modify: `src/events.lua` if an owned timer/event name is needed
- Modify: `tests/lua/test_runtime.lua`

**Interfaces:**
- Consumes `Cleanup.new` and Task 2 planner methods.
- Produces aliases for the five approved commands and runtime callbacks used by `map_cleanup.lua`.

- [ ] **Step 1: Add failing runtime alias and hazard tests**

Add tests proving exact alias parsing, malformed target rejection, preview output, token confirmation, cancellation, active walker blocking, current-room blocking, pending automapper/special-transition blocking, and owned alias cleanup on shutdown.

```lua
test("cleanup aliases preview exact targets and confirmation is token-bound",function()
  aliasCallback(f,"^dghud map delete room (\\d+)$")({"", "100"})
  eq(hud.cleanup:pending().room_ids[1],100)
  aliasCallback(f,"^dghud map confirm (\\S+)$")({"",hud.cleanup:pending().token})
  eq(f.map.rooms[100],nil)
end)
```

- [ ] **Step 2: Run runtime tests and verify RED**

Run: `lua tests/run.lua`

Expected: aliases and cleanup runtime do not exist.

- [ ] **Step 3: Implement runtime safety snapshots**

The snapshot must combine GMCP current room, `walker:active()` and its remaining route, `automapper.pending`, `special_transition:pending()`, and generated speed-walk state. Any uncertainty blocks planning.

- [ ] **Step 4: Implement lifecycle callbacks**

`beforeDelete` stops walking and cancels pending transitions only after final revalidation. `afterDelete` removes IDs from `managed_rooms`, clears adapter caches, calls Mudlet map refresh, and reprocesses current GMCP only when its room was not deleted.

- [ ] **Step 5: Implement exact aliases and bounded output**

Preview output includes operation, exact area, count, sorted IDs, and:

```text
[DGHUD Map] Preview ABC123 expires in 30 seconds.
[DGHUD Map] Confirm with: dghud map confirm ABC123
```

Errors contain no personal map dumps. Confirmation reports exact deleted/failed/untouched IDs.

- [ ] **Step 6: Implement adapter clock/token/reporting boundary**

Use `os.time` for expiry. Token generation must combine high-entropy runtime data where available and produce a short opaque alphanumeric token; tests inject deterministic factories. Add `refreshMap()` that contains Mudlet exceptions.

- [ ] **Step 7: Run full tests and commit**

Run: `lua tests/run.lua && python3 tests/test_build.py`

Commit:

```bash
git add src/main.lua src/mudlet_adapter.lua src/events.lua tests/lua/test_runtime.lua
git commit -m "feat: add safe mapper cleanup commands"
```

### Task 4: End-to-End Preservation and Failure Acceptance

**Files:**
- Modify: `tests/lua/test_mapper_acceptance.lua`
- Modify: `docs/MUDLET_ACCEPTANCE.md`
- Modify: `README.md`

**Interfaces:**
- Consumes the complete cleanup feature.
- Produces durable regression coverage and user documentation.

- [ ] **Step 1: Add failing acceptance fixtures**

Create a fake map containing HUD rooms/submaps plus byte-recorded personal rooms, ordinary exits, special exits, coordinates, names, and metadata. Assert preview/cancel/expiry cause no mutation and successful cleanup changes only selected HUD-owned objects.

- [ ] **Step 2: Run acceptance tests and verify RED if integration gaps remain**

Run: `lua tests/run.lua`

Expected: any missing integration causes a focused preservation or lifecycle failure.

- [ ] **Step 3: Close only acceptance-discovered gaps**

Make the smallest production correction required by a failing acceptance test. Do not add new cleanup scope or a force option.

- [ ] **Step 4: Document commands and recovery flow**

README examples must state: move out of the affected room/submap, stop walking, preview, inspect exact IDs, confirm within 30 seconds, and revisit rooms to remap them. `docs/MUDLET_ACCEPTANCE.md` must include cancel, expiry, stale preview, partial failure, and personal-content comparison checks.

- [ ] **Step 5: Run full verification and commit**

Run:

```bash
lua tests/run.lua
python3 tests/test_build.py
git diff --check
```

Commit:

```bash
git add tests/lua/test_mapper_acceptance.lua docs/MUDLET_ACCEPTANCE.md README.md src
git commit -m "test: verify safe map cleanup preservation"
```

### Task 5: Release, Disposable-Profile Acceptance, and Independent Review

**Files:**
- Modify: `src/defaults.lua`
- Modify: version expectations in `tests/lua/test_updater.lua` and `tests/lua/test_mapper_acceptance.lua`
- Generated but ignored: `dist/DragonsGateHUD.mpackage`, `dist/manifest.json`

**Interfaces:**
- Consumes all prior tasks.
- Produces the next patch release and verified installation in `Dragons Gate HUD` only.

- [ ] **Step 1: Run an independent whole-branch safety review**

Reviewer must inspect ownership authority, inbound personal-exit checks, current/route blockers, stale confirmation, partial failure, cache reconciliation, and preservation tests. Resolve every load-bearing finding before release.

- [ ] **Step 2: Bump the patch version exactly once**

Update the production version and literal test expectations. The newer-version updater fixture must remain one patch higher than the installed fixture.

- [ ] **Step 3: Run release verification**

```bash
lua tests/run.lua
python3 tests/test_build.py
dghud_release_version=$(lua -e 'package.path="src/?.lua;"..package.path; print(require("defaults").version)')
python3 scripts/build.py --owner wizzydizzy-ctrl --repository dragons-gate-hud --version "$dghud_release_version"
python3 -c 'import hashlib,json,pathlib; p=pathlib.Path("dist/DragonsGateHUD.mpackage"); m=json.loads(pathlib.Path("dist/manifest.json").read_text()); assert p.stat().st_size==m["archive_size"]; assert hashlib.sha256(p.read_bytes()).hexdigest()==m["sha256"]'
git diff --check
```

- [ ] **Step 4: Commit, push, tag, and verify published assets**

Commit source/tests/docs, push `main`, create annotated `v<version>`, wait for GitHub Actions, download both release assets into `mktemp -d`, and independently verify version, size, and SHA-256.

- [ ] **Step 5: Install only in the disposable profile**

Run `dghud update` in `Dragons Gate HUD`. Do not execute deletion against an existing production map area. Build an isolated HUD-owned test submap, move outside it, verify preview/cancel/expiry, confirm cleanup, revisit one deleted canonical room, and verify clean remapping.

- [ ] **Step 6: Verify preservation and hand off**

Compare recorded personal map content before/after, confirm unrelated triggers/aliases/scripts/packages remain unchanged, ensure the repository is clean, and report the release URL, tests, live acceptance, and exact commands.
