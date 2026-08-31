# Hybrid Character Data HUD Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Merge GMCP with captured `inventory`, `stat`, and `info` output and render responsive identity, combat, equipment, inventory, and compass panels.

**Architecture:** Pure parsers produce command snapshots; a package-owned collector sequences startup commands and captures manual refreshes; `state.lua` merges GMCP-first data into one view model. Geyser consumes that model and recalculates bounded fonts and content-derived geometry on every resize.

**Tech Stack:** Lua 5.1, Mudlet 5.0, Geyser, GMCP, temporary Mudlet triggers/events/timers, Python package builder, GitHub Actions

**Spec:** `docs/superpowers/specs/2026-08-31-hybrid-character-data-design.md`

## Global Constraints

- Own and remove every HUD trigger, event, timer, alias, and widget.
- Never alter unrelated Mudlet content or preferences.
- Prefer valid GMCP fields; use parsed output only as fallback.
- Run the three startup commands once per character-entry session, sequentially, without polling.
- Preserve a 64-percent main-console width and readable minimum fonts.

---

### Task 1: Pure command parsers

**Files:** Create `src/command_parser.lua`, `tests/lua/test_command_parser.lua`; modify `tests/run.lua`, `scripts/build.py`, `src/entry.lua`.

**Interfaces:** Produce `parseInventory(lines)`, `parseStat(lines)`, `parseInfo(lines)`, and `isComplete(command, lines)`.

- [ ] **Step 1: Write failing captured-output tests**

```lua
local Parser=require("command_parser")
test("parses inventory without merging duplicate names",function()
  local r=assert(Parser.parseInventory({"Items carried:","  A torch [1.0 lb].","  A torch [0.1 lbs].","Your inventory totals 1.1 lbs."}))
  eq(#r.items,2); eq(r.items[2].weight,0.1); eq(r.total_weight,1.1)
end)
test("parses stat combat and exact equipment",function()
  local r=assert(Parser.parseStat({"Body Armor: 4%.","OR:  18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","You are still protected by the 80 hour novice protection.","::: Equipment Readied :::","  A simple spear.",">"}))
  eq(r.body_armor,4); eq(r.or_rating,18); eq(r.stance,"Aggressive"); eq(r.equipment[1],"A simple spear")
end)
test("parses physical data and eleven attributes",function()
  local r=assert(Parser.parseInfo({"You are Test Tester, a stocky bodied 28 year old Entropic Male young Monitanian. You are 6'10\" and weigh 309 lbs.","Str Int Wis Dex Agi Con Cha Wil Voi Per App","Good Low Fair Fair Fair Good Good Good Aver Fair Fair",">"}))
  eq(r.physical.age,28); eq(r.physical.sex,"Male"); eq(r.attributes.STR,"Good"); eq(r.attributes.APP,"Fair")
end)
test("incomplete responses do not parse",function() eq(Parser.parseInventory({"Items carried:"}),nil) end)
```

- [ ] **Step 2: Run `lua tests/run.lua` and verify RED** — missing `command_parser`.

- [ ] **Step 3: Implement ANSI stripping, anchored command matches, ordered item/equipment arrays, attribute mapping, and explicit terminators.**

```lua
function Parser.isComplete(command,lines)
  local fn={inventory=Parser.parseInventory,stat=Parser.parseStat,info=Parser.parseInfo}
  return fn[command] and fn[command](lines)~=nil or false
end
```

- [ ] **Step 4: Register the module in test/build/entry lists; run `lua tests/run.lua && python3 -m unittest tests.test_build -v`; verify PASS.**

- [ ] **Step 5: Commit**

```bash
git add src/command_parser.lua tests/lua/test_command_parser.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: parse Dragons Gate character commands"
```

### Task 2: Source-neutral merged state

**Files:** Modify `src/state.lua`, `tests/lua/test_state.lua`.

**Interfaces:** Change to `State.normalize(gmcp_source, command_snapshot)`; add `character.physical/religion/deity`, `attributes`, `combat`, `equipment.items`, and `inventory`.

- [ ] **Step 1: Write failing precedence tests**

```lua
test("GMCP wins and parsed output fills absent fields",function()
  local r=State.normalize({Char={Status={name="Live"}}},{info={character={name="Parsed"},physical={age=28},attributes={STR="Good"}},stat={stance="Aggressive",equipment={"Spear"}},inventory={items={{name="Torch",weight=1}},total_weight=1}})
  eq(r.character.name,"Live"); eq(r.character.physical.age,28); eq(r.attributes.STR,"Good")
  eq(r.combat.stance,"Aggressive"); eq(r.equipment.items[1],"Spear"); eq(r.inventory.total_weight,1)
end)
test("unknown parsed values remain absent",function() local r=State.normalize({},{}); eq(r.combat.body_armor,nil); eq(r.character.deity,nil) end)
```

- [ ] **Step 2: Run tests and verify RED** — new sections are absent.
- [ ] **Step 3: Construct fresh merged tables; never mutate GMCP or snapshots; preserve existing numeric normalization.**
- [ ] **Step 4: Run `lua tests/run.lua`; verify PASS; commit.**

```bash
git add src/state.lua tests/lua/test_state.lua
git commit -m "feat: merge command data into HUD state"
```

### Task 3: Command collector and adapter lifecycle

**Files:** Create `src/command_collector.lua`, `tests/lua/test_command_collector.lua`; modify `src/mudlet_adapter.lua`, `tests/run.lua`, `scripts/build.py`, `src/entry.lua`.

**Interfaces:** Adapter adds `addLineTrigger`, `killTrigger`, `schedule`, `cancelTimer`, `sendCommand`; collector exposes `new(adapter,parser,onChange)`, `start`, `shutdown`, `snapshot`.

- [ ] **Step 1: Write failing sequence/lifecycle tests**

```lua
test("refreshes once and sequentially after entry",function()
  local f=fakeCollectorAdapter(); local c=Collector.new(f,Parser,function() end); c:start()
  f:line("Welcome to Dragon's Gate, Test!"); eq(f.sent[1],"inventory"); eq(#f.sent,1)
  f:lines(inventoryLines); eq(f.sent[2],"stat"); f:lines(statLines); eq(f.sent[3],"info")
  f:lines(infoLines); f:line("Welcome to Dragon's Gate, Test!"); eq(#f.sent,3)
end)
test("manual commands refresh and shutdown leaks nothing",function()
  local f=fakeCollectorAdapter(); local c=Collector.new(f,Parser,function() end); c:start()
  f:outgoing("inventory"); f:lines(inventoryLines); eq(c.snapshot.inventory.total_weight,15.9)
  c:shutdown(); eq(f:ownedCount(),0)
end)
test("timeout retains old data and advances startup",function()
  local f=fakeCollectorAdapter(); local c=Collector.new(f,Parser,function() end); c.snapshot.inventory={total_weight=7}; c:start()
  f:line("Welcome to Dragon's Gate, Test!"); f:fireTimer(); eq(c.snapshot.inventory.total_weight,7); eq(f.sent[2],"stat")
end)
```

- [ ] **Step 2: Run tests and verify RED** — collector missing.
- [ ] **Step 3: Implement `sequence={"inventory","stat","info"}`, one active line buffer, a five-second timer, `sysDataSendRequest` manual detection, and disconnect reset. Parse via `pcall`; replace only complete valid snapshots.**
- [ ] **Step 4: Add adapter wrappers using `tempRegexTrigger("^.*$")`, `tempTimer`, `send`, and matching kill APIs. Collector records and removes all returned IDs.**
- [ ] **Step 5: Register modules; run Lua/build tests; verify PASS; commit.**

```bash
git add src/command_collector.lua src/mudlet_adapter.lua tests/lua/test_command_collector.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: collect character commands once per session"
```

### Task 4: Controller integration

**Files:** Modify `src/main.lua`, `tests/lua/test_runtime.lua`.

**Interfaces:** Controller owns one collector and calls `State.normalize(adapter:getGMCP(), collector.snapshot)`.

- [ ] **Step 1: Write failing tests that collector data reaches `last_state`, reload leaves one line trigger/outgoing handler, shutdown leaves none, and health requires a running collector.**
- [ ] **Step 2: Run tests and verify RED.**
- [ ] **Step 3: Create/start collector before initial refresh; call refresh from `onChange`; stop collector before view deletion.**

```lua
function Main:refresh()
  local snapshot=self.collector and self.collector.snapshot or {}
  local normalized=State.normalize(self.adapter:getGMCP(),snapshot)
  self.view:update(normalized); self.last_state=normalized; return true
end
```

- [ ] **Step 4: Run `lua tests/run.lua`; verify PASS; commit.**

```bash
git add src/main.lua tests/lua/test_runtime.lua
git commit -m "feat: integrate command collection lifecycle"
```

### Task 5: Responsive character, combat, equipment, wealth, and inventory cards

**Files:** Modify `src/view.lua`, `src/layout.lua`, `tests/lua/test_view.lua`, `tests/lua/test_layout.lua`.

**Interfaces:** Add pure content helpers `headerContent`, `detailsContent`, `wealthContent`, `inventoryRows`; layout adds bounded fonts and derived row/card metrics.

- [ ] **Step 1: Write failing view tests**

```lua
test("visible header removes protocol wording",function() local h=View.headerContent(layout,theme); eq(h:find("GMCP",1,true),nil); eq(h:find("● LIVE",1,true)~=nil,true) end)
test("inventory truncates on complete rows",function()
  local r=View.inventoryRows({{name="One"},{name="Two"},{name="Three"}},2)
  eq(r[1].name,"One"); eq(r[2].label,"+2 more")
end)
```

- [ ] **Step 2: Write failing metric tests across 760×700, 1200×800, 2056×1177, and 3840×2160. Assert `row_height >= font+8`, details line height, gauge fit, bounded fonts, and 64-percent console width.**
- [ ] **Step 3: Run tests and verify RED.**
- [ ] **Step 4: Implement responsive metrics**

```lua
layout.inventory_font=clamp(layout.body_font-2,14,20)
layout.inventory_row_height=layout.inventory_font+10
layout.compass_font=clamp(layout.body_font,16,22)
layout.compass_cell=layout.compass_font+14
layout.utility_font=clamp(layout.body_font-4,12,18)
layout.utility_height=layout.utility_font+12
layout.details_line_height=layout.body_font+6
```

- [ ] **Step 5: Create independent Details, Equipment, Wealth, and Inventory widgets. Prefer exact equipment names; retain readiness fallback. Calculate inventory capacity from remaining height and render whole rows plus `+N more`. Header says `● LIVE`.**
- [ ] **Step 6: Run tests; verify PASS; commit.**

```bash
git add src/view.lua src/layout.lua tests/lua/test_view.lua tests/lua/test_layout.lua
git commit -m "feat: add responsive character and inventory cards"
```

### Task 6: Compass and utility navigation

**Files:** Create `src/navigation.lua`, `tests/lua/test_navigation.lua`; modify `src/view.lua`, `tests/lua/test_view.lua`, `tests/run.lua`, `scripts/build.py`, `src/entry.lua`.

**Interfaces:** Produce `Navigation.availability(exits)`, eight direction records with row/column/command, and four utility records.

- [ ] **Step 1: Write failing normalization tests for full names and `n/ne/e/se/s/sw/w/nw`; assert utilities send exactly `go portal`, `go door`, `go gate`, `go arch`.**
- [ ] **Step 2: Run tests and verify RED.**
- [ ] **Step 3: Implement canonical direction records and case-insensitive aliases; ignore up/down/in/out for compass availability.**
- [ ] **Step 4: Write failing fake-callback tests: bright available east sends `east`; dim unavailable north has no callback; utilities send exact commands.**
- [ ] **Step 5: Replace dynamic exits with fixed 3×3 compass, decorative center, and utility row. Reuse widgets on updates; hide in compact mode; retain textual all-exit summary.**
- [ ] **Step 6: Register module; run Lua/build tests; verify PASS; commit.**

```bash
git add src/navigation.lua src/view.lua tests/lua/test_navigation.lua tests/lua/test_view.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: add compass and utility navigation"
```

### Task 7: Repeated resize and live-acceptance regression

**Files:** Modify `tests/lua/test_runtime.lua`, `tests/lua/test_layout.lua`, `docs/MUDLET_ACCEPTANCE.md`.

**Interfaces:** Verify complete HUD behavior and lifecycle.

- [ ] **Step 1: Add a repeated-resize test cycling wide → medium → compact → 4K → medium. Assert fonts/row heights recompute, console remains ≥64%, and owned runtime counts never grow.**
- [ ] **Step 2: Run tests; if geometry is fixed, verify RED and route it through `Layout.compute`; rerun until PASS.**
- [ ] **Step 3: Document live checks: one startup sequence, matching parsed values, manual refreshes, bright/dim compass behavior, utility commands in disposable context, resize transitions, health check, and unchanged unrelated packages.**
- [ ] **Step 4: Run `lua tests/run.lua && python3 -m unittest tests.test_build -v && git diff --check`; verify zero failures; commit.**

```bash
git add tests/lua/test_runtime.lua tests/lua/test_layout.lua docs/MUDLET_ACCEPTANCE.md
git commit -m "test: verify responsive hybrid HUD lifecycle"
```

### Task 8: Release and live Mudlet verification

**Files:** Modify `src/defaults.lua`.

**Interfaces:** Produce the next semantic patch release and update only the disposable `Dragons Gate HUD` profile.

- [ ] **Step 1: Select the next unused patch version and update `src/defaults.lua`.**
- [ ] **Step 2: Run full Lua/build/diff verification and commit `release: prepare hybrid character HUD`.**
- [ ] **Step 3: Push `main`, tag the exact version, and push the tag. Let GitHub Actions alone publish assets.**
- [ ] **Step 4: Wait for the release run; download both assets to a temporary directory; verify package SHA-256 equals the manifest.**
- [ ] **Step 5: Run `dghud update`, wait for the installed-version message, enter the character, and execute the acceptance checklist at wide, medium, compact, and restored sizes.**
- [ ] **Step 6: Run final tests and require an empty `git status --short`.**

