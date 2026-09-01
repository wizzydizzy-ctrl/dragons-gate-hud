# Special Exits, Sub-Maps, and Zoom Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Persist every confirmed non-directional Dragons Gate room transition as a canonical GMCP-room special exit into a separate sub-map, support safe walking across those exits, and add working embedded zoom controls.

**Architecture:** A focused `special_transition` component owns short-lived command candidates and their timers. `automapper` decides effective map partitions from canonical GMCP room IDs and delegates persistent room, area, standard-exit, special-exit, and zoom mutations to `map_adapter`; `map_walker` accepts special steps only after adapter validation. The Geyser view exposes zoom callbacks but contains no mapper policy.

**Tech Stack:** Lua 5.1, Mudlet 5.0/Geyser, Mudlet mapper APIs (`addSpecialExit`, `getSpecialExits`, `getMapZoom`, `setMapZoom`, room/area user data), Python 3 package builder, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-01-special-exits-submaps-zoom-design.md`

## Global Constraints

- `gmcp.Room.Info.num` is the only canonical room identity; never create duplicate rooms for one GMCP number.
- Every confirmed non-directional transition to an unseen room creates a separate HUD-owned sub-map, including doors.
- Reverse special exits are observation-only and may use a different command.
- Existing unowned rooms, areas, exits, settings, triggers, aliases, scripts, timers, keys, packages, and modules must not be mutated.
- Candidate confirmation defaults to three seconds; same-room GMCP refreshes do not confirm or cancel it.
- Zoom uses Mudlet's native per-area APIs, clamps at `3.0` minimum, and never changes room coordinates.
- Updates replace only the `DragonsGateHUD` package and preserve map records, zoom, settings, and logs.
- Every production change follows red-green-refactor and every task ends with a focused commit.

---

## File Structure

- Create `src/special_transition.lua`: classify outbound commands and own one cancellable, expiring special-transition candidate.
- Modify `src/automapper.lua`: consume standard or special pending transitions, select effective partitions, preserve canonical existing-room placement, and connect observed edges.
- Modify `src/map_adapter.lua`: persist/read partitions, add and validate special exits, expose room area and native zoom operations.
- Modify `src/map_walker.lua`: accept validated special route steps while preserving exact expected-room safety.
- Modify `src/main.lua`: wire timers, route validation, generated special commands, zoom callbacks, and bounded diagnostics.
- Modify `src/view.lua`: render responsive `−`, center, and `+` controls above the embedded mapper.
- Modify `src/layout.lua`: reserve a small non-overlapping zoom toolbar inside the mapper frame.
- Modify `src/defaults.lua`: add candidate timeout and zoom configuration and advance the release version only in the final task.
- Modify `src/settings.lua` only if schema migration requires explicit normalization of new nested mapper keys.
- Modify `src/mudlet_adapter.lua`: expose mapper API wrappers if they are not supplied through `MapAdapter.mudletApi`.
- Modify `tests/lua/test_special_transition.lua`: unit coverage for candidate classification, replacement, expiration, and cancellation.
- Modify `tests/lua/test_map_adapter.lua`: persistence, ownership, special-exit, partition, and zoom adapter coverage.
- Modify `tests/lua/test_automapper.lua`: canonical-room/sub-map behavior and observed reverse links.
- Modify `tests/lua/test_map_walker.lua`: validated special-route execution and rejection.
- Modify `tests/lua/test_runtime.lua`: event/timer/UI callback integration and isolation.
- Modify `tests/lua/test_layout.lua` and `tests/lua/test_view.lua`: responsive zoom-control geometry and callbacks.
- Modify `tests/lua/test_mapper_acceptance.lua`: end-to-end persistence, reload, walking, and personal-content guarantees.
- Modify `tests/run.lua`: load the new transition unit test.
- Modify `README.md` and `docs/MUDLET_ACCEPTANCE.md`: document behavior, controls, diagnostics, and live checks.

---

### Task 1: Short-Lived Special Transition Candidates

**Files:**
- Create: `src/special_transition.lua`
- Create: `tests/lua/test_special_transition.lua`
- Modify: `tests/run.lua`
- Modify: `src/defaults.lua`
- Test: `tests/lua/test_special_transition.lua`

**Interfaces:**
- Consumes: `model.direction(command)`, adapter functions `schedule(seconds, callback)` and `cancelTimer(id)`.
- Produces: `SpecialTransition.new(model, adapter, timeoutSeconds, onStatus)`, `:onOutgoing(command, originID)`, `:onRoom(roomID)`, `:cancel(reason)`, `:pending()`, and `:shutdown()`.
- `:onRoom(roomID)` returns either `nil` or a table whose `from` and `to` fields are positive integers, whose `command` is a normalized nonempty string, and whose `kind` is `"special"`.

- [ ] **Step 1: Write failing classification and confirmation tests**

```lua
local Special=require("special_transition")

test("confirms the final eligible non-direction command from canonical rooms",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("open gate",100)); assert(tracker:onOutgoing("go gate",100))
  eq(tracker:onRoom(100),nil)
  local transition=assert(tracker:onRoom(900))
  eq(transition.from,100); eq(transition.to,900); eq(transition.command,"go gate")
  eq(tracker:pending(),nil)
end)

test("directions controls and expired candidates never become special exits",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  eq(tracker:onOutgoing("north",100),nil)
  eq(tracker:onOutgoing("dghud update",100),nil)
  assert(tracker:onOutgoing("climb rope",100)); adapter:fireOnlyTimer()
  eq(tracker:onRoom(900),nil)
end)
```

- [ ] **Step 2: Run the suite and verify the missing module failure**

Run: `lua tests/run.lua`

Expected: FAIL because `special_transition` cannot be loaded.

- [ ] **Step 3: Implement the minimal candidate state machine**

```lua
function Special:onOutgoing(command,originID)
  self:cancel("replaced")
  local value=normalize(command)
  if not positive(originID) or value=="" or self.model.direction(value) or excluded(value) then return nil end
  local timer,err=self.adapter:schedule(self.timeout_seconds,function() self.timer=nil; self.candidate=nil; self:status("expired") end)
  if not timer then return nil,err or "special transition timer could not be created" end
  self.timer=timer; self.candidate={from=tonumber(originID),command=value}
  return true
end

function Special:onRoom(roomID)
  local destination=positive(roomID) and tonumber(roomID) or nil
  if not self.candidate or not destination or destination==self.candidate.from then return nil end
  local result={from=self.candidate.from,to=destination,command=self.candidate.command,kind="special"}
  local ok,err=self:cancel("confirmed")
  if not ok then return nil,err end
  return result
end
```

The explicit exclusion set must include `dghud`, `walkto`, `walkstop`, `mapcenter`, `inventory`, `inv`, `stat`, `info`, `look`, `l`, `who`, `say`, `whisper`, `link`, and their argument forms. A later outbound command always cancels or replaces the previous candidate. Standard movement, wrong-direction handling, disconnect, and shutdown call `:cancel()` through later runtime wiring.

- [ ] **Step 4: Add cancellation and timer-failure tests, then make them pass**

```lua
test("replacement disconnect and cancellation failures clear candidate ownership",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("enter tunnel",100)); assert(tracker:cancel("disconnect"))
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
  adapter.cancelError="cancel exploded"; assert(tracker:onOutgoing("climb rope",100))
  local ok,err=tracker:cancel("shutdown"); eq(ok,nil); assert(err:find("cancel exploded",1,true))
  eq(tracker:pending(),nil)
end)
```

Run: `lua tests/run.lua`

Expected: all tests PASS with no timer remaining after cancellation or shutdown.

- [ ] **Step 5: Add defaults and commit**

Add to `defaults.mapper`:

```lua
special_timeout = 3,
zoom_step = 2.5,
zoom_min = 3.0,
zoom_max = 60.0,
```

Run: `git diff --check && lua tests/run.lua`

Commit:

```bash
git add src/special_transition.lua src/defaults.lua tests/lua/test_special_transition.lua tests/run.lua
git commit -m "feat: track confirmed special transitions"
```

---

### Task 2: Persistent Partitions and Canonical Room Reuse

**Files:**
- Modify: `src/map_adapter.lua`
- Modify: `tests/lua/test_map_adapter.lua`
- Test: `tests/lua/test_map_adapter.lua`

**Interfaces:**
- Consumes: normalized room tables from `MapperModel.normalizeRoom` and effective partition strings selected by `Automapper`.
- Produces: `MapAdapter:roomRecord(roomID)`, `:effectivePartition(roomID)`, and extended `:ensureRoom(room, coordinates, partitionKey)`.
- `roomRecord` returns a table with `exists` and `owned` booleans plus optional `partition`, `area`, and `coordinates` values, or `nil,error`.

- [ ] **Step 1: Write failing persistence tests**

```lua
test("persists a special destination partition keyed by canonical room ID",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Vault"),{x=0,y=0,z=0},"special:900"))
  eq(api.rooms[900].user["dghud.partition"],"special:900")
  eq(api.rooms[900].user["dghud.game_area"],"1")
  local record=assert(Adapter.new(api):roomRecord(900))
  eq(record.partition,"special:900"); eq(record.area,api.rooms[900].area)
end)

test("existing canonical rooms retain their area and coordinates",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1"),{x=0,y=0,z=0},"special:900"))
  local area=api.rooms[900].area
  assert(map:ensureRoom(descriptor(900,"2"),{x=8,y=8,z=0},"special:other"))
  eq(api.rooms[900].area,area); eq(api.rooms[900].x,0); eq(api.rooms[900].y,0)
end)
```

- [ ] **Step 2: Run tests and verify partition arguments are unsupported**

Run: `lua tests/run.lua`

Expected: FAIL because `ensureRoom` does not persist partitions and rewrites existing placement.

- [ ] **Step 3: Implement canonical existing-room preservation**

Add `getRoomArea` to the guarded API and read existing room metadata before mutation. For newly created rooms only, set area and coordinates. For existing owned rooms, refresh safe descriptive metadata but retain area, partition, and coordinates.

```lua
if createdThisCall then
  operations[#operations+1]={"setRoomUserData",room.id,"dghud.partition",partitionKey}
  operations[#operations+1]={"setRoomUserData",room.id,"dghud.game_area",tostring(room.area_key)}
  operations[#operations+1]={"setRoomArea",room.id,area}
  operations[#operations+1]={"setRoomCoordinates",room.id,coordinates.x,coordinates.y,coordinates.z}
end
```

Area names for partitions must be deterministic:

```lua
local function areaName(key)
  local destination=tostring(key):match("^special:(%d+)$")
  return destination and ("Dragons Gate - Submap "..destination) or ("Dragons Gate - "..tostring(key))
end
```

- [ ] **Step 4: Test migration and ownership conflicts**

Add cases proving an existing owned pre-feature room receives a stable effective partition derived from its existing area without moving, and an unowned canonical collision returns the current ownership error with zero mutations.

Run: `lua tests/run.lua`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/map_adapter.lua tests/lua/test_map_adapter.lua
git commit -m "feat: persist canonical mapper partitions"
```

---

### Task 3: Observed Special Exits and Sub-Map Automapping

**Files:**
- Modify: `src/map_adapter.lua`
- Modify: `src/automapper.lua`
- Modify: `tests/lua/test_map_adapter.lua`
- Modify: `tests/lua/test_automapper.lua`
- Test: `tests/lua/test_map_adapter.lua`, `tests/lua/test_automapper.lua`

**Interfaces:**
- Consumes: transition tables from Task 1 and partition persistence from Task 2.
- Produces: `MapAdapter:connectSpecial(fromID,toID,command)`, `:specialExitMatches(fromID,toID,command)`, and `Automapper:onSpecialTransition(transition)`.
- `connectSpecial` is idempotent and requires both endpoint rooms to be HUD-owned.

- [ ] **Step 1: Write failing adapter special-exit tests**

```lua
test("adds only observed one-way special exits between owned rooms",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  assert(map:connectSpecial(100,900,"go gate")); assert(map:connectSpecial(100,900,"go gate"))
  eq(api.special[100]["go gate"],900); eq(api.special[900],nil)
  eq(map:specialExitMatches(100,900,"go gate"),true)
end)
```

- [ ] **Step 2: Run tests and verify missing special-exit APIs fail**

Run: `lua tests/run.lua`

Expected: FAIL because `connectSpecial` and fake `addSpecialExit/getSpecialExits` do not exist.

- [ ] **Step 3: Implement guarded special-exit adapter methods**

Add `addSpecialExit` and `getSpecialExits` to `MapAdapter.mudletApi`. Validate positive endpoint IDs, nonempty normalized commands, and ownership before calling Mudlet. Read existing special exits first; return success without mutation when the exact edge already exists.

```lua
function MapAdapter:connectSpecial(fromID,toID,command)
  if not self:isOwned(fromID) or not self:isOwned(toID) then return nil,"special exit endpoints are not owned by DragonsGateHUD" end
  if self:specialExitMatches(fromID,toID,command) then return true end
  return invoke(self.api,"addSpecialExit",fromID,toID,command)
end
```

- [ ] **Step 4: Write failing automapper sub-map and reverse-observation tests**

```lua
test("special movement creates a destination-rooted submap and exact edge",function()
  assert(mapper:onRoom(room(100,"Outside",1,{"north"})))
  assert(mapper:onSpecialTransition({from=100,to=900,command="go door",kind="special"}))
  assert(mapper:onRoom(room(900,"Inside",1,{"south"})))
  eq(map.rooms[900].partition,"special:900")
  eq(map.special[1].from,100); eq(map.special[1].to,900); eq(map.special[1].command,"go door")
end)

test("reverse special edge appears only after observed return command",function()
  -- map 100 -> 900 first
  eq(#map.special,1)
  assert(mapper:onSpecialTransition({from=900,to=100,command="leave door",kind="special"}))
  assert(mapper:onRoom(room(100,"Outside",1,{"north"})))
  eq(#map.special,2); eq(map.special[2].command,"leave door")
end)
```

- [ ] **Step 5: Implement partition selection and deferred connection**

`onSpecialTransition` stores a pending special transition. On destination GMCP arrival:

- look up the canonical destination first;
- use its persisted partition when it exists;
- otherwise use the literal prefix `special:` followed by the numeric destination ID;
- create/ensure the room at `{0,0,0}` in that partition;
- connect the exact one-way special edge only after room ensure succeeds;
- clear pending state on every terminal error.

Directional moves inherit the origin's effective special partition when the destination's game area equals the origin's saved game area. A changed game area uses the normalized GMCP area key. Existing canonical destinations always retain their persisted partition.

- [ ] **Step 6: Test multiple entrances, reload, and error containment**

Add cases for two origins entering room `900`, directional exploration inside `special:900`, a directional GMCP area change, adapter reload, same-room refresh, unowned destination collision, and failed `addSpecialExit`. Assert no duplicate room, no moved room, and no invented edge.

Run: `lua tests/run.lua`

Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add src/map_adapter.lua src/automapper.lua tests/lua/test_map_adapter.lua tests/lua/test_automapper.lua
git commit -m "feat: map observed special exits into submaps"
```

---

### Task 4: Runtime Transition Wiring and Isolation

**Files:**
- Modify: `src/main.lua`
- Modify: `tests/lua/test_runtime.lua`
- Test: `tests/lua/test_runtime.lua`

**Interfaces:**
- Consumes: `SpecialTransition` from Task 1 and `Automapper:onSpecialTransition` from Task 3.
- Produces: exactly one tracker per running HUD, owned timers, and unchanged event-count health semantics.

- [ ] **Step 1: Write failing runtime integration tests**

```lua
test("runtime confirms the final non-direction command from the next canonical room",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={},mapper={special_timeout=3}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"go gate")
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,900); eq(f.map.special[1].command,"go gate")
end)

test("disconnect reload and shutdown remove candidate timers without touching personal timers",function()
  local f=fake(); f.personalTimer="personal"; local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); f.callbacks["sysDisconnectionEvent"]()
  eq(hud.special_transition:pending(),nil); eq(f.timers.personal,"kept")
end)
```

- [ ] **Step 2: Run tests and verify runtime has no tracker**

Run: `lua tests/run.lua`

Expected: FAIL because `Main` does not construct or invoke `SpecialTransition`.

- [ ] **Step 3: Wire candidate lifecycle**

Construct the tracker after `Automapper`, using the existing adapter scheduler and configured timeout. In the outbound event:

- generated walker commands are marked before processing;
- standard directions go to `Automapper:onOutgoing` and cancel a special candidate;
- eligible nongenerated non-directions go to `SpecialTransition:onOutgoing(command,currentRoom)`;
- generated confirmed special route commands are still eligible to become pending transitions.

In the room event, call `transition=tracker:onRoom(info.num)` before `Automapper:onRoom`; if present, call `Automapper:onSpecialTransition(transition)` before room ingestion. Cancel on wrong direction, disconnect, mapper disablement, shutdown, and startup rollback.

- [ ] **Step 4: Add failure rollback and runtime-count tests**

Test scheduler failure, cancellation exceptions, mapper failure after confirmation, repeated reload, and shutdown. Assert all HUD-owned timers/events/aliases are removed exactly once and unrelated runtime survives.

Run: `lua tests/run.lua`

Expected: all tests PASS and existing health checks remain valid.

- [ ] **Step 5: Commit**

```bash
git add src/main.lua tests/lua/test_runtime.lua
git commit -m "feat: wire special transition mapping runtime"
```

---

### Task 5: Safe Walking Across Confirmed Special Exits

**Files:**
- Modify: `src/map_adapter.lua`
- Modify: `src/map_walker.lua`
- Modify: `src/main.lua`
- Modify: `tests/lua/test_map_walker.lua`
- Modify: `tests/lua/test_runtime.lua`
- Test: `tests/lua/test_map_walker.lua`, `tests/lua/test_runtime.lua`

**Interfaces:**
- Consumes: route `{rooms={...},commands={...}}` and adapter `validateStep(fromID,toID,command)`.
- Produces: `MapAdapter:validateRouteStep(fromID,toID,command)` and walker support for exact confirmed special commands.

- [ ] **Step 1: Replace the old rejection test with failing validation tests**

```lua
test("walker sends a confirmed special command and waits for its exact room",function()
  local adapter=fakeAdapter(); function adapter:validateStep(from,to,command) return from==1 and to==2 and command=="go gate" end
  local walker=Walker.new(adapter,function() end)
  assert(walker:start({rooms={1,2,3},commands={"go gate","n"}},3))
  eq(adapter.sent[1].command,"go gate"); assert(walker:onRoom(2)); eq(adapter.sent[2].command,"n")
end)

test("walker rejects an unconfirmed special route command",function()
  local adapter=fakeAdapter(); function adapter:validateStep() return nil,"special exit is not confirmed" end
  local ok,err=Walker.new(adapter,function() end):start({rooms={1,2},commands={"pull lever"}},2)
  eq(ok,nil); eq(err,"special exit is not confirmed")
end)
```

- [ ] **Step 2: Run tests and verify special commands remain rejected**

Run: `lua tests/run.lua`

Expected: FAIL with `unsupported route command go gate`.

- [ ] **Step 3: Validate every route edge before walker activation**

Directions remain locally normalized. For each non-direction step call `adapter:validateStep(route.rooms[i],route.rooms[i+1],command)` inside protected error handling. Store the exact confirmed command without rewriting case-sensitive game syntax.

Expose `MapAdapter:validateRouteStep` as:

```lua
function MapAdapter:validateRouteStep(fromID,toID,command)
  local direction=MapperModel.direction(command)
  if direction then return true,direction end
  if self:specialExitMatches(fromID,toID,command) then return true,command end
  return nil,"special exit is not confirmed from "..fromID.." to "..toID
end
```

- [ ] **Step 4: Mark generated special commands and test runtime walking**

Replace the single direction-valued `generated_movement` marker with an exact generated command token. The outbound event consumes it only when the sent command matches. Test `walkto` and map click across a mixed route, roundtime pause, wrong destination, timeout, and a manually typed non-direction command replacing the route.

Run: `lua tests/run.lua`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/map_adapter.lua src/map_walker.lua src/main.lua tests/lua/test_map_walker.lua tests/lua/test_runtime.lua
git commit -m "feat: walk across confirmed special exits"
```

---

### Task 6: Native Per-Area Zoom and Responsive Controls

**Files:**
- Modify: `src/map_adapter.lua`
- Modify: `src/view.lua`
- Modify: `src/layout.lua`
- Modify: `src/main.lua`
- Modify: `tests/lua/test_map_adapter.lua`
- Modify: `tests/lua/test_view.lua`
- Modify: `tests/lua/test_layout.lua`
- Modify: `tests/lua/test_runtime.lua`
- Test: mapper adapter, view, layout, and runtime suites.

**Interfaces:**
- Consumes: current canonical room ID and settings `zoom_step`, `zoom_min`, `zoom_max`.
- Produces: `MapAdapter:zoom(roomID, visualDirection)`, `:currentZoom(roomID)`, `View:setMapZoomCallback(callback)`, and three HUD controls.
- `visualDirection` is `"larger"` or `"smaller"`; the adapter hides Mudlet's inverted numeric convention.

- [ ] **Step 1: Write failing native zoom tests**

```lua
test("visual zoom direction hides Mudlet numeric inversion and clamps per area",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.zoom[7]=20
  local map=Adapter.new(api)
  eq(map:zoom(100,"larger",2.5,3,60),17.5); eq(api.zoom[7],17.5)
  eq(map:zoom(100,"smaller",2.5,3,60),20); eq(api.zoom[7],20)
  api.zoom[7]=3; eq(map:zoom(100,"larger",2.5,3,60),3)
end)
```

- [ ] **Step 2: Run tests and verify zoom methods are missing**

Run: `lua tests/run.lua`

Expected: FAIL because `zoom` and `currentZoom` do not exist.

- [ ] **Step 3: Implement guarded area zoom**

Add `getRoomArea`, `getMapZoom`, and `setMapZoom` wrappers. Require an owned canonical room, read its area, read current zoom, compute `current-step` for `larger` and `current+step` for `smaller`, clamp, set the area-specific zoom, call `updateMap`, and return the applied value. Any API error leaves the previous zoom unchanged and returns `nil,error`.

- [ ] **Step 4: Write failing view and layout tests**

```lua
test("mapper owns visible minus center and plus controls without covering compass",function()
  local view=chatView(); local layout=Layout.compute(1920,1080); view:applyLayout(layout)
  eq(view.map_zoom_out.visible,true); eq(view.map_center.visible,true); eq(view.map_zoom_in.visible,true)
  eq(view.map_zoom_in.parent,view.mapper_frame)
  eq(view.map_zoom_in.y+view.map_zoom_in.height<=view.mapper_frame.height,true)
end)

test("zoom buttons invoke visual actions",function()
  local view=chatView(); local calls={}; view:setMapZoomCallback(function(action) calls[#calls+1]=action end)
  view.map_zoom_in.click(); view.map_zoom_out.click(); view.map_center.click()
  eq(table.concat(calls,","),"larger,smaller,center")
end)
```

- [ ] **Step 5: Implement the responsive mapper toolbar**

Create three small labels parented to `mapper_frame`. Reserve `layout.lower_mapper_toolbar_height` at the top of the frame, place the native mapper below it, and keep the existing mapper minimum height measured on usable map content. Use `−`, `◎`, and `+` labels with tooltips when supported. Hide all three in compact mode or whenever the mapper is hidden.

- [ ] **Step 6: Wire callbacks and failures**

`Main` sets one callback after creating the view. `larger` and `smaller` call `map:zoom(currentRoom, action, settings...)`; `center` calls `map:center(currentRoom)`. Report success as a bounded mapper status and failures through the existing mapper error path. Test repeated resize does not create duplicate controls or callbacks.

Run: `lua tests/run.lua`

Expected: all tests PASS across `1920x1080`, `1200x800`, `1200x650`, `1000x650`, and `760x700` fixtures.

- [ ] **Step 7: Commit**

```bash
git add src/map_adapter.lua src/view.lua src/layout.lua src/main.lua tests/lua/test_map_adapter.lua tests/lua/test_view.lua tests/lua/test_layout.lua tests/lua/test_runtime.lua
git commit -m "feat: add native embedded mapper zoom controls"
```

---

### Task 7: Acceptance, Documentation, Version, and Release Verification

**Files:**
- Modify: `tests/lua/test_mapper_acceptance.lua`
- Modify: `README.md`
- Modify: `docs/MUDLET_ACCEPTANCE.md`
- Modify: `src/defaults.lua`
- Test: full Lua suite and Python package build test.

**Interfaces:**
- Consumes: all prior task interfaces.
- Produces: one releasable package version with documented update and live acceptance behavior.

- [ ] **Step 1: Write failing end-to-end acceptance tests**

Cover this exact sequence in a fake persistent Mudlet map:

```lua
room(100) -> send("go door") -> room(900)
room(900) -> send("north")   -> room(901)
room(901) -> send("go arch") -> room(1200)
room(1200)-> send("leave")   -> room(901)
reload HUD -> revisit room(900) -> zoom larger -> walkto(100)
```

Assert canonical IDs `{100,900,901,1200}` exist once; partitions are normal, `special:900`, `special:900`, and `special:1200`; only observed special edges exist; reload preserves them; zoom targets the saved area; and mixed special/directional walking sends one command per expected GMCP destination.

- [ ] **Step 2: Run tests and verify acceptance gaps fail**

Run: `lua tests/run.lua`

Expected: FAIL until all integrated persistence and route assertions are satisfied.

- [ ] **Step 3: Update documentation**

Document:

- canonical GMCP room identity and duplicate prevention;
- every confirmed non-direction destination starting a sub-map;
- observed-only reverse connections;
- three-second candidate rule and conservative exclusions;
- safe special-exit `walkto` support;
- `−`, center, and `+` behavior and per-area persistence;
- ownership and update isolation;
- disposable-profile live acceptance commands and expected observations.

- [ ] **Step 4: Bump the release version exactly once**

Read the latest published tag with `git tag --sort=-v:refname | head -1`, choose the next patch version, update `Defaults.version`, and update the single acceptance assertion that pins it. Do not guess the version before reading the tag.

- [ ] **Step 5: Run fresh full verification**

```bash
lua tests/run.lua
python3 -m unittest discover -s tests -v
dghud_release_version=$(lua -e 'package.path="src/?.lua;"..package.path; print(require("defaults").version)')
python3 scripts/build.py --owner wizzydizzy-ctrl --repository dragons-gate-hud --version "$dghud_release_version"
git diff --check
python3 -c 'import hashlib,json,pathlib; p=pathlib.Path("dist/DragonsGateHUD.mpackage"); m=json.loads(pathlib.Path("dist/manifest.json").read_text()); assert hashlib.sha256(p.read_bytes()).hexdigest()==m["sha256"]'
```

Expected: zero Lua failures, Python build test PASS, successful package build, clean diff check, and matching package checksum.

- [ ] **Step 6: Commit the release candidate**

```bash
git add tests/lua/test_mapper_acceptance.lua README.md docs/MUDLET_ACCEPTANCE.md src/defaults.lua
git commit -m "docs: finalize special submap mapper release"
```

- [ ] **Step 7: Request code review and resolve findings test-first**

Use `superpowers:requesting-code-review`. For each valid finding, add or strengthen a failing test, implement the correction, rerun the full suite, and commit the focused fix. Do not merge or tag with unresolved correctness or ownership findings.

- [ ] **Step 8: Publish and verify GitHub assets**

After the branch is integrated into `main`, create the resolved annotated version tag, push `main` and the tag, wait for the release workflow, download `DragonsGateHUD.mpackage` and `manifest.json`, and independently verify version, byte count, and SHA-256.

- [ ] **Step 9: Perform live disposable-profile acceptance**

Use `dghud update` in `Dragons Gate HUD` only after the release asset is verified. Test door/gate sub-map creation, directional continuation, observed reverse travel, canonical room revisit, all three map controls, full-screen/windowed resizing, and a mixed `walkto` route. Record any live mismatch as a new failing automated test before correcting it. Do not modify unrelated profiles or personal Mudlet content.
