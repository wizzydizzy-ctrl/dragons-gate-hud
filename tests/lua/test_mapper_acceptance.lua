local Main=require("main")
local Defaults=require("defaults")
local MapperModel=require("mapper_model")

local function count(values) local n=0; for _ in pairs(values) do n=n+1 end; return n end
local function runtime(world)
  local f={next=0,events={},aliases={},triggers={},timers={},world=world,statuses={},gmcp={Char={Vitals={hp=10,hp_max=10}},Room={Info={num=176,name="Start",area=1,exits={"north"}}}}}
  function f:getWindowSize() return 1920,1080 end
  function f:setBorders() end
  function f:createView() return {update=function() end,applyLayout=function() end,renderChat=function() end,setChatFilterCallback=function() end,setMapZoomCallback=function(_,callback) f.zoomCallback=callback end,delete=function() end} end
  function f:getGMCP() return self.gmcp end
  function f:isCharacterActive() return false end
  function f:addEvent(name,fn) self.next=self.next+1; local id="event-"..self.next; self.events[id]={name=name,fn=fn}; return id end
  function f:killEvent(id) self.events[id]=nil end
  function f:addAlias(pattern,fn) self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]={pattern=pattern,fn=fn}; return id end
  function f:killAlias(id) self.aliases[id]=nil end
  function f:addLineTrigger(fn) self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:killTrigger(id) self.triggers[id]=nil end
  function f:createChatStorage() return {loadRecent=function() return {} end,append=function() return true end,close=function() return true end,characterKey=function() return "test" end} end
  function f:epoch() return 1 end
  function f:timestamp() return "2026-08-31T12:00:00-04:00" end
  function f:schedule(_,fn) self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil; return true end
  function f:sendCommand(command) self.sent=command; self.world.sent=self.world.sent or {}; self.world.sent[#self.world.sent+1]=command; return true end
  function f:reportMapperStatus(kind,message) self.statuses[#self.statuses+1]={kind=kind,message=message}; return true end
  function f:reportMapStatus(status) self.map_status=status; return status end
  function f:createMapAdapter()
    local map={world=self.world}
    local directions={"n","ne","e","se","s","sw","w","nw","up","down","in","out"}
    local reverse={n="s",ne="sw",e="w",se="nw",s="n",sw="ne",w="e",nw="se",up="down",down="up",["in"]="out",out="in"}
    local function normalize(command) return tostring(command or ""):match("^%s*(.-)%s*$") end
    local function ensureArea(partition)
      map.world.areas=map.world.areas or {}; map.world.zoom=map.world.zoom or {}
      local area=map.world.areas[partition]
      if not area then
        map.world.nextArea=(map.world.nextArea or 0)+1; area=map.world.nextArea; map.world.areas[partition]=area; map.world.zoom[area]=20
      end
      return area
    end
    function map:roomRecord(id)
      local room=self.world.rooms[id]
      if not room then return {exists=false,owned=false,placement_needed=true} end
      return {exists=true,owned=room.owner=="DragonsGateHUD",partition=room.partition,game_area=tostring(room.game_area or ""),area=room.area,coordinates=room.coordinates,placement_needed=false}
    end
    function map:effectivePartition(id)
      local room=self.world.rooms[id]
      if room then return room.partition end
      return nil,"room partition is unavailable"
    end
    function map:ensureRoom(room,coordinates,partition)
      local old=self.world.rooms[room.id]
      if old and old.owner~="DragonsGateHUD" then return nil,"room "..room.id.." is not owned by DragonsGateHUD" end
      if old then old.name=room.name; return true end
      partition=tostring(partition or room.area_key)
      self.world.creations=self.world.creations or {}; self.world.creations[room.id]=(self.world.creations[room.id] or 0)+1
      self.world.rooms[room.id]={name=room.name,owner="DragonsGateHUD",coordinates=coordinates,partition=partition,game_area=tostring(room.area_key),area=ensureArea(partition)}
      return true
    end
    function map:ensureStub(id,direction) self.world.stubs[id..":"..direction]=true; return true end
    function map:connect(from,to,direction,confirmedReverse)
      self.world.links[from..":"..direction]=to
      if confirmedReverse then self.world.links[to..":"..reverse[direction]]=from end
      return true
    end
    function map:connectSpecial(from,to,command)
      if not self:isOwned(from) or not self:isOwned(to) then return nil,"special exit endpoints are not owned by DragonsGateHUD" end
      self.world.special=self.world.special or {}; self.world.special[from..":"..to..":"..normalize(command)]=true; return true
    end
    function map:specialExitMatches(from,to,command)
      return self.world.special and self.world.special[from..":"..to..":"..normalize(command)]==true
    end
    function map:validateRouteStep(from,to,command)
      local direction=MapperModel.direction(command)
      if direction then
        if self:isOwned(from) and self:isOwned(to) and self.world.links[from..":"..direction]==to then return true,direction end
        return nil,"standard exit is not persisted from "..from.." to "..to
      end
      if self:isOwned(from) and self:isOwned(to) and self:specialExitMatches(from,to,command) then return true,command end
      return nil,"special exit is not confirmed from "..from.." to "..to
    end
    function map:setCurrent(id) self.current=id; return true end
    function map:center(id) self.current=id; return true end
    function map:zoom(id,action,step,minimum,maximum)
      local room=self.world.rooms[id]; if not room or room.owner~="DragonsGateHUD" then return nil,"room is not owned by DragonsGateHUD" end
      local current=self.world.zoom[room.area]; local applied=action=="larger" and current-step or current+step
      applied=math.max(minimum,math.min(maximum,applied)); self.world.zoom[room.area]=applied; self.world.lastZoomArea=room.area; return applied
    end
    function map:coordinates(id) local room=self.world.rooms[id]; return room and room.coordinates end
    function map:roomsAt(partition,x,y,z) local result={}; for id,room in pairs(self.world.rooms) do local p=room.coordinates; if room.owner=="DragonsGateHUD" and tostring(room.partition)==tostring(partition) and p and p.x==x and p.y==y and p.z==z then result[#result+1]=id end end; return result end
    function map:isOwned(id) return self.world.rooms[id] and self.world.rooms[id].owner=="DragonsGateHUD" end
    function map:route(from,to)
      from=tonumber(from); to=tonumber(to)
      if not self:isOwned(from) or not self:isOwned(to) then return nil,"no route" end
      local queue={{room=from,rooms={from},commands={}}}; local seen={[from]=true}; local cursor=1
      while queue[cursor] do
        local path=queue[cursor]; cursor=cursor+1
        if path.room==to then
          for index,command in ipairs(path.commands) do
            local valid,validErr=self:validateRouteStep(path.rooms[index],path.rooms[index+1],command)
            if not valid then return nil,validErr end
          end
          return {rooms=path.rooms,commands=path.commands}
        end
        local neighbors={}
        for _,direction in ipairs(directions) do
          local destination=self.world.links[path.room..":"..direction]
          if destination then neighbors[#neighbors+1]={to=destination,command=direction} end
        end
        local special={}
        for key in pairs(self.world.special or {}) do
          local source,destination,command=key:match("^(%d+):(%d+):(.*)$")
          if tonumber(source)==path.room then special[#special+1]={to=tonumber(destination),command=command} end
        end
        table.sort(special,function(a,b) return a.to==b.to and a.command<b.command or a.to<b.to end)
        for _,edge in ipairs(special) do neighbors[#neighbors+1]=edge end
        for _,edge in ipairs(neighbors) do
          if self:isOwned(edge.to) and not seen[edge.to] then
            seen[edge.to]=true
            local rooms={}; for index,id in ipairs(path.rooms) do rooms[index]=id end; rooms[#rooms+1]=edge.to
            local commands={}; for index,command in ipairs(path.commands) do commands[index]=command end; commands[#commands+1]=edge.command
            queue[#queue+1]={room=edge.to,rooms=rooms,commands=commands}
          end
        end
      end
      return nil,"no route"
    end
    return map
  end
  return f
end

local function findAlias(f,pattern) for _,alias in pairs(f.aliases) do if alias.pattern==pattern then return alias.fn end end end
local function fire(f,name,arg)
  for _,event in pairs(f.events) do if event.name==name then event.fn(nil,arg) end end
end
local function arrive(f,id,exits)
  f.gmcp.Room.Info={num=id,name="Room "..id,area=1,environment="Plain",flags={"indoor"},exits=exits or {}}
  fire(f,"gmcp.Room.Info")
end
local function observeCommand(f,command)
  fire(f,"sysDataSendRequest",command)
end

test("mapper release defaults are ready for version 0.2.56",function()
  eq(Defaults.version,"0.2.56"); eq(Defaults.mapper.enabled,true); eq(Defaults.mapper.walk_timeout,12)
  eq(Defaults.mapper.minimum_height,90); eq(Defaults.mapper.schema,1)
end)

test("special submaps persist canonical rooms zoom and mixed walking end to end",function()
  local world={rooms={},stubs={},links={},special={},areas={},zoom={},creations={},sent={}}
  local f=runtime(world)
  f.gmcp.Room.Info={num=100,name="Room 100",area=1,environment="Plain",flags={"outdoor"},exits={}}
  local hud=Main.new(f,Defaults); assert(hud:start())

  observeCommand(f,"  Go Door  "); arrive(f,900,{"north"})
  observeCommand(f,"north"); arrive(f,901,{"south"})
  observeCommand(f,"  Go Arch  "); arrive(f,1200,{})
  observeCommand(f,"leave"); arrive(f,901,{"south"})

  eq(count(world.rooms),4)
  for _,id in ipairs({100,900,901,1200}) do eq(world.creations[id],1) end
  eq(world.rooms[100].partition,"1")
  eq(world.rooms[900].partition,"special:900")
  eq(world.rooms[901].partition,"special:900")
  eq(world.rooms[1200].partition,"special:1200")
  eq(count(world.special),3)
  eq(world.special["100:900:Go Door"],true)
  eq(world.special["901:1200:Go Arch"],true)
  eq(world.special["1200:901:leave"],true)
  eq(world.special["900:100:leave door"],nil)

  observeCommand(f,"Go Arch"); arrive(f,1200,{"out"})
  observeCommand(f,"out"); arrive(f,100,{"in"})
  eq(count(world.special),3); eq(world.links["1200:out"],100); eq(world.links["100:in"],1200)

  assert(hud:reload()); observeCommand(f,"Go Door"); arrive(f,900,{"north"})
  eq(count(world.rooms),4); eq(count(world.special),3); eq(world.rooms[900].partition,"special:900")
  for _,id in ipairs({100,900,901,1200}) do eq(world.creations[id],1) end
  local savedArea=world.rooms[900].area; world.zoom[savedArea]=20
  eq(f.zoomCallback("larger"),17.5); eq(world.lastZoomArea,savedArea); eq(world.zoom[savedArea],17.5)

  local invalid,invalidErr=hud.map:validateRouteStep(901,100,"south")
  eq(invalid,nil); eq(invalidErr,"standard exit is not persisted from 901 to 100")
  local route,routeErr=hud.map:route(900,100); assert(route,routeErr)
  eq(table.concat(route.rooms,","),"900,901,1200,100")
  eq(table.concat(route.commands,","),"n,Go Arch,out")
  for index,command in ipairs(route.commands) do
    local valid,canonical=hud.map:validateRouteStep(route.rooms[index],route.rooms[index+1],command)
    assert(valid,canonical); eq(canonical,command)
  end
  local walk=assert(findAlias(f,"^walkto\\s+(\\d+)$")); local sentBefore=#world.sent
  assert(walk("100")); eq(#world.sent,sentBefore+1); eq(world.sent[#world.sent],"n")
  observeCommand(f,"n"); arrive(f,901,{"south"}); eq(#world.sent,sentBefore+2); eq(world.sent[#world.sent],"Go Arch")
  observeCommand(f,"Go Arch"); arrive(f,1200,{"out"}); eq(#world.sent,sentBefore+3); eq(world.sent[#world.sent],"out")
  observeCommand(f,"out"); arrive(f,100,{"in"}); eq(hud.walker:active(),false); eq(#world.sent,sentBefore+3); eq(count(world.special),3)
end)

test("mapping walking reload and shutdown preserve personal map and runtime",function()
  local world={rooms={[999]={name="Personal room",owner="personal",coordinates={x=9,y=9,z=0}}},stubs={},links={}}
  local f=runtime(world); local personal=f:addAlias("^personal$",function() end)
  local hud=Main.new(f,Defaults); assert(hud:start())
  fire(f,"sysDataSendRequest","north"); f.gmcp.Room.Info={num=180,name="North",area=1,exits={"south"}}; fire(f,"gmcp.Room.Info")
  local walk=findAlias(f,"^walkto\\s+(\\d+)$"); assert(walk("176")); eq(f.sent,"s")
  f.gmcp.Room.Info={num=176,name="Start",area=1,exits={"north"}}; fire(f,"gmcp.Room.Info"); eq(hud.walker:active(),false)
  assert(hud:reload()); hud:shutdown()
  eq(world.rooms[999].name,"Personal room"); eq(world.rooms[999].owner,"personal"); eq(world.rooms[176].owner,"DragonsGateHUD")
  eq(f.aliases[personal]~=nil,true); eq(count(f.events),0); eq(count(f.triggers),0); eq(count(f.timers),0)
end)

test("mapstatus reports bounded mapper diagnostics without personal map data",function()
  local world={rooms={[999]={name="Secret personal room",owner="personal"}},stubs={},links={}}
  local f=runtime(world); local hud=Main.new(f,Defaults); assert(hud:start())
  hud.last_mapper_error="test failure"
  local status=findAlias(f,"^dghud mapstatus$")()
  eq(status.enabled,true); eq(status.current_room,176); eq(status.managed_count,1); eq(status.active_destination,"none"); eq(status.last_error,"test failure"); eq(status.last_status,"room 176")
  eq(f.map_status,status); eq(count(status),6); eq(status.personal,nil); eq(tostring(status):find("Secret personal room",1,true),nil)
  hud:shutdown()
end)

test("mapper settings control walking timeout and diagnostics enabled state",function()
  local settings=require("settings").merge(Defaults,{mapper={enabled=false,walk_timeout=23,minimum_height=150}})
  local f=runtime({rooms={},stubs={},links={}}); local hud=Main.new(f,settings); assert(hud:start())
  eq(hud.walker.timeout_seconds,23); eq(hud.current_layout.lower_mapper_min_height,150); eq(findAlias(f,"^dghud mapstatus$")().enabled,false); hud:shutdown()
end)
