# Embedded Automapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent native Mudlet automapper embedded immediately above the HUD compass, with automatic standard-exit discovery, clickable destinations, and safe `walkto <room number>` navigation.

**Architecture:** Pure Lua model modules normalize GMCP rooms, plan coordinates, and control one-step walking without calling Mudlet globals. A focused Mudlet map adapter owns all native mapper API calls and enforces room ownership. `Main` wires GMCP, outgoing movement, layout, and lifecycle events into those modules while `View` embeds a `Geyser.Mapper` directly above the compass.

**Tech Stack:** Lua 5.1, Mudlet 5.0.0, GMCP, Mudlet mapper APIs, Geyser.Mapper, existing Lua test harness, Python package builder, GitHub Actions releases.

**Spec:** `docs/superpowers/specs/2026-08-31-embedded-automapper-design.md`

## Global Constraints

- The embedded map sits immediately above the compass direction pad in the lower-left navigation stack.
- The first mapper release supports only north, northeast, east, southeast, south, southwest, west, northwest, up, down, in, and out.
- Dragons Gate `gmcp.Room.Info.num` is the canonical game room identifier.
- Existing unowned Mudlet rooms are never deleted or silently rewritten.
- Automatic special-exit traversal is disabled in the first release.
- Walking sends one step at a time and waits for the expected GMCP room number.
- HUD update and uninstall preserve discovered map data.
- All runtime objects and aliases are owned by `DragonsGateHUD`; unrelated Mudlet content remains untouched.
- Every production change follows red-green-refactor and the full suite must remain green.

---

### Task 1: Pure Room and Direction Model

**Files:**
- Create: `src/mapper_model.lua`
- Create: `tests/lua/test_mapper_model.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`
- Modify: `src/entry.lua`

**Interfaces:**
- Consumes: raw `gmcp.Room.Info` tables and optional origin coordinates.
- Produces: `Model.normalizeRoom(info) -> room|nil,error`, `Model.direction(command) -> canonical|nil`, `Model.opposite(direction) -> direction|nil`, `Model.destination(origin,direction) -> {x,y,z}`, and `Model.nearestFree(desired,isOccupied) -> {x,y,z}`.

- [ ] **Step 1: Write failing normalization and direction tests**

```lua
local Model=require("mapper_model")
test("normalizes a Dragons Gate room",function()
  local room=assert(Model.normalizeRoom({num=176,name="Training square.",area=1,environment="Plains/Grasslands",exits={"northeast"},flags={"indoor"}}))
  eq(room.id,176); eq(room.area_key,"1"); eq(room.exits[1],"ne")
end)
test("maps directions coordinates and opposites",function()
  eq(Model.direction("northeast"),"ne"); eq(Model.opposite("ne"),"sw")
  local p=Model.destination({x=4,y=7,z=0},"ne"); eq(p.x,5); eq(p.y,8); eq(p.z,0)
end)
test("rejects rooms without positive numeric IDs",function()
  eq(Model.normalizeRoom({name="Unknown"}),nil); eq(Model.normalizeRoom({num=0}),nil)
end)
```

- [ ] **Step 2: Run the test and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because `mapper_model` cannot be required.

- [ ] **Step 3: Implement the minimal pure model**

```lua
local Model={}
local aliases={north="n",n="n",northeast="ne",ne="ne",east="e",e="e",southeast="se",se="se",south="s",s="s",southwest="sw",sw="sw",west="w",w="w",northwest="nw",nw="nw",up="up",u="up",down="down",d="down",["in"]="in",out="out"}
local opposite={n="s",ne="sw",e="w",se="nw",s="n",sw="ne",w="e",nw="se",up="down",down="up",["in"]="out",out="in"}
local vectors={n={0,1,0},ne={1,1,0},e={1,0,0},se={1,-1,0},s={0,-1,0},sw={-1,-1,0},w={-1,0,0},nw={-1,1,0},up={0,0,1},down={0,0,-1},["in"]={0,0,0},out={0,0,0}}
function Model.direction(value) return aliases[tostring(value or ""):lower()] end
function Model.opposite(value) return opposite[Model.direction(value)] end
function Model.destination(origin,direction)
  local v=vectors[Model.direction(direction)]; if not v then return nil end
  return {x=(origin.x or 0)+v[1],y=(origin.y or 0)+v[2],z=(origin.z or 0)+v[3]}
end
```

Implement `normalizeRoom` with copied arrays and `nearestFree` with deterministic rings around the desired coordinate. For `in` and `out`, retain the origin coordinate until the collision resolver chooses a free point.

- [ ] **Step 4: Register the module in package loading**

Add `mapper_model` to `scripts/build.py` `MODULES`, to `src/entry.lua` `moduleNames`, and load `tests/lua/test_mapper_model.lua` from `tests/run.lua`.

- [ ] **Step 5: Run focused and full verification**

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v`

Expected: all tests PASS and the generated package contains `DGHUD Module - mapper_model`.

- [ ] **Step 6: Commit**

```bash
git add src/mapper_model.lua tests/lua/test_mapper_model.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: add automapper room model"
```

---

### Task 2: Owned Mudlet Map Adapter

**Files:**
- Create: `src/map_adapter.lua`
- Create: `tests/lua/test_map_adapter.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`
- Modify: `src/entry.lua`

**Interfaces:**
- Consumes: normalized room records and planned links from `mapper_model`.
- Produces: `MapAdapter.new(api)`, `:ensureRoom(room,coordinates) -> true|nil,error`, `:ensureStub(roomID,direction)`, `:connect(fromID,toID,direction,confirmedReverse)`, `:setCurrent(roomID)`, `:coordinates(roomID)`, `:route(fromID,toID) -> steps|nil,error`, and `:center(roomID)`.
- Ownership key: `dghud.owner=DragonsGateHUD`; schema key: `dghud.mapper_schema=1`.

- [ ] **Step 1: Write failing ownership tests with a fake mapper API**

```lua
local Adapter=require("map_adapter")
test("creates and tags a missing managed room",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom({id=176,name="Training square.",area_key="1",exits={"ne"}},{x=0,y=0,z=0}))
  eq(api.rooms[176].name,"Training square."); eq(api.rooms[176].user["dghud.owner"],"DragonsGateHUD")
end)
test("refuses to rewrite an unowned colliding room ID",function()
  local api=fakeMapApi({[176]={name="Personal room",user={}}}); local map=Adapter.new(api)
  local ok,err=map:ensureRoom({id=176,name="Training square.",area_key="1",exits={}},{x=0,y=0,z=0})
  eq(ok,nil); eq(err,"room 176 is not owned by DragonsGateHUD"); eq(api.rooms[176].name,"Personal room")
end)
```

- [ ] **Step 2: Run the test and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because `map_adapter` does not exist.

- [ ] **Step 3: Implement dependency-injected adapter logic**

```lua
local MapAdapter={}; MapAdapter.__index=MapAdapter
function MapAdapter.new(api) return setmetatable({api=api,owner="DragonsGateHUD",schema="1"},MapAdapter) end
function MapAdapter:isOwned(id) return self.api:getRoomUserData(id,"dghud.owner")==self.owner end
function MapAdapter:ensureRoom(room,coordinates)
  if self.api:roomExists(room.id) and not self:isOwned(room.id) then return nil,"room "..room.id.." is not owned by DragonsGateHUD" end
  if not self.api:roomExists(room.id) then assert(self.api:addRoom(room.id)) end
  self.api:setRoomUserData(room.id,"dghud.owner",self.owner)
  self.api:setRoomUserData(room.id,"dghud.mapper_schema",self.schema)
  self.api:setRoomName(room.id,room.name); self.api:setRoomCoordinates(room.id,coordinates.x,coordinates.y,coordinates.z)
  return true
end
```

Wrap native functions behind an `api` table so tests never call Mudlet globals. Implement managed area creation, environment metadata, flags, stubs, directional links, current-room selection, route calculation, and map refresh. Do not expose deletion in this adapter.

- [ ] **Step 4: Add the production API factory**

`MapAdapter.mudletApi()` wraps `roomExists`, `addRoom`, `addAreaName`, `setRoomArea`, `setRoomName`, `setRoomCoordinates`, `setRoomUserData`, `getRoomUserData`, `setExitStub`, `setExit`, `getRoomCoordinates`, `getRoomsByPosition`, `setRoomIDbyHash`, `centerview`, `getPath`, and `updateMap`. Guard optional functions and return explicit errors instead of throwing when Mudlet lacks a required mapper API.

- [ ] **Step 5: Register, run, and verify**

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v && git diff --check`

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/map_adapter.lua tests/lua/test_map_adapter.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: add owned Mudlet map adapter"
```

---

### Task 3: Automatic Standard-Direction Discovery

**Files:**
- Create: `src/automapper.lua`
- Create: `tests/lua/test_automapper.lua`
- Modify: `src/main.lua`
- Modify: `src/events.lua`
- Modify: `tests/lua/test_runtime.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`
- Modify: `src/entry.lua`

**Interfaces:**
- Consumes: `Model`, a `MapAdapter`, outgoing commands, and normalized `gmcp.Room.Info` records.
- Produces: `Automapper.new(model,map,onStatus)`, `:onOutgoing(command)`, `:onRoom(info)`, `:onWrongDirection(direction)`, `:currentRoom()`, and `:shutdown()`.
- Emits status values `mapped`, `teleport`, `ownership_conflict`, and `invalid_room` through `onStatus(kind,message)`.

- [ ] **Step 1: Write failing exploration tests**

```lua
test("connects only the observed direction and confirmed reverse",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  mapper:onRoom({num=100,name="A",area=1,exits={"north"}})
  mapper:onOutgoing("north")
  mapper:onRoom({num=101,name="B",area=1,exits={"south"}})
  eq(map.links[1].from,100); eq(map.links[1].to,101); eq(map.links[1].direction,"n"); eq(map.links[1].reverse,true)
end)
test("does not invent a link after a teleport",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  mapper:onRoom({num=100,name="A",area=1,exits={"north"}}); mapper:onRoom({num=900,name="Elsewhere",area=2,exits={}})
  eq(#map.links,0); eq(map.current,900)
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because `automapper` is missing.

- [ ] **Step 3: Implement pending movement and room ingestion**

```lua
function Automapper:onOutgoing(command)
  local direction=self.model.direction(command)
  if direction and self.current_id then self.pending={from=self.current_id,direction=direction} end
end
function Automapper:onRoom(raw)
  local room,err=self.model.normalizeRoom(raw); if not room then return nil,err end
  local coordinates=self:coordinatesFor(room)
  local ok,why=self.map:ensureRoom(room,coordinates); if not ok then self.pending=nil; return nil,why end
  if self.pending and self.pending.from~=room.id then
    local reverse=self.model.opposite(self.pending.direction)
    self.map:connect(self.pending.from,room.id,self.pending.direction,contains(room.exits,reverse))
  end
  self.pending=nil; self.current_id=room.id; self.map:setCurrent(room.id); return true
end
```

Create stubs for advertised unexplored exits. Clear pending movement on WrongDir, disconnect, unsupported commands that represent teleport utilities, and shutdown.

- [ ] **Step 4: Wire runtime events without duplicating handlers**

In `Main:start`, create the map adapter and automapper before registering GMCP handlers. Route `gmcp.Room.Info` through `automapper:onRoom(gmcp.Room.Info)` and then perform the normal HUD refresh. Route `sysDataSendRequest` through both the existing collector and `automapper:onOutgoing(command)` using owned handlers. Route `gmcp.Room.WrongDir` and disconnection to the automapper.

- [ ] **Step 5: Verify lifecycle ownership**

Extend `test_runtime.lua` to assert one automapper instance, no duplicated event handlers after reload, no owned timers after shutdown, and preservation of unrelated fake map records.

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v`

Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add src/automapper.lua src/main.lua src/events.lua tests/lua/test_automapper.lua tests/lua/test_runtime.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: discover Dragons Gate rooms from GMCP"
```

---

### Task 4: Embedded Mapper Immediately Above Compass

**Files:**
- Modify: `src/view.lua`
- Modify: `src/layout.lua`
- Modify: `src/mudlet_adapter.lua`
- Modify: `tests/lua/test_layout.lua`
- Modify: `tests/lua/test_view.lua`
- Modify: `tests/lua/test_runtime.lua`

**Interfaces:**
- Consumes: current responsive layout and Mudlet map database populated by Tasks 2–3.
- Produces: `View.mapper`, `layout.lower_mapper_height`, and `View:centerMap(roomID)`.
- Placement invariant: mapper bottom equals compass top minus the standard section gap.

- [ ] **Step 1: Write failing placement tests**

```lua
test("embedded mapper is allocated immediately above compass",function()
  local r=Layout.compute(1920,1080)
  eq(r.lower_mapper_height>=140,true)
  eq(r.lower_mapper_gap,r.lower_row_gap)
end)
test("short windows preserve mapper before optional details",function()
  local r=Layout.compute(1200,650)
  eq(r.lower_mapper_height>=90,true); eq(r.mapper_visible,true)
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because mapper layout metrics do not exist.

- [ ] **Step 3: Add responsive mapper metrics**

Calculate the available left-stack height after gauges, Status, Location, compass, and utility buttons. Allocate a clamped mapper height: wide minimum 140 px, medium/short minimum 90 px, and the remaining available height as the maximum. Set `mapper_visible=false` only in compact mode or when even the minimum cannot fit after reducing optional detail.

- [ ] **Step 4: Create and place the native embedded mapper**

```lua
self.mapper_frame=label("DGHUD.MapperFrame",self.right,"background:#101713;border:1px solid "..t.border..";border-radius:7px;")
self.mapper=Geyser.Mapper:new({name="DGHUD.Mapper",x=4,y=4,width="100%-8",height="100%-8"},self.mapper_frame)
```

Place `mapper_frame` after Location and immediately before `compass_area`. Move compass and utility Y positions downward from the map bottom. Hide both mapper objects in compact mode. Raise interactive map and compass objects after backgrounds. Ensure `View:delete()` recursively removes them through the owned root.

- [ ] **Step 5: Center on GMCP room changes**

Add `Adapter:centerMap(roomID)` and invoke it after `Automapper:onRoom` succeeds. Use native `centerview(roomID)` and `updateMap()` behind the adapter boundary.

- [ ] **Step 6: Test full-screen, restored, short, and compact layouts**

Run: `lua tests/run.lua`

Then use the disposable Mudlet profile to resize through approximately `2560x1400`, `1920x1080`, `1200x800`, `1000x650`, and compact width. Confirm the map remains above the compass and no black gap appears.

- [ ] **Step 7: Commit**

```bash
git add src/view.lua src/layout.lua src/mudlet_adapter.lua tests/lua/test_layout.lua tests/lua/test_view.lua tests/lua/test_runtime.lua
git commit -m "feat: embed responsive mapper above compass"
```

---

### Task 5: Safe One-Step Walker and Room-Number Alias

**Files:**
- Create: `src/map_walker.lua`
- Create: `tests/lua/test_map_walker.lua`
- Modify: `src/automapper.lua`
- Modify: `src/main.lua`
- Modify: `src/events.lua`
- Modify: `tests/lua/test_runtime.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`
- Modify: `src/entry.lua`

**Interfaces:**
- Consumes: `MapAdapter:route(fromID,toID)`, `adapter:sendCommand(command)`, GMCP room arrivals, WrongDir, disconnection, outgoing manual movement, and one-shot timers.
- Produces: `Walker.new(adapter,onStatus)`, `:start(route)`, `:onRoom(roomID)`, `:onWrongDirection()`, `:onManualMovement(command)`, `:stop(reason)`, `:active()`, and `:shutdown()`.
- Route shape: `{rooms={176,177,180},commands={"ne","e"}}`.

- [ ] **Step 1: Write failing one-step and cancellation tests**

```lua
test("walker waits for each expected GMCP room",function()
  local adapter=fakeWalkerAdapter(); local walker=Walker.new(adapter,function() end)
  assert(walker:start({rooms={176,177,180},commands={"ne","e"}})); eq(adapter.sent[1],"ne")
  walker:onRoom(177); eq(adapter.sent[2],"e"); walker:onRoom(180); eq(walker:active(),false)
end)
test("walker stops on unexpected room or wrong direction",function()
  local adapter=fakeWalkerAdapter(); local walker=Walker.new(adapter,function() end)
  walker:start({rooms={1,2},commands={"n"}}); walker:onRoom(99); eq(walker:active(),false); eq(adapter.sent[2],nil)
  walker:start({rooms={99,100},commands={"e"}}); walker:onWrongDirection(); eq(walker:active(),false)
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because `map_walker` is missing.

- [ ] **Step 3: Implement the walker state machine**

```lua
function Walker:sendNext()
  local command=self.route.commands[self.index]
  if not command then return self:stop("arrived") end
  self.expected=self.route.rooms[self.index+1]
  self.adapter:sendCommand(command)
  self.timeout=self.adapter:schedule(12,function() self:stop("movement timed out") end)
end
function Walker:onRoom(roomID)
  if not self.route then return end
  if tonumber(roomID)~=tonumber(self.expected) then return self:stop("unexpected room "..tostring(roomID)) end
  self.adapter:cancelTimer(self.timeout); self.timeout=nil; self.index=self.index+1; self:sendNext()
end
```

Generated movement must be marked so its own outgoing event does not cancel the walker. A different manual standard movement calls `stop("manual movement")`. Roundtime does not trigger another send; only confirmed room arrival advances the route.

- [ ] **Step 4: Add aliases and click integration**

Add owned aliases:

```text
^walkto\s+(\d+)$
^walkstop$
^mapcenter$
```

`walkto` validates the destination, asks `MapAdapter:route(current,destination)`, rejects routes containing unsupported special exits, and starts the walker. Define the Mudlet mapper click hook `doSpeedWalk()` inside the owned package so native clicked destinations are converted from `speedWalkPath` and `speedWalkDir` into the same route shape. Preserve any pre-existing global `doSpeedWalk` reference and restore it on shutdown rather than deleting user code.

- [ ] **Step 5: Wire stop conditions and lifecycle**

Stop on WrongDir, disconnection, ownership conflict, unexpected room, timeout, `walkstop`, package shutdown, and manual directional movement. Report `Walking to 180`, `Arrived at 180`, or `Walk stopped: <reason>` through one concise HUD/console status path.

- [ ] **Step 6: Run complete tests**

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v && git diff --check`

Expected: all tests PASS with no timers, aliases, handlers, or global click hooks left after shutdown.

- [ ] **Step 7: Commit**

```bash
git add src/map_walker.lua src/automapper.lua src/main.lua src/events.lua tests/lua/test_map_walker.lua tests/lua/test_runtime.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: add safe clickable room walking"
```

---

### Task 6: Settings, Diagnostics, Migration, and Live Acceptance

**Files:**
- Modify: `src/defaults.lua`
- Modify: `src/settings.lua`
- Modify: `src/main.lua`
- Modify: `src/view.lua`
- Modify: `README.md`
- Modify: `docs/MUDLET_ACCEPTANCE.md`
- Create: `tests/lua/test_mapper_acceptance.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Consumes: all mapper components from Tasks 1–5.
- Produces settings `mapper.enabled`, `mapper.walk_timeout`, `mapper.minimum_height`, `mapper.schema`; diagnostics command `dghud mapstatus`; and release version bump.

- [ ] **Step 1: Write failing settings and acceptance tests**

```lua
test("mapper settings merge without removing user overrides",function()
  local merged=Settings.merge(defaults,{mapper={walk_timeout=20}})
  eq(merged.mapper.enabled,true); eq(merged.mapper.walk_timeout,20); eq(merged.mapper.schema,1)
end)
test("mapping walking reload and shutdown preserve unrelated state",function()
  local world=fakeMapperWorldWithPersonalRoom(999)
  local hud=startMappedHud(world); walkKnownRoute(hud,176,180); hud:reload(); hud:shutdown()
  eq(world.rooms[999].name,"Personal room"); eq(world.rooms[176].user["dghud.owner"],"DragonsGateHUD"); eq(world:ownedRuntimeCount(),0)
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because mapper settings and diagnostics are absent.

- [ ] **Step 3: Add defaults and status diagnostics**

```lua
mapper={enabled=true,walk_timeout=12,minimum_height=90,schema=1}
```

`dghud mapstatus` prints enabled state, current room ID, managed room count, active destination, and last mapper error without dumping private user data or unrelated map records.

- [ ] **Step 4: Update user and acceptance documentation**

Document embedded placement, automatic standard-direction discovery, click-to-walk, `walkto`, `walkstop`, `mapcenter`, `dghud mapstatus`, ownership behavior, map persistence, and the exclusion of automatic special exits.

- [ ] **Step 5: Run repository verification**

Run:

```bash
lua tests/run.lua
python3 -m unittest tests/test_build.py -v
git diff --check
```

Expected: zero failures and no whitespace errors.

- [ ] **Step 6: Perform live disposable-profile acceptance**

Build an unreleased package, install it only into `Dragons Gate HUD`, and verify all eight acceptance cases in the spec. Use safe training rooms for route tests. Do not run auto-walking while the character is in combat or has an unsent command.

- [ ] **Step 7: Version, publish, update, and re-verify**

Bump the patch version, build with the production owner/repository, commit, push `main`, tag the release, wait for GitHub Actions, run `dghud update`, and repeat mapping plus click/walk acceptance against the published package.

- [ ] **Step 8: Commit documentation and release-ready state**

```bash
git add src/defaults.lua src/settings.lua src/main.lua src/view.lua README.md docs/MUDLET_ACCEPTANCE.md tests/lua/test_mapper_acceptance.lua tests/run.lua
git commit -m "docs: finish embedded automapper acceptance"
```

---

## Final Verification Checklist

- [ ] Every mapper production behavior was introduced by a failing test.
- [ ] The full Lua and Python test suites pass.
- [ ] The embedded map is immediately above the compass at wide, medium, restored, and short heights.
- [ ] Compact mode never obscures the main console or exposes a black gap.
- [ ] Standard exploration creates owned rooms, stubs, and confirmed links without duplication.
- [ ] Teleports and unsupported special exits never invent directional links.
- [ ] Clicking and `walkto <room number>` share the one-step confirmed walker.
- [ ] WrongDir, unexpected rooms, timeout, manual movement, disconnection, and shutdown stop walking.
- [ ] Existing unowned rooms and unrelated Mudlet content remain unchanged.
- [ ] Updating and uninstalling HUD code preserve discovered map data.
- [ ] Published release assets and manifest pass checksum and health checks.
