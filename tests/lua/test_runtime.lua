local Main=require("main")
local MudletAdapter=require("mudlet_adapter")
local MapAdapter=require("map_adapter")
local function fake()
  local f={next=0,killed={},deleted=0,borders={10,20,30,40},set_borders={},callbacks={},layouts={},triggers={},timers={},timer_delays={},timer_cancels={},events={},aliases={}}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders(a,b,c,d) self.set_borders={a,b,c,d} end
  function f:getWindowSize() return self.width or 1920,self.height or 1080 end
  function f:createView() return {
    update=function(self,state) self.state=state end,
    applyLayout=function(self,layout) f.layouts[#f.layouts+1]=layout end,
    renderChat=function(self,entries,categories,filter) f.chatRenders=(f.chatRenders or 0)+1; f.renderedChat={entries=entries,categories=categories,filter=filter} end,
    setChatFilterCallback=function(self,callback) f.chatFilterCallback=callback end,
    setMapCenterCallback=function(self,callback) f.mapCenterCallback=callback end,
    setMapZoomCallback=function(self,callback) f.mapZoomCallback=callback; f.mapZoomCallbackSets=(f.mapZoomCallbackSets or 0)+1 end,
    centerMap=function(self,roomID) f.centeredRooms=f.centeredRooms or {}; f.centeredRooms[#f.centeredRooms+1]=roomID; return true end,
    delete=function() f.deleted=f.deleted+1 end,
  } end
  function f:addEvent(name,fn) self.next=self.next+1; self.callbacks[name]=fn; local id="event-"..self.next; self.events[id]=name; return id end
  function f:addAlias(pattern,fn) self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]={pattern=pattern,fn=fn}; return id end
  function f:killEvent(id) self.killed[id]=true; self.events[id]=nil end
  function f:killAlias(id) self.killed[id]=true; self.aliases[id]=nil end
  function f:getGMCP() return self.gmcp or {Char={Vitals={hp=1,hp_max=1}}} end
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
  function f:createChatStorage(visibleLimit)
    f.chatVisibleLimit=visibleLimit
    f.chatEntries=f.chatEntries or {}; local storage={entries=f.chatEntries}
    function storage:characterKey(character)
      local key=tostring(character or ""):lower():gsub("[^a-z0-9_-]+","_"):gsub("_+","_"):gsub("^_+",""):gsub("_+$","")
      return key~="" and key or "unknown"
    end
    function storage:loadRecent(character)
      f.loadRecentCalls=(f.loadRecentCalls or 0)+1
      local key=self:characterKey(character); f.loadedCharacterKeys=f.loadedCharacterKeys or {}; f.loadedCharacterKeys[#f.loadedCharacterKeys+1]=key
      if f.chatEntriesByKey then return f.chatEntriesByKey[key] or {} end
      return self.entries
    end
    function storage:append(entry) f.chatStorageAppends=(f.chatStorageAppends or 0)+1; self.entries[#self.entries+1]=entry; return true end
    function storage:close() if f.onStorageClose then f.onStorageClose() end; return true end
    return storage
  end
  function f:schedule(delay,fn)
    if self.failSchedule=="return" then return nil,"special schedule failed" end
    if self.failSchedule=="throw" then error("special schedule exploded") end
    self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; self.timer_delays[id]=delay; return id
  end
  function f:cancelTimer(id)
    self.timer_cancels[id]=(self.timer_cancels[id] or 0)+1
    self.timers[id]=nil
    if self.failCancel then error("special cancellation exploded") end
    return true
  end
  function f:fireTimer() local id,fn=next(self.timers); if id then self.timers[id]=nil; fn() end end
  function f:sendCommand(command) self.sent=command; self.sentCommands=self.sentCommands or {}; self.sentCommands[#self.sentCommands+1]=command; return true end
  function f:count(tableValue) local n=0; for _ in pairs(tableValue) do n=n+1 end; return n end
  function f:createMapAdapter()
    local map={rooms={},stubs={},links={},special={},current=nil,shutdowns=0}
    function map:clearOwnedRoomNames() f.mapLabelCleanups=(f.mapLabelCleanups or 0)+1; return 0 end
    function map:ensureRoom(room,coordinates,partition)
      local record=self.rooms[room.id]
      if record then record.room=room else self.rooms[room.id]={room=room,coordinates=coordinates,partition=partition or room.area_key,game_area=room.area_key,owned=true} end
      return true
    end
    function map:ensureStub() return true end
    function map:connect(from,to,direction,reverse) self.links[#self.links+1]={from=from,to=to,direction=direction,reverse=reverse}; return true end
    function map:connectSpecial(from,to,command)
      if f.failSpecialMap=="return" then return nil,"special mapping failed" end
      if f.failSpecialMap=="throw" then error("special mapping exploded") end
      self.special[#self.special+1]={from=from,to=to,command=command}; return true
    end
    function map:setCurrent(id) self.current=id; return self:center(id) end
    function map:center(id) self.centered=id; f.mapCenterCalls=(f.mapCenterCalls or 0)+1; return true end
    function map:zoom(id,action,step,minimum,maximum)
      f.mapZoomCalls=f.mapZoomCalls or {}; f.mapZoomCalls[#f.mapZoomCalls+1]={id,action,step,minimum,maximum}
      if f.zoomError then return nil,f.zoomError end
      return f.zoomResult or 17.5
    end
    function map:coordinates(id) local item=self.rooms[id]; return item and item.coordinates end
    function map:roomRecord(id)
      local record=self.rooms[id]
      if not record then return {exists=false,owned=false,placement_needed=true} end
      return {exists=true,owned=record.owned,coordinates=record.coordinates,partition=record.partition,game_area=record.game_area}
    end
    function map:effectivePartition(id) local record=self.rooms[id]; return record and record.partition end
    function map:roomsAt() return {} end
    function map:isOwned(id) return self.rooms[id]~=nil end
    function map:route(fromID,toID)
      if f.routeError then return nil,f.routeError end
      return f.route or {rooms={fromID,toID},commands={"n"}}
    end
    function map:validateRouteStep(from,to,command)
      for _,exit in ipairs(self.special) do
        if exit.from==from and exit.to==to and exit.command==tostring(command):match("^%s*(.-)%s*$") and self:isOwned(from) and self:isOwned(to) then return true,exit.command end
      end
      return nil,"special exit is not confirmed from "..from.." to "..to
    end
    self.createdMaps=(self.createdMaps or 0)+1; self.map=map; return map
  end
  function f:suppressDefaultMapInfo() self.mapInfoSuppressions=(self.mapInfoSuppressions or 0)+1; return true end
  function f:reportMapperStatus(kind,message) self.mapperStatuses=self.mapperStatuses or {}; self.mapperStatuses[#self.mapperStatuses+1]={kind,message} end
  return f
end

test("startup performs the owned-room label migration once",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start()); eq(f.mapLabelCleanups,1)
end)
test("startup suppresses only Mudlet's duplicate default map information",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start()); eq(f.mapInfoSuppressions,1)
end)
test("Mudlet adapter suppresses the Short and Full default map information",function()
  local disabled={}; local updates=0
  local adapter=MudletAdapter.new(); eq(adapter:suppressDefaultMapInfo({
    disableMapInfo=function(name) disabled[#disabled+1]=name end,
    updateMap=function() updates=updates+1 end,
  }),true)
  eq(disabled[1],"Short"); eq(disabled[2],"Full"); eq(#disabled,2); eq(updates,1)
end)

local function gmcpRoom(id)
  return {Char={Vitals={hp=1,hp_max=1}},Room={Info={num=id,name="Room "..id,area=1,exits={}}}}
end

local function aliasCallback(f,pattern)
  for _,alias in pairs(f.aliases) do if alias.pattern==pattern then return alias.fn end end
end

test("successful room ingestion centers the embedded mapper",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="Training grounds.",area=1,exits={"west"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  eq(f.mapCenterCalls,1); eq(f.map.centered,175)
end)
test("Mudlet adapter centers and refreshes the native map after selecting an owned room",function()
  local calls={}
  local api={
    getRoomUserData=function(id,key) if id==175 and key=="dghud.owner" then return "DragonsGateHUD" end end,
    centerview=function(id) calls[#calls+1]={"center",id}; return true end,
    updateMap=function() calls[#calls+1]={"update"}; return true end,
  }
  local adapter=MudletAdapter.new(); local map=adapter:createMapAdapter(api)
  eq(map:setCurrent(175),true); eq(calls[1][1],"center"); eq(calls[1][2],175); eq(calls[2][1],"update")
end)
test("startup is idempotent and shutdown owns exact runtime IDs",function()
  local f=fake(); local hud=Main.new(f,{layout={left_width=190,right_width=270}}); eq(hud:start(),true); local first=f.next; eq(hud:start(),true); eq(f.next,first); eq(hud:shutdown(),true); eq(f.deleted,1); eq(f.set_borders[1],0); eq(f.set_borders[2],0); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("health check requires root handlers and an owned chat trigger",function()
  local hud=Main.new(fake(),{layout={left_width=190,right_width=270}}); eq(hud:healthCheck(),nil); hud:start(); eq(hud:healthCheck(),true); hud.chat.trigger=nil; eq(hud:healthCheck(),nil)
end)
test("window resize recomputes absolute borders and view layout",function()
  local f=fake(); f.borders={1290,234,1610,120}; local hud=Main.new(f,{layout={}}); hud:start(); eq(f.layouts[#f.layouts].mode,"wide"); eq(f.set_borders[1],336); eq(f.set_borders[2],314); eq(f.set_borders[3],336); f.width=760; f.height=700; f.callbacks["sysWindowResizeEvent"](); eq(f.layouts[#f.layouts].mode,"compact"); eq(f.set_borders[1],0); eq(f.set_borders[2],276); eq(f.set_borders[3],0); eq(f.set_borders[4],0)
end)
test("runtime wires one mapper toolbar callback across resize and reports zoom outcomes",function()
  local f=fake(); f.gmcp=gmcpRoom(175); f.zoomResult=17.5
  local hud=Main.new(f,{layout={},mapper={zoom_step=2.5,zoom_min=3,zoom_max=60}}); assert(hud:start())
  eq(type(f.mapZoomCallback),"function"); eq(f.mapZoomCallbackSets,1)
  eq(f.mapZoomCallback("larger"),17.5)
  local call=f.mapZoomCalls[1]; eq(call[1],175); eq(call[2],"larger"); eq(call[3],2.5); eq(call[4],3); eq(call[5],60)
  eq(f.mapperStatuses[#f.mapperStatuses][1],"zoom"); eq(hud.last_mapper_status,"Map zoom 17.5")
  f.mapZoomCallback("center"); eq(f.map.centered,175); eq(f.mapperStatuses[#f.mapperStatuses][1],"centered")
  f.callbacks["sysWindowResizeEvent"](); f.callbacks["sysWindowResizeEvent"](); eq(f.mapZoomCallbackSets,1)
  f.zoomError="native zoom failed"; local value,e=f.mapZoomCallback("smaller")
  eq(value,nil); eq(e,"native zoom failed"); eq(hud.last_mapper_error,"native zoom failed"); eq(f.mapperStatuses[#f.mapperStatuses][1],"error")
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
test("GMCP identity arrival hydrates persisted character history without appending it",function()
  local f=fake()
  f.chatEntriesByKey={
    unknown={},
    dace_alterac={{schema=1,timestamp="2026-08-31T12:00:00-04:00",character="Dace Alterac",category="ESP",message="persisted after login",line="persisted after login",source="builtin"}},
  }
  local hud=Main.new(f,{layout={},chat={visible_limit=1000,dedupe_seconds=3}}); assert(hud:start())
  eq(table.concat(f.loadedCharacterKeys,","),"unknown"); eq(#hud.chat:entries(),0)
  f.gmcp={Char={Status={name="Dace",surname="Alterac"},Vitals={hp=1,hp_max=1}}}; hud:refresh()
  eq(table.concat(f.loadedCharacterKeys,","),"unknown,dace_alterac")
  eq(#hud.chat:entries(),1); eq(hud.chat:entries()[1].message,"persisted after login"); eq(f.chatStorageAppends or 0,0)
end)
test("controller status and storage use the effective bounded visible limit",function()
  local oversized=fake(); oversized.chatEntries={}
  for index=1,1001 do oversized.chatEntries[index]={category="ROOM",message="line-"..index} end
  local hud=Main.new(oversized,{layout={},chat={visible_limit=1500,dedupe_seconds=3}}); assert(hud:start())
  local status=hud:chatStatus(); eq(oversized.chatVisibleLimit,1000); eq(status.visible_count,1000)
  eq(hud.chat:entries()[1].message,"line-2"); eq(hud.chat:entries()[1000].message,"line-1001")

  local lower=fake(); lower.chatEntries={{category="ROOM",message="one"},{category="ROOM",message="two"},{category="ROOM",message="three"}}
  local lowerHud=Main.new(lower,{layout={},chat={visible_limit=2,dedupe_seconds=3}}); assert(lowerHud:start())
  eq(lower.chatVisibleLimit,2); eq(lowerHud:chatStatus().visible_count,2); eq(lowerHud.chat:entries()[1].message,"two")
end)
test("startup checks for updates before refreshing command data at an in-game prompt",function()
  local f=fake(); f.character_active=true; local order={}
  local hud=Main.new(f,{layout={}})
  hud.updater={checkAtCharacterEntry=function(_,done) order[#order+1]="check"; eq(#(f.sentCommands or {}),0); done(false); return true end}
  assert(hud:start()); order[#order+1]=f.sent
  eq(table.concat(order,","),"check,inventory")
end)
test("welcome character entry checks only once and never refreshes before completion",function()
  local f=fake(); local pending; local checks=0
  local hud=Main.new(f,{layout={}})
  hud.updater={checkAtCharacterEntry=function(_,done) checks=checks+1; pending=done; return true end}
  hud:start()
  for _,fn in pairs(f.triggers) do fn("Welcome to Dragon's Gate, Test!") end
  for _,fn in pairs(f.triggers) do fn("Welcome to Dragon's Gate, Test!") end
  eq(checks,1); eq(#(f.sentCommands or {}),0); pending(false); eq(f.sent,"inventory")
end)
test("reload leaves one command collector",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:reload(); eq(f:count(f.triggers),2); local outgoing=0; for _,name in pairs(f.events) do if name=="sysDataSendRequest" then outgoing=outgoing+1 end end; eq(outgoing,2)
end)

test("runtime wires one automapper handler per event and cleans it exactly",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=100,name="A",area=1,exits={"north"}}}}
  local personal=f:addEvent("gmcp.Room.Info",function() end); local hud=Main.new(f,{layout={}}); assert(hud:start())
  eq(f.createdMaps,1); eq(hud.automapper:currentRoom(),100)
  local function count(name) local n=0; for _,value in pairs(f.events) do if value==name then n=n+1 end end; return n end
  eq(count("gmcp.Room.Info"),2); eq(count("gmcp.Room.WrongDir"),1); eq(count("sysDisconnectionEvent"),2); eq(count("sysDataSendRequest"),2)
  hud:reload(); eq(f.createdMaps,2); eq(count("gmcp.Room.Info"),2); eq(count("gmcp.Room.WrongDir"),1); eq(count("sysDataSendRequest"),2)
  hud:shutdown(); eq(f.events[personal],"gmcp.Room.Info"); eq(count("gmcp.Room.Info"),1); eq(count("gmcp.Room.WrongDir"),0); eq(count("sysDataSendRequest"),0)
end)

test("runtime routes movement, wrong direction, teleport commands, and disconnect",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=100,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north"); eq(hud.automapper.pending.direction,"n")
  f.callbacks["gmcp.Room.WrongDir"](); eq(hud.automapper.pending,nil)
  f.callbacks["sysDataSendRequest"](nil,"north"); f.callbacks["sysDataSendRequest"](nil,"go portal"); eq(hud.automapper.pending,nil)
  f.callbacks["sysDataSendRequest"](nil,"north"); f.callbacks["sysDisconnectionEvent"](); eq(hud.automapper.pending,nil)
end)
test("runtime confirms the final non-direction command from the next canonical room",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={},mapper={special_timeout=7}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"pull lever"); f.callbacks["sysDataSendRequest"](nil,"go gate")
  local ownedTimer=hud.special_transition.timer; eq(f.timer_delays[ownedTimer],7)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,900); eq(f.map.special[1].command,"go gate")
  eq(hud.special_transition:pending(),nil); eq(f.timer_cancels[ownedTimer],1); eq(f:count(f.timers),0)
end)
test("expired arbitrary special command cannot reuse an earlier direction",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.callbacks["sysDataSendRequest"](nil,"climb rope")
  local timer=hud.special_transition.timer; local expire=assert(f.timers[timer]); f.timers[timer]=nil; expire()
  eq(hud.special_transition:pending(),nil)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,0)
end)
test("unscheduled arbitrary special command cannot reuse an earlier direction",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.failSchedule="return"; f.callbacks["sysDataSendRequest"](nil,"climb rope"); f.failSchedule=nil
  eq(hud.special_transition:pending(),nil)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,0)
end)
test("excluded control command cannot reuse an earlier direction",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.callbacks["sysDataSendRequest"](nil,"look")
  eq(hud.special_transition:pending(),nil)
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,0)
end)
test("successful arbitrary special command owns the transition exactly",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"north")
  f.callbacks["sysDataSendRequest"](nil,"  Climb RuneRope  ")
  f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,0); eq(#f.map.special,1)
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,900); eq(f.map.special[1].command,"Climb RuneRope")
end)
test("runtime reports tracker scheduler failures without retaining candidates",function()
  for _,mode in ipairs({"return","throw"}) do
    local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start()); f.failSchedule=mode
    local callbackOk=pcall(f.callbacks["sysDataSendRequest"],nil,"climb rope")
    eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(f:count(f.timers),0)
    eq(tostring(hud.last_mapper_error):find("special schedule",1,true)~=nil,true)
    f.failSchedule=nil; hud:shutdown()
  end
end)
test("runtime reports bounded replacement cancellation failures and does not schedule a replacement",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local scheduled=f.next
  f.failCancel=true
  local callbackOk=pcall(f.callbacks["sysDataSendRequest"],nil,"Open New Door")
  eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(f.next,scheduled)
  eq(tostring(hud.last_mapper_error):find("special transition replacement cancellation failed",1,true),1)
  eq(#tostring(hud.last_mapper_error)<=200,true)
  f.failCancel=nil; hud:shutdown()
end)
test("runtime contains cancellation exceptions and preserves personal timers",function()
  local f=fake(); local personalTimer=f:schedule(60,function() end); f.gmcp=gmcpRoom(100)
  local hud=Main.new(f,{layout={}}); assert(hud:start()); f.callbacks["sysDataSendRequest"](nil,"enter tunnel")
  local ownedTimer=hud.special_transition.timer; f.failCancel=true
  local callbackOk=pcall(f.callbacks["sysDisconnectionEvent"])
  eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(f.timer_cancels[ownedTimer],1)
  eq(tostring(hud.last_mapper_error):find("special cancellation exploded",1,true)~=nil,true)
  eq(f.timers[personalTimer]~=nil,true); f.failCancel=nil; hud:shutdown(); eq(f.timers[personalTimer]~=nil,true)
end)
test("runtime contains mapper failure after confirmation and clears transition state",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.failSpecialMap="throw"; f.gmcp=gmcpRoom(900)
  local callbackOk=pcall(f.callbacks["gmcp.Room.Info"])
  eq(callbackOk,true); eq(hud.special_transition:pending(),nil); eq(hud.automapper.pending,nil); eq(f:count(f.timers),0)
  eq(#f.map.special,0); eq(tostring(hud.last_mapper_error):find("special mapping exploded",1,true)~=nil,true)
  hud:shutdown()
end)
test("runtime continues from an ensured special destination after edge persistence fails",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.failSpecialMap="return"; f.gmcp=gmcpRoom(900); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.special,0); eq(hud.automapper:currentRoom(),900); eq(f.map.current,900)
  eq(f.map.rooms[900].partition,"special:900")

  f.failSpecialMap=nil; f.callbacks["sysDataSendRequest"](nil,"north"); f.gmcp=gmcpRoom(901); f.callbacks["gmcp.Room.Info"]()
  eq(#f.map.links,1); eq(f.map.links[1].from,900); eq(f.map.links[1].to,901); eq(f.map.links[1].direction,"n")
  eq(f.map.rooms[901].partition,"special:900")
  hud:shutdown()
end)
test("repeated reload cancels each candidate once and retains unrelated runtime",function()
  local f=fake(); local personalAlias=f:addAlias("personal",function() end); local personalEvent=f:addEvent("personal",function() end); local personalTimer=f:schedule(60,function() end); f.gmcp=gmcpRoom(100)
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  for _=1,3 do
    f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local tracker=hud.special_transition; local ownedTimer=tracker.timer
    assert(hud:reload()); eq(tracker:pending(),nil); eq(f.timer_cancels[ownedTimer],1); eq(hud.special_transition==tracker,false)
  end
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local tracker=hud.special_transition; local ownedTimer=tracker.timer
  hud:shutdown(); eq(tracker:pending(),nil); eq(f.timer_cancels[ownedTimer],1)
  eq(f.aliases[personalAlias]~=nil,true); eq(f.events[personalEvent]~=nil,true); eq(f.timers[personalTimer]~=nil,true)
end)
test("runtime confirms a generated special transition",function()
  local f=fake(); f.gmcp=gmcpRoom(100); local hud=Main.new(f,{layout={}}); assert(hud:start())
  assert(hud.walker.adapter:sendCommand("go arch")); f.callbacks["sysDataSendRequest"](nil,"go arch")
  f.gmcp=gmcpRoom(901); f.callbacks["gmcp.Room.Info"]()
  eq(f.map.special[1].from,100); eq(f.map.special[1].to,901); eq(f.map.special[1].command,"go arch")
end)
test("runtime cancels candidates on movement and mapper lifecycle boundaries",function()
  local f=fake(); local personalTimer=f:schedule(60,function() end); f.gmcp=gmcpRoom(100)
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); eq(hud.special_transition:pending().command,"enter tunnel")
  f.callbacks["sysDataSendRequest"](nil,"north"); eq(hud.special_transition:pending(),nil)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); f.callbacks["gmcp.Room.WrongDir"](); eq(hud.special_transition:pending(),nil)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); f.callbacks["sysDisconnectionEvent"](); eq(hud.special_transition:pending(),nil)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); hud.settings.mapper={enabled=false}; f.callbacks["sysDataSendRequest"](nil,"look"); eq(hud.special_transition:pending(),nil)
  local first=hud.special_transition; hud.settings.mapper={}; assert(hud:reload()); eq(first:pending(),nil); eq(hud.special_transition==first,false)
  f.callbacks["sysDataSendRequest"](nil,"enter tunnel"); local second=hud.special_transition; hud:shutdown(); eq(second:pending(),nil)
  eq(f.timers[personalTimer]~=nil,true); eq(f:count(f.timers),1)
end)
test("roundtime counts down once per second and becomes ready",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:onRoundtime(2); eq(hud.last_state.vitals.roundtime,2)
  f:fireTimer(); eq(hud.last_state.vitals.roundtime,1); f:fireTimer(); eq(hud.last_state.vitals.roundtime,0); eq(f:count(f.timers),0)
end)
test("GMCP roundtime pauses controlled walking until a ready vitals update",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1,roundtime=0}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  f.route={rooms={175,176,180},commands={"north","east"}}
  local hud=Main.new(f,{layout={},mapper={walk_timeout=12}}); assert(hud:start())
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("180")); eq(#f.sentCommands,1)
  f.gmcp.Char.Vitals.roundtime=4; f.gmcp.Room.Info={num=176,name="B",area=1,exits={"east"}}; f.callbacks["gmcp.Room.Info"]()
  eq(#f.sentCommands,1); eq(hud.walker.waiting_roundtime,true)
  f.gmcp.Char.Vitals.roundtime=2; f.callbacks["gmcp.Char.Vitals"](); eq(#f.sentCommands,1)
  f.gmcp.Char.Vitals.roundtime=0; f.callbacks["gmcp.Char.Vitals"](); eq(#f.sentCommands,2); eq(f.sentCommands[2],"e")
  hud:shutdown()
end)
test("repeated resize changes typography without growing runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); local runtime=f:count(f.events)+f:count(f.triggers)+f:count(f.aliases)
  for _,size in ipairs({{2056,1177},{1200,800},{760,700},{3840,2160},{1200,800}}) do
    f.width,f.height=size[1],size[2]; f.callbacks["sysWindowResizeEvent"](); local r=f.layouts[#f.layouts]
    eq(r.inventory_row_height>=r.inventory_font+8,true); eq(r.details_line_height>=r.body_font+4,true); eq(r.console_width>=math.floor(size[1]*.65),true); eq(f:count(f.events)+f:count(f.triggers)+f:count(f.aliases),runtime)
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

test("reload and shutdown retain unrelated aliases events and timers",function()
  local f=fake(); local personalAlias=f:addAlias(); local personalEvent=f:addEvent("personal",function() end); local personalTimer=f:schedule(1,function() end)
  local hud=Main.new(f,{layout={}}); hud:start(); hud:reload(); hud:shutdown()
  eq(f.aliases[personalAlias]~=nil,true); eq(f.events[personalEvent]~=nil,true); eq(f.timers[personalTimer]~=nil,true)
end)

test("map adapter construction exceptions and nil results roll back startup",function()
  for _,mode in ipairs({"throw","nil"}) do
    local f=fake()
    function f:createMapAdapter()
      if mode=="throw" then error("adapter exploded") end
      return nil,"adapter unavailable"
    end
    local hud=Main.new(f,{layout={}}); local ok,err=hud:start()
    eq(ok,nil); eq(tostring(err):find(mode=="throw" and "adapter exploded" or "adapter unavailable",1,true)~=nil,true)
    eq(hud.started,false); eq(hud.map,nil); eq(hud.automapper,nil); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0)
  end
end)

test("automapper construction exceptions and nil results roll back startup",function()
  for _,mode in ipairs({"throw","nil"}) do
    local f=fake(); local hud=Main.new(f,{layout={}})
    hud.createAutomapper=function()
      if mode=="throw" then error("automapper exploded") end
      return nil,"automapper unavailable"
    end
    local ok,err=hud:start()
    eq(ok,nil); eq(tostring(err):find(mode=="throw" and "automapper exploded" or "automapper unavailable",1,true)~=nil,true)
    eq(hud.started,false); eq(hud.map,nil); eq(hud.automapper,nil); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0)
  end
end)

test("every post-hook startup failure restores hook and cleans runtime",function()
  local oldHook=_G.doSpeedWalk; local personal=function() return "personal" end
  for _,boundary in ipairs({"view","layout","collector","event","alias"}) do
    _G.doSpeedWalk=personal; local f=fake(); local hud=Main.new(f,{layout={}})
    if boundary=="view" then function f:createView() error("view exploded") end end
    if boundary=="layout" then function f:setBorders() error("layout exploded") end end
    if boundary=="collector" then function f:addLineTrigger() error("collector exploded") end end
    if boundary=="event" then function f:addEvent() error("event exploded") end end
    if boundary=="alias" then function f:addAlias() error("alias exploded") end end
    local ok,err=hud:start(); eq(ok,nil); eq(tostring(err):find("exploded",1,true)~=nil,true)
    eq(_G.doSpeedWalk,personal); eq(hud.started,false); eq(hud.walker,nil); eq(hud.special_transition,nil)
    eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
  end
  _G.doSpeedWalk=oldHook
end)

test("walk failures emit one stopped status and clear generated marker",function()
  for _,boundary in ipairs({"send","schedule"}) do
    local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=1,name="A",area=1,exits={"north"}}}}; f.route={rooms={1,2},commands={"north"}}
    if boundary=="send" then function f:sendCommand() error("send exploded") end
    else function f:schedule() error("schedule exploded") end end
    local hud=Main.new(f,{layout={}}); assert(hud:start()); local before=#(f.mapperStatuses or {})
    local ok=aliasCallback(f,"^walkto\\s+(\\d+)$")("2"); eq(ok,nil); eq(hud.walker:active(),false); eq(hud.generated_command,nil)
    local stopped=0; for index=before+1,#f.mapperStatuses do if f.mapperStatuses[index][1]=="stopped" then stopped=stopped+1 end end
    eq(stopped,1); eq(f.mapperStatuses[#f.mapperStatuses][1],"stopped"); hud:shutdown()
  end
end)

test("walk aliases validate current room route safely and share one walker",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  f.route={rooms={175,176,180},commands={"north","east"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); local walkstop=assert(aliasCallback(f,"^walkstop$")); local mapcenter=assert(aliasCallback(f,"^mapcenter$"))
  assert(walkto("180")); eq(f.sentCommands[#f.sentCommands],"n"); eq(hud.walker:active(),true)
  f.callbacks["sysDataSendRequest"](nil,"n"); eq(hud.walker:active(),true)
  f.callbacks["gmcp.Room.Info"](); eq(#f.sentCommands,1)
  walkstop(); eq(hud.walker:active(),false)
  mapcenter(); eq(f.map.centered,175)
end)

test("map adapter validates exact owned route steps and preserves special command syntax",function()
  local owners={[1]="DragonsGateHUD",[2]="DragonsGateHUD",[3]="DragonsGateHUD"}
  local adapter=MapAdapter.new({
    getRoomUserData=function(id,key) if key=="dghud.owner" then return owners[id] or "" end end,
    getSpecialExits=function(from,listAll) eq(from,1); eq(listAll,true); return {[2]={['Go Gate']="0"}} end,
  })
  local ok,command=adapter:validateRouteStep(1,2,"Go Gate")
  eq(ok,true); eq(command,"Go Gate")
  ok,command=adapter:validateRouteStep(1,2,"go gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 2")
  ok,command=adapter:validateRouteStep(1,3,"Go Gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 3")
  ok,command=adapter:validateRouteStep(1,2,"leave gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 2")
  owners[2]="Personal"
  ok,command=adapter:validateRouteStep(1,2,"Go Gate")
  eq(ok,nil); eq(command,"special exit is not confirmed from 1 to 2")
end)

test("walkto crosses a confirmed special exit one command at a time around roundtime",function()
  local f=fake(); f.gmcp=gmcpRoom(1); f.route={rooms={1,2,3},commands={"  Go Gate  ","north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  hud.map.rooms[2]={}; hud.map.rooms[3]={}; hud.map.special[1]={from=1,to=2,command="Go Gate"}
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); assert(walkto("3"))
  eq(f.sentCommands[1],"Go Gate"); eq(f.sentCommands[2],nil); eq(hud.generated_command,"Go Gate")
  f.callbacks["sysDataSendRequest"](nil,"Go Gate"); eq(hud.generated_command,nil); eq(hud.walker:active(),true)
  f.gmcp=gmcpRoom(2); f.gmcp.Char.Vitals.roundtime=4; f.callbacks["gmcp.Room.Info"]()
  eq(#f.sentCommands,1); eq(hud.walker.waiting_roundtime,true)
  f.gmcp.Char.Vitals.roundtime=0; f.callbacks["gmcp.Char.Vitals"]()
  eq(f.sentCommands[2],"n"); eq(f.sentCommands[3],nil)
  f.callbacks["sysDataSendRequest"](nil,"n"); f.gmcp=gmcpRoom(3); f.callbacks["gmcp.Room.Info"]()
  eq(hud.walker:active(),false); eq(hud.generated_command,nil)
end)

test("native map click crosses a confirmed special exit with exact generated isolation",function()
  local oldHook,oldPath,oldDir=_G.doSpeedWalk,_G.speedWalkPath,_G.speedWalkDir
  local f=fake(); f.gmcp=gmcpRoom(1); local hud=Main.new(f,{layout={}}); assert(hud:start())
  hud.map.rooms[2]={}; hud.map.rooms[3]={}; hud.map.special[1]={from=1,to=2,command="go gate"}
  _G.speedWalkPath={1,2,3}; _G.speedWalkDir={"go gate","east"}; assert(_G.doSpeedWalk())
  eq(f.sentCommands[1],"go gate"); eq(hud.generated_command,"go gate")
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.gmcp=gmcpRoom(2); f.callbacks["gmcp.Room.Info"]()
  eq(f.sentCommands[2],"e"); eq(f.sentCommands[3],nil)
  hud:shutdown(); _G.doSpeedWalk=oldHook; _G.speedWalkPath=oldPath; _G.speedWalkDir=oldDir
end)

test("special walking stops on an unexpected room and movement timeout",function()
  local f=fake(); f.gmcp=gmcpRoom(1); f.route={rooms={1,2},commands={"go gate"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.map.rooms[2]={}; hud.map.special[1]={from=1,to=2,command="go gate"}
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); assert(walkto("2"))
  f.callbacks["sysDataSendRequest"](nil,"go gate"); f.gmcp=gmcpRoom(99); f.callbacks["gmcp.Room.Info"]()
  eq(hud.walker:active(),false); eq(hud.last_mapper_status,"Walk stopped: unexpected room 99")
  f.gmcp=gmcpRoom(1); hud.automapper.current_id=1; assert(walkto("2")); local timeout=hud.walker.timeout
  local callback=assert(f.timers[timeout]); f.timers[timeout]=nil; callback()
  eq(hud.walker:active(),false); eq(hud.generated_command,nil); eq(hud.last_mapper_status,"Walk stopped: movement timed out")
end)

test("manually typed non-direction command replaces a generated special walk",function()
  local f=fake(); f.gmcp=gmcpRoom(1); f.route={rooms={1,2},commands={"go gate"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.map.rooms[2]={}; hud.map.special[1]={from=1,to=2,command="go gate"}
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("2")); eq(hud.generated_command,"go gate")
  f.callbacks["sysDataSendRequest"](nil,"pull lever")
  eq(hud.walker:active(),false); eq(hud.generated_command,nil); eq(hud.last_mapper_status,"Walk stopped: manual movement")
  eq(hud.special_transition:pending().command,"pull lever")
end)

test("routine walking stops are statuses and do not overwrite mapper errors",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}; f.route={rooms={175,176},commands={"north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); hud.last_mapper_error="earlier failure"
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("176")); aliasCallback(f,"^walkstop$")()
  local status=hud:mapStatus(); eq(status.last_error,"earlier failure"); eq(status.last_status,"Walk stopped: requested")
  assert(aliasCallback(f,"^walkto\\s+(\\d+)$")("176")); f.callbacks["sysDataSendRequest"](nil,"east")
  status=hud:mapStatus(); eq(status.last_error,"earlier failure"); eq(status.last_status,"Walk stopped: manual movement")
  hud:shutdown(); eq(hud.last_mapper_error,"earlier failure")
end)

test("walkto rejects missing current rooms route errors and unconfirmed special exits",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); assert(hud:start())
  local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$")); local ok,err=walkto("20"); eq(ok,nil); eq(err,"current room is unavailable")
  hud.automapper.current_id=10; f.routeError="no route"; ok,err=walkto("20"); eq(ok,nil); eq(err,"no route")
  f.routeError=nil; f.route={rooms={10,20},commands={"go portal"}}; ok,err=walkto("20"); eq(ok,nil); eq(err,"special exit is not confirmed from 10 to 20")
end)

test("native map click uses walker route and restores the previous global hook",function()
  local previous=function() return "personal" end; local oldHook=_G.doSpeedWalk; _G.doSpeedWalk=previous
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); local ownedHook=_G.doSpeedWalk; eq(ownedHook~=previous,true)
  hud.map.rooms[176]={}; _G.speedWalkPath={175,176}; _G.speedWalkDir={"north"}; assert(ownedHook()); eq(f.sentCommands[#f.sentCommands],"n")
  hud:shutdown(); eq(_G.doSpeedWalk,previous); eq(f:count(f.timers),0); eq(f:count(f.aliases),0)
  _G.doSpeedWalk=oldHook; _G.speedWalkPath=nil; _G.speedWalkDir=nil
end)

test("disabled mapper never replaces personal speedwalk hook",function()
  local old=_G.doSpeedWalk; local personal=function() return "personal" end; _G.doSpeedWalk=personal
  local f=fake(); local hud=Main.new(f,{layout={},mapper={enabled=false}}); assert(hud:start()); eq(_G.doSpeedWalk,personal); hud:shutdown(); eq(_G.doSpeedWalk,personal); _G.doSpeedWalk=old
end)

test("map click delegates unowned and mixed routes but handles wholly owned routes",function()
  local oldHook,oldPath,oldDir=_G.doSpeedWalk,_G.speedWalkPath,_G.speedWalkDir
  local delegated=0; local personal=function() delegated=delegated+1; return "personal" end; _G.doSpeedWalk=personal
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={},mapper={}}); assert(hud:start()); hud.map.isOwned=function(_,id) return id==175 or id==176 end
  _G.speedWalkPath={900,901}; _G.speedWalkDir={"n"}; eq(_G.doSpeedWalk(),"personal"); eq(delegated,1)
  _G.speedWalkPath={175,901}; _G.speedWalkDir={"n"}; eq(_G.doSpeedWalk(),"personal"); eq(delegated,2)
  _G.speedWalkPath={175,176}; _G.speedWalkDir={"n"}; assert(_G.doSpeedWalk()); eq(delegated,2)
  hud:shutdown(); eq(_G.doSpeedWalk,personal); _G.doSpeedWalk=oldHook; _G.speedWalkPath=oldPath; _G.speedWalkDir=oldDir
end)

test("native map click accepts speedWalkPath without the current room",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=175,name="A",area=1,exits={"north"}}}}
  local hud=Main.new(f,{layout={}}); assert(hud:start())
  hud.map.rooms[176]={}; _G.speedWalkPath={176}; _G.speedWalkDir={"north"}; assert(_G.doSpeedWalk()); eq(hud.walker:active(),true); eq(f.sentCommands[#f.sentCommands],"n")
  hud:shutdown(); _G.speedWalkPath=nil; _G.speedWalkDir=nil
end)

test("Mudlet send with no return value still starts controlled walking",function()
  local f=fake(); function f:sendCommand(command) self.sentCommands=self.sentCommands or {}; self.sentCommands[#self.sentCommands+1]=command end
  f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=1,name="A",area=1,exits={"north"}}}}; f.route={rooms={1,2},commands={"north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$"))
  assert(walkto("2")); eq(hud.walker:active(),true); eq(f.sentCommands[#f.sentCommands],"n"); hud:shutdown()
end)

test("walker stops on disconnect WrongDir unexpected room manual movement and shutdown",function()
  local f=fake(); f.gmcp={Char={Vitals={hp=1,hp_max=1}},Room={Info={num=1,name="A",area=1,exits={"north"}}}}; f.route={rooms={1,2},commands={"north"}}
  local hud=Main.new(f,{layout={}}); assert(hud:start()); local walkto=assert(aliasCallback(f,"^walkto\\s+(\\d+)$"))
  walkto("2"); f.callbacks["sysDataSendRequest"](nil,"east"); eq(hud.walker:active(),false)
  walkto("2"); f.callbacks["gmcp.Room.WrongDir"](); eq(hud.walker:active(),false)
  walkto("2"); f.gmcp.Room.Info={num=99,name="Elsewhere",area=1,exits={}}; f.callbacks["gmcp.Room.Info"](); eq(hud.walker:active(),false)
  f.gmcp.Room.Info={num=1,name="A",area=1,exits={"north"}}; hud.automapper.current_id=1; walkto("2"); f.callbacks["sysDisconnectionEvent"](); eq(hud.walker:active(),false)
  walkto("2"); hud:shutdown(); eq(f:count(f.timers),0)
end)
