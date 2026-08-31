local Main=require("main")
local function fake()
  local f={next=0,killed={},deleted=0,borders={10,20,30,40},set_borders={},callbacks={},layouts={},triggers={},timers={},events={},aliases={}}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders(a,b,c,d) self.set_borders={a,b,c,d} end
  function f:getWindowSize() return self.width or 1920,self.height or 1080 end
  function f:createView() return {
    update=function(self,state) self.state=state end,
    applyLayout=function(self,layout) f.layouts[#f.layouts+1]=layout end,
    renderChat=function(self,entries,categories,filter) f.chatRenders=(f.chatRenders or 0)+1; f.renderedChat={entries=entries,categories=categories,filter=filter} end,
    setChatFilterCallback=function(self,callback) f.chatFilterCallback=callback end,
    delete=function() f.deleted=f.deleted+1 end,
  } end
  function f:addEvent(name,fn) self.next=self.next+1; self.callbacks[name]=fn; local id="event-"..self.next; self.events[id]=name; return id end
  function f:addAlias() self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]=true; return id end
  function f:killEvent(id) self.killed[id]=true; self.events[id]=nil end
  function f:killAlias(id) self.killed[id]=true; self.aliases[id]=nil end
  function f:getGMCP() return {Char={Vitals={hp=1,hp_max=1}}} end
  function f:isCharacterActive() return self.character_active==true end
  function f:addLineTrigger(fn)
    self.lineTriggerCalls=(self.lineTriggerCalls or 0)+1
    if self.failChatTrigger and self.lineTriggerCalls==2 then error("chat trigger registration failed") end
    self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id
  end
  function f:killTrigger(id) self.killed[id]=true; self.triggers[id]=nil end
  function f:epoch() return self.epochValue or 100 end
  function f:timestamp() return self.timestampValue or "2026-08-31T13:00:00-04:00" end
  function f:reportChatErrorOnce() self.chatErrors=(self.chatErrors or 0)+1 end
  function f:createChatStorage()
    f.chatEntries=f.chatEntries or {}; local storage={entries=f.chatEntries}
    function storage:loadRecent() f.loadRecentCalls=(f.loadRecentCalls or 0)+1; return self.entries end
    function storage:append(entry) self.entries[#self.entries+1]=entry; return true end
    function storage:close() if f.onStorageClose then f.onStorageClose() end; return true end
    return storage
  end
  function f:schedule(_,fn) self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:fireTimer() local id,fn=next(self.timers); if id then self.timers[id]=nil; fn() end end
  function f:sendCommand(command) self.sent=command end
  function f:count(tableValue) local n=0; for _ in pairs(tableValue) do n=n+1 end; return n end
  return f
end
test("startup is idempotent and shutdown owns exact runtime IDs",function()
  local f=fake(); local hud=Main.new(f,{layout={left_width=190,right_width=270}}); eq(hud:start(),true); local first=f.next; eq(hud:start(),true); eq(f.next,first); eq(hud:shutdown(),true); eq(f.deleted,1); eq(f.set_borders[1],0); eq(f.set_borders[2],0); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("health check requires root handlers and an owned chat trigger",function()
  local hud=Main.new(fake(),{layout={left_width=190,right_width=270}}); eq(hud:healthCheck(),nil); hud:start(); eq(hud:healthCheck(),true); hud.chat.trigger=nil; eq(hud:healthCheck(),nil)
end)
test("window resize recomputes absolute borders and view layout",function()
  local f=fake(); f.borders={1290,234,1610,120}; local hud=Main.new(f,{layout={}}); hud:start(); eq(f.layouts[#f.layouts].mode,"wide"); eq(f.set_borders[1],326); eq(f.set_borders[2],314); eq(f.set_borders[3],326); f.width=760; f.height=700; f.callbacks["sysWindowResizeEvent"](); eq(f.layouts[#f.layouts].mode,"compact"); eq(f.set_borders[1],0); eq(f.set_borders[2],276); eq(f.set_borders[3],0); eq(f.set_borders[4],0)
end)
test("chat controller renders through the view and tab callbacks select filters",function()
  local f=fake(); local hud=Main.new(f,{layout={},chat={visible_limit=1000,dedupe_seconds=3}}); hud:start()
  eq(f.renderedChat.filter,"ALL"); eq(type(f.chatFilterCallback),"function")
  assert(hud.chat:capture("QUEST","The quest begins.")); f.chatFilterCallback("QUEST")
  eq(hud.chat.filter,"QUEST"); eq(f.renderedChat.filter,"QUEST"); eq(f.renderedChat.entries[1].message,"The quest begins.")
end)
test("resize preserves chat controller history and trigger ownership",function()
  local f=fake(); local hud=Main.new(f,{layout={},chat={height_percent=.25}}); hud:start(); assert(hud.chat:capture("QUEST","kept"))
  local controller=hud.chat; local trigger=controller.trigger; local runtime=f:count(f.triggers)
  f.width,f.height=1000,650; f.callbacks["sysWindowResizeEvent"]()
  eq(hud.chat,controller); eq(hud.chat.trigger,trigger); eq(f:count(f.triggers),runtime); eq(hud.chat:entries()[1].message,"kept")
  eq(f.layouts[#f.layouts].chat_height>160,true); eq(f.set_borders[2],f.layouts[#f.layouts].console_top)
end)
test("controller merges collector snapshots and removes collector runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud.collector.snapshot.info={attributes={STR="Good"}}; hud:refresh(); eq(hud.last_state.attributes.STR,"Good"); eq(f:count(f.triggers),2); hud:shutdown(); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("startup refreshes command data when installed at an in-game prompt",function()
  local f=fake(); f.character_active=true
  local hud=Main.new(f,{layout={}}); hud:start(); eq(f.sent,"inventory")
end)
test("reload leaves one command collector",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:reload(); eq(f:count(f.triggers),2); local outgoing=0; for _,name in pairs(f.events) do if name=="sysDataSendRequest" then outgoing=outgoing+1 end end; eq(outgoing,1)
end)
test("roundtime counts down once per second and becomes ready",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:onRoundtime(2); eq(hud.last_state.vitals.roundtime,2)
  f:fireTimer(); eq(hud.last_state.vitals.roundtime,1); f:fireTimer(); eq(hud.last_state.vitals.roundtime,0); eq(f:count(f.timers),0)
end)
test("repeated resize changes typography without growing runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); local runtime=f:count(f.events)+f:count(f.triggers)+f:count(f.aliases)
  for _,size in ipairs({{2056,1177},{1200,800},{760,700},{3840,2160},{1200,800}}) do
    f.width,f.height=size[1],size[2]; f.callbacks["sysWindowResizeEvent"](); local r=f.layouts[#f.layouts]
    eq(r.inventory_row_height>=r.inventory_font+8,true); eq(r.details_line_height>=r.body_font+4,true); eq(r.console_width>=size[1]*.66,true); eq(f:count(f.events)+f:count(f.triggers)+f:count(f.aliases),runtime)
  end
end)
test("chat trigger registration failure rolls back partial HUD runtime",function()
  local f=fake(); f.failChatTrigger=true; local hud=Main.new(f,{layout={}}); local started,err=hud:start()
  eq(started,nil); eq(tostring(err):find("chat trigger registration failed",1,true)~=nil,true); eq(hud.started,false); eq(hud.chat,nil); eq(hud:healthCheck(),nil)
  eq(f.deleted,1); eq(f:count(f.triggers),0); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.timers),0)
end)
test("chat runtime has one owned trigger and cached personal API survives reload safely",function()
  local f=fake(); local unrelated=f:addLineTrigger(function() end); local hud=Main.new(f,{layout={}}); hud:start()
  eq(hud.chat.started,true); eq(f:count(f.triggers),3)
  DGHUD={controller=hud}; Main.installChatApi(DGHUD); local capture=DGHUD.chat.capture
  assert(capture("QUEST","before reload")); hud:reload(); DGHUD={controller=hud}; Main.installChatApi(DGHUD)
  eq(f:count(f.triggers),3); eq(f.loadRecentCalls,2); eq(#hud.chat:entries(),1); eq(hud.chat:entries()[1].message,"before reload")
  assert(capture("QUEST","after reload")); eq(#hud.chat:entries(),2); eq(hud.chat:entries()[2].message,"after reload")
  hud:shutdown(); eq(f:count(f.triggers),1); eq(f.triggers[unrelated]~=nil,true)
  local result,err=capture("QUEST","during shutdown"); eq(result,nil); eq(err,"chatbox is not running"); DGHUD=nil
end)
test("public capture fails while storage cleanup is re-entrant",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); DGHUD={controller=hud}; Main.installChatApi(DGHUD); local capture=DGHUD.chat.capture
  f.onStorageClose=function() f.reentrantResult,f.reentrantError=capture("QUEST","during close") end
  hud:shutdown(); eq(f.reentrantResult,nil); eq(f.reentrantError,"chatbox is not running"); eq(#f.chatEntries,0); DGHUD=nil
end)
