# Persistent Top Chatbox Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an always-visible responsive chatbox above the main console that captures approved Dragons Gate communication, saves it indefinitely per character, and accepts future personal-trigger captures through `DGHUD.chat.capture()`.

**Architecture:** Pure Lua modules parse and model chat entries independently from Mudlet. A storage adapter owns append-only JSONL files and bounded history loading. A chat controller connects one owned line trigger and the public API to a responsive Geyser chat view aligned exactly with the center console.

**Tech Stack:** Lua 5.1, Mudlet 5.0.0, Geyser containers/labels/mini-console, JSONL through Mudlet yajl, existing Lua test harness, Python package builder, GitHub Actions releases.

**Spec:** `docs/superpowers/specs/2026-08-31-top-chatbox-design.md`

## Global Constraints

- Chatbox is always visible at the top center and exactly matches main-console width.
- Target height is 240 px, percentage-scaled and clamped between configured minimum and maximum.
- Original game output remains visible in the main console.
- Captured history is retained indefinitely in per-character, per-date JSONL files.
- Visible history is bounded to the newest 1,000 entries.
- Built-in parsing is anchored to approved formats and must reject misleading NPC/system narration.
- Adjacent identical entries are deduplicated within the configured time window.
- `DGHUD.chat.capture(category,text[,metadata])` remains stable for personal triggers.
- Updates never alter personal triggers or delete chat logs.
- Automapper implementation remains paused until chatbox acceptance is complete.

---

### Task 1: Strict Chat Parser and Entry Model

**Files:**
- Create: `src/chat_parser.lua`
- Create: `tests/lua/test_chat_parser.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`
- Modify: `src/entry.lua`

**Interfaces:**
- Consumes: raw incoming lines and active character name.
- Produces: `Parser.parse(line,character) -> entry|nil`, `Parser.custom(category,text,metadata,character,now) -> entry|nil,error`, and `Parser.category(value) -> safeCategory|nil`.
- Entry fields: `schema`, `timestamp`, `character`, `category`, `speaker`, `target`, `language`, `message`, `line`, `source`.

- [ ] **Step 1: Write failing tests for every supplied format**

```lua
local Parser=require("chat_parser")
test("parses room speech target and verb",function()
  local e=assert(Parser.parse('Ocinaiya says to Suupidosutaa, "Especially you."',"Dace Alterac"))
  eq(e.category,"ROOM"); eq(e.speaker,"Ocinaiya"); eq(e.target,"Suupidosutaa"); eq(e.message,"Especially you.")
end)
test("parses private and mental channels",function()
  eq(assert(Parser.parse('Tekk (ESP): "ahhh and she returns"')).category,"ESP")
  eq(assert(Parser.parse('You pick up Losmir\'s mental link, "dragon door... is unlocked"')).category,"DRAGON")
  eq(assert(Parser.parse('You pick up Faolann\'s thoughts echoing through the area, "leave me be"')).category,"CONTACT")
end)
test("rejects misleading narration",function()
  eq(Parser.parse("The teller whispers to you about opening an account."),nil)
end)
```

Include the exact ROOM, OWN, WHISPER, ESP, DRAGON, CONTACT, ELDER, and GUIDE examples from the specification. Test optional `to <target>` and `in <language>` clauses, ANSI removal, malformed quotes, empty text, and safe custom categories.

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because `chat_parser` cannot be required.

- [ ] **Step 3: Implement anchored parser rules**

```lua
local rules={
  {category="ESP",pattern='^([%w_%-%\']+) %(ESP%): "(.*)"$'},
  {category="STAFF",pattern='^([%w_%-%\']+) %(ELDER%): "(.*)"$'},
  {category="STAFF",pattern='^%[GUIDE%] ([%w_%-%\']+): (.+)$'},
}
function Parser.category(value)
  value=tostring(value or ""):upper():match("^%s*(.-)%s*$")
  return value:match("^[A-Z][A-Z0-9_%-]*$") and value or nil
end
```

Use ordered rules so specific ESP/mental/staff formats run before ROOM speech. Normalize ANSI away before matching. Build entries through one constructor that omits missing metadata and marks built-ins with `source="builtin"`.

- [ ] **Step 4: Register module and run verification**

Add `chat_parser` to package module lists and `test_chat_parser.lua` to `tests/run.lua`.

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v`

Expected: all tests PASS.

- [ ] **Step 5: Commit**

```bash
git add src/chat_parser.lua tests/lua/test_chat_parser.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: parse Dragons Gate chat channels"
```

---

### Task 2: Deduplication, Bounded History, and Permanent JSONL Storage

**Files:**
- Create: `src/chat_history.lua`
- Create: `src/chat_storage.lua`
- Create: `tests/lua/test_chat_history.lua`
- Create: `tests/lua/test_chat_storage.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`
- Modify: `src/entry.lua`

**Interfaces:**
- Produces `History.new(limit,dedupeSeconds)`, `:append(entry,epoch) -> added`, `:entries(filter)`, and `:categories()`.
- Produces `Storage.new(api,basePath,visibleLimit)`, `:append(entry)`, `:loadRecent(character) -> entries`, `Storage.safeCharacter(name)`, and `:close()`.
- Storage API dependency: `mkdir(path)`, `append(path,text)`, `list(path)`, `read(path)`, `encode(table)`, `decode(line)`.

- [ ] **Step 1: Write failing history tests**

```lua
test("deduplicates only identical adjacent entries",function()
  local h=History.new(1000,3); local e={category="ESP",speaker="Tekk",message="hello"}
  eq(h:append(e,100),true); eq(h:append(e,101),false)
  eq(h:append({category="ESP",speaker="Gia",message="hello"},102),true)
end)
test("retains only the newest visible limit",function()
  local h=History.new(2,3); h:append({category="ROOM",message="one"},1); h:append({category="ROOM",message="two"},2); h:append({category="ROOM",message="three"},3)
  eq(#h:entries("ALL"),2); eq(h:entries("ALL")[1].message,"two")
end)
```

- [ ] **Step 2: Write failing storage tests**

```lua
test("sanitizes character paths and appends dated JSONL",function()
  local api=fakeStorageApi(); local storage=Storage.new(api,"/profile/DragonsGateHUD/chat",1000)
  storage:append({timestamp="2026-08-31T13:00:00-04:00",character="Dace/Alterac",category="ROOM",message="hello"})
  eq(api.lastPath,"/profile/DragonsGateHUD/chat/dace_alterac/2026-08-31.jsonl")
end)
test("skips malformed JSONL while loading later entries",function()
  local api=fakeStorageApiWithLines({'not json','{"category":"ESP","message":"valid"}'})
  local entries=Storage.new(api,"/chat",1000):loadRecent("Dace Alterac"); eq(#entries,1); eq(entries[1].message,"valid")
end)
```

- [ ] **Step 3: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because history and storage modules are missing.

- [ ] **Step 4: Implement bounded model and append-only storage**

History computes a dedupe key from category, speaker, target, and message. `PRIVATE` returns WHISPER, ESP, DRAGON, and CONTACT; `ALL` returns all entries. Storage lowercases and replaces unsafe filename characters, derives the date from the entry timestamp, appends one encoded object plus newline, and reads newest dated files first until `visibleLimit` valid entries are collected.

- [ ] **Step 5: Add Mudlet storage API factory**

Wrap `lfs.mkdir`, `io.open` append/read, `yajl.to_string`, and `yajl.to_value`. Create directories one segment at a time beneath `getMudletHomeDir().."/DragonsGateHUD/chat"`. Never accept user-controlled absolute or parent paths.

- [ ] **Step 6: Register, verify, and commit**

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v && git diff --check`

```bash
git add src/chat_history.lua src/chat_storage.lua tests/lua/test_chat_history.lua tests/lua/test_chat_storage.lua tests/run.lua scripts/build.py src/entry.lua
git commit -m "feat: persist bounded chat history"
```

---

### Task 3: Chat Controller and Stable Personal-Trigger API

**Files:**
- Create: `src/chat_controller.lua`
- Create: `tests/lua/test_chat_controller.lua`
- Modify: `src/main.lua`
- Modify: `src/mudlet_adapter.lua`
- Modify: `src/entry.lua`
- Modify: `tests/lua/test_runtime.lua`
- Modify: `tests/run.lua`
- Modify: `scripts/build.py`

**Interfaces:**
- Produces `ChatController.new(adapter,parser,history,storage,onChange,characterProvider)`, `:start()`, `:onLine(line)`, `:capture(category,text,metadata)`, `:setFilter(filter)`, `:entries()`, and `:shutdown()`.
- Public API: `DGHUD.chat.capture(category,text[,metadata]) -> true|nil,error` and `DGHUD.chat.setFilter(category)`.

- [ ] **Step 1: Write failing controller tests**

```lua
test("one owned line trigger captures and persists recognized chat",function()
  local f=fake(); local controller=makeController(f); controller:start(); f:line('Tekk (ESP): "hello"')
  eq(controller:entries()[1].category,"ESP"); eq(f.storageAppends,1); eq(f:count(f.triggers),1)
end)
test("custom API creates a filter without editing HUD triggers",function()
  local controller=makeController(fake()); controller:start(); assert(controller:capture("QUEST","The quest begins."))
  eq(controller:entries()[1].source,"custom"); eq(controller.history:categories()[1],"QUEST")
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because `chat_controller` is missing.

- [ ] **Step 3: Implement one capture pipeline**

```lua
function Controller:accept(entry)
  local added=self.history:append(entry,self.adapter:epoch())
  if not added then return false end
  local ok,err=self.storage:append(entry)
  if not ok then self.adapter:reportChatErrorOnce(err) end
  self.onChange(self:entries(),self.history:categories()); return true
end
function Controller:onLine(line)
  local entry=self.parser.parse(line,self.characterProvider(),self.adapter:timestamp())
  if entry then return self:accept(entry) end
end
```

Load recent entries once on start. Rotate subsequent storage automatically when `characterProvider()` changes. Storage failure reports once and does not stop in-memory capture.

- [ ] **Step 4: Wire lifecycle and stable API**

Create the controller during `Main:start` and shut it down before deleting the view. Expose `DGHUD.chat.capture` and `setFilter` as wrappers that resolve the current controller each call, preventing stale references after update/reload. During shutdown return `nil,"chatbox is not running"`.

- [ ] **Step 5: Verify isolation and reload behavior**

Extend runtime tests to assert one owned chat trigger after reload, no owned chat runtime after shutdown, callable API after reload, and no changes to unrelated fake triggers or files.

Run: `lua tests/run.lua && python3 -m unittest tests/test_build.py -v`

- [ ] **Step 6: Commit**

```bash
git add src/chat_controller.lua src/main.lua src/mudlet_adapter.lua src/entry.lua tests/lua/test_chat_controller.lua tests/lua/test_runtime.lua tests/run.lua scripts/build.py
git commit -m "feat: expose persistent chat capture API"
```

---

### Task 4: Responsive Always-Visible Top-Center Chatbox

**Files:**
- Modify: `src/layout.lua`
- Modify: `src/view.lua`
- Modify: `src/main.lua`
- Modify: `tests/lua/test_layout.lua`
- Modify: `tests/lua/test_view.lua`
- Modify: `tests/lua/test_runtime.lua`

**Interfaces:**
- Layout produces `header_height`, `chat_height`, `console_top`, `chat_x`, and `chat_width`.
- View produces `chat_container`, `chat_tabs`, `chat_output`, `:renderChat(entries,categories,activeFilter)`, and `:setChatFilterCallback(fn)`.

- [ ] **Step 1: Write failing geometry tests**

```lua
test("chatbox aligns exactly with center console",function()
  local r=Layout.compute(1920,1080)
  eq(r.chat_x,r.left); eq(r.chat_width,r.console_width); eq(r.chat_height,240)
  eq(r.console_top,r.header_height+r.chat_height); eq(r.top,r.console_top)
end)
test("chat height scales and clamps",function()
  eq(Layout.compute(1200,650).chat_height>=160,true)
  eq(Layout.compute(3840,2160).chat_height<=320,true)
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because chat geometry is absent.

- [ ] **Step 3: Split side-card and console top geometry**

Compute `header_height` using the existing breakpoint header value. Compute chat height from settings percentage, rounded and clamped; the reference 1080-pixel height must yield 240. Set `console_top=header_height+chat_height` and pass it to `setBorderTop`. Continue placing Identity and side cards at `header_height`, not `console_top`.

- [ ] **Step 4: Build the owned chat view**

```lua
self.chat=Geyser.Container:new({name="DGHUD.Chat",x=0,y=0,width=100,height=240},self.root)
self.chat_bg=label("DGHUD.Chat.Background",self.chat,"background:#0d1210;border:1px solid "..t.border..";")
self.chat_tabs=Geyser.Container:new({name="DGHUD.Chat.Tabs",x=0,y=0,width="100%",height=32},self.chat)
self.chat_output=Geyser.MiniConsole:new({name="DGHUD.Chat.Output",x=8,y=36,width="100%-16",height="100%-44"},self.chat)
```

Place the container at `chat_x,header_height,chat_width,chat_height`. Render compact category buttons with deterministic custom-category overflow. Apply channel colors and responsive fonts. Keep timestamps visually muted. Preserve scroll position unless already at the bottom.

- [ ] **Step 5: Wire controller rendering and tab callbacks**

Controller `onChange` calls `View:renderChat`. Tab callbacks call `controller:setFilter(category)` and rerender. Main refreshes chat layout on every window resize without recreating controller history or triggers.

- [ ] **Step 6: Verify every breakpoint**

Run: `lua tests/run.lua`.

Live-resize the disposable profile through approximately `2560x1400`, `1920x1080`, `1200x800`, `1000x650`, and compact width. Confirm the chatbox remains visible, center-aligned, non-overlapping, and the game console remains usable.

- [ ] **Step 7: Commit**

```bash
git add src/layout.lua src/view.lua src/main.lua tests/lua/test_layout.lua tests/lua/test_view.lua tests/lua/test_runtime.lua
git commit -m "feat: add responsive top-center chatbox"
```

---

### Task 5: Settings, Documentation, Live Acceptance, and Release

**Files:**
- Modify: `src/defaults.lua`
- Modify: `src/settings.lua`
- Modify: `README.md`
- Modify: `docs/MUDLET_ACCEPTANCE.md`
- Create: `tests/lua/test_chat_acceptance.lua`
- Modify: `tests/run.lua`

**Interfaces:**
- Settings: `chat.enabled`, `height_percent`, `target_height`, `min_height`, `max_height`, `visible_limit`, `dedupe_seconds`, and `timestamps`.
- Diagnostic alias: `dghud chatstatus` reports active filter, visible count, current character storage key, and last storage error.

- [ ] **Step 1: Write failing settings and end-to-end acceptance tests**

```lua
test("chat settings retain defaults around user overrides",function()
  local merged=Settings.merge(defaults,{chat={height_percent=.25}})
  eq(merged.chat.height_percent,.25); eq(merged.chat.visible_limit,1000); eq(merged.chat.target_height,240)
end)
test("capture reload and shutdown preserve personal runtime",function()
  local f=fakeChatRuntimeWithPersonalTrigger(); local hud=startHud(f); f:line('Tekk (ESP): "hello"'); hud:reload(); eq(f.personalTrigger,true); eq(hud.chat:entries()[1].message,"hello"); hud:shutdown(); eq(f.personalTrigger,true)
end)
```

- [ ] **Step 2: Run tests and verify RED**

Run: `lua tests/run.lua`

Expected: FAIL because settings and acceptance wiring are absent.

- [ ] **Step 3: Add defaults and documentation**

Add the exact settings from the specification. Document filters, permanent local storage path, `DGHUD.chat.capture`, custom-trigger examples, deduplication, indefinite retention, diagnostic alias, and privacy implications of saving private communications locally.

- [ ] **Step 4: Run full repository verification**

```bash
lua tests/run.lua
python3 -m unittest tests/test_build.py -v
git diff --check
```

Expected: zero failures.

- [ ] **Step 5: Perform live disposable-profile acceptance**

Install an unreleased package into `Dragons Gate HUD`. Feed each supplied sample through the real line-capture path, confirm strict filters and deduplication, call `DGHUD.chat.capture("QUEST",line)` from a temporary personal trigger, reload/update/reconnect, inspect dated JSONL persistence, and resize all target layouts. Do not send representational game messages solely for testing; use already observed output or synthetic local lines.

- [ ] **Step 6: Publish through the existing updater**

Bump the patch version, commit source/tests/docs, push `main`, create and push the release tag, wait for GitHub Actions, run `dghud update` in a safe live moment, and repeat chat capture plus resize checks against the published artifact.

- [ ] **Step 7: Commit release-ready documentation**

```bash
git add src/defaults.lua src/settings.lua README.md docs/MUDLET_ACCEPTANCE.md tests/lua/test_chat_acceptance.lua tests/run.lua
git commit -m "docs: finish persistent chatbox acceptance"
```

---

## Final Verification Checklist

- [ ] Every supplied message format enters the correct category.
- [ ] Misleading NPC/system narration is rejected.
- [ ] Adjacent duplicate ESP entries appear once.
- [ ] `DGHUD.chat.capture()` works before and after reload/update.
- [ ] Custom categories become filterable without package edits.
- [ ] Logs append indefinitely under safe per-character/date paths.
- [ ] Only the newest 1,000 valid entries load into memory.
- [ ] Normal game output remains untouched.
- [ ] Chatbox remains always visible, responsive, and exactly center-aligned.
- [ ] Full-screen/restored/compact resizing produces no overlap or black gaps.
- [ ] Unrelated Mudlet triggers, aliases, scripts, packages, maps, and settings remain unchanged.
- [ ] Published release, checksum, health check, and live acceptance all pass.
