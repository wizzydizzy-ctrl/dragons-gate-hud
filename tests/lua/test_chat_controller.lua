local Controller=require("chat_controller")
local Parser=require("chat_parser")
local History=require("chat_history")

local function fake(entries)
  local f={next=0,triggers={},storageAppends=0,storageEntries=entries or {},storedCharacters={},errors=0,epochValue=100,timestampValue="2026-08-31T13:00:00-04:00",character="Dace Alterac",loadRecentCalls=0,loadedCharacterKeys={}}
  function f:addLineTrigger(fn) if self.triggerFailure then error(self.triggerFailure) end; self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
  function f:count(value) local total=0; for _ in pairs(value) do total=total+1 end; return total end
  function f:epoch() return self.epochValue end
  function f:timestamp() return self.timestampValue end
  function f:reportChatErrorOnce() self.errors=self.errors+1 end
  f.storage={}
  function f.storage:characterKey(character)
    local key=tostring(character or ""):lower():gsub("[^a-z0-9_-]+","_"):gsub("_+","_"):gsub("^_+",""):gsub("_+$","")
    return key~="" and key or "unknown"
  end
  function f.storage:loadRecent(character)
    f.loadRecentCalls=f.loadRecentCalls+1
    local key=self:characterKey(character); f.loadedCharacterKeys[#f.loadedCharacterKeys+1]=key
    if f.loadFailure then error(f.loadFailure) end
    if f.storageEntriesByKey then return f.storageEntriesByKey[key] or {} end
    return f.storageEntries
  end
  function f.storage:append(entry)
    f.storageAppends=f.storageAppends+1
    f.storedCharacters[#f.storedCharacters+1]=entry.character
    if f.storageFailure then return nil,"disk full" end
    return true
  end
  return f
end

local function makeController(f,onChange)
  return Controller.new(f,Parser,History.new(1000,3),f.storage,onChange or function() end,function() return f.character end)
end

test("one owned line trigger captures and persists recognized chat",function()
  local f=fake(); local controller=makeController(f); controller:start(); f:line('Tekk (ESP): "hello"')
  eq(controller:entries()[1].category,"ESP"); eq(f.storageAppends,1); eq(f:count(f.triggers),1)
end)

test("does not start when owned trigger registration fails",function()
  local f=fake(); f.triggerFailure="chat trigger registration failed"; local controller=makeController(f)
  local started,err=controller:start(); eq(started,nil); eq(tostring(err):find("chat trigger registration failed",1,true)~=nil,true); eq(controller.started,false); eq(controller.trigger,nil); eq(f:count(f.triggers),0)
end)

test("custom API creates a filter without editing HUD triggers",function()
  local f=fake(); local controller=makeController(f); controller:start(); assert(controller:capture("QUEST","The quest begins."))
  eq(controller:entries()[1].source,"custom"); eq(controller.history:categories()[1],"QUEST"); eq(f:count(f.triggers),1)
end)

test("custom API treats an adjacent duplicate as a successful no-op",function()
  local f=fake(); local controller=makeController(f); controller:start()
  eq(controller:capture("QUEST","The quest begins."),true); eq(controller:capture("QUEST","The quest begins."),true)
  eq(f.storageAppends,1)
end)

test("storage errors report once while in-memory capture continues",function()
  local f=fake(); f.storageFailure=true; local controller=makeController(f); controller:start()
  eq(controller:capture("QUEST","first"),true); f.epochValue=101; eq(controller:capture("QUEST","second"),true)
  eq(#controller:entries(),2); eq(f.storageAppends,2); eq(f.errors,1)
end)

test("reports a startup history failure once and continues capturing",function()
  local f=fake(); f.loadFailure="history read exploded"; local controller=makeController(f)
  eq(controller:start(),true); eq(f.errors,1); eq(f.loadRecentCalls,1); f:line('Tekk (ESP): "hello"'); f.epochValue=104; eq(controller:capture("QUEST","continues"),true)
  eq(#controller:entries(),2); eq(f.storageAppends,2); controller:start(); eq(f.errors,1); eq(f.loadRecentCalls,1)
end)

test("loads recent entries once and rotates later captures to the active character",function()
  local f=fake({{category="ESP",message="earlier",character="Dace Alterac",timestamp="2026-08-31T12:00:00-04:00"}}); local controller=makeController(f)
  controller:start(); eq(controller:entries()[1].message,"earlier")
  assert(controller:capture("QUEST","for Dace")); f.character="Gia"; f.epochValue=104; assert(controller:capture("QUEST","for Gia"))
  eq(f.storedCharacters[1],"Dace Alterac"); eq(f.storedCharacters[2],"Gia")
end)

test("sanitized character transition hydrates history once without re-persisting",function()
  local f=fake(); f.character=nil
  f.storageEntriesByKey={
    unknown={{schema=1,timestamp="2026-08-31T12:00:00-04:00",character="Unknown",category="ROOM",message="unknown recent",line="unknown recent",source="builtin"}},
    dace_alterac={{schema=1,timestamp="2026-08-31T11:00:00-04:00",character="Dace Alterac",category="ESP",message="persisted Dace",line="persisted Dace",source="builtin"}},
  }
  local controller=makeController(f); controller:start(); assert(controller:capture("QUEST","live unknown"))
  eq(f.storageAppends,1); eq(table.concat(f.loadedCharacterKeys,","),"unknown")
  f.character="Dace/Alterac"; assert(controller:syncCharacter())
  local entries=controller:entries()
  eq(table.concat(f.loadedCharacterKeys,","),"unknown,dace_alterac")
  eq(#entries,3); eq(entries[1].message,"persisted Dace"); eq(entries[2].message,"unknown recent"); eq(entries[3].message,"live unknown")
  eq(f.storageAppends,1)
  f.character="Dace Alterac"; assert(controller:syncCharacter())
  eq(table.concat(f.loadedCharacterKeys,","),"unknown,dace_alterac")
end)

test("filter changes notify with only matching entries and shutdown removes its trigger",function()
  local f=fake(); local calls={}; local controller=makeController(f,function(entries,_,filter) calls[#calls+1]={entries=entries,filter=filter} end)
  controller:start(); assert(controller:capture("QUEST","quest")); f.epochValue=104; assert(controller:capture("EVENTS","event")); controller:setFilter("QUEST")
  eq(calls[#calls].filter,"QUEST"); eq(calls[#calls].entries[1].message,"quest"); controller:shutdown(); eq(f:count(f.triggers),0); eq(controller:capture("QUEST","late"),nil)
end)
