local Main=require("main")
local Defaults=require("defaults")

local function count(values) local n=0; for _ in pairs(values) do n=n+1 end; return n end
local function runtime(world)
  local f={next=0,events={},aliases={},triggers={},timers={},world=world,statuses={},gmcp={Char={Vitals={hp=10,hp_max=10}},Room={Info={num=176,name="Start",area=1,exits={"north"}}}}}
  function f:getWindowSize() return 1920,1080 end
  function f:setBorders() end
  function f:createView() return {update=function() end,applyLayout=function() end,renderChat=function() end,setChatFilterCallback=function() end,delete=function() end} end
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
  function f:sendCommand(command) self.sent=command; return true end
  function f:reportMapperStatus(kind,message) self.statuses[#self.statuses+1]={kind=kind,message=message}; return true end
  function f:reportMapStatus(status) self.map_status=status; return status end
  function f:createMapAdapter()
    local map={world=self.world}
    function map:ensureRoom(room,coordinates)
      local old=self.world.rooms[room.id]
      if old and old.owner~="DragonsGateHUD" then return nil,"room "..room.id.." is not owned by DragonsGateHUD" end
      self.world.rooms[room.id]={name=room.name,owner="DragonsGateHUD",coordinates=coordinates,area=room.area_key}; return true
    end
    function map:ensureStub(id,direction) self.world.stubs[id..":"..direction]=true; return true end
    function map:connect(from,to,direction,reverse) self.world.links[from..":"..direction]=to; if reverse then self.world.links[to..":s"]=from end; return true end
    function map:setCurrent(id) self.current=id; return true end
    function map:center(id) self.current=id; return true end
    function map:coordinates(id) local room=self.world.rooms[id]; return room and room.coordinates end
    function map:roomsAt(area,x,y,z) local result={}; for id,room in pairs(self.world.rooms) do local p=room.coordinates; if room.owner=="DragonsGateHUD" and tostring(room.area)==tostring(area) and p and p.x==x and p.y==y and p.z==z then result[#result+1]=id end end; return result end
    function map:route(from,to) if self.world.links[from..":n"]==to then return {rooms={from,to},commands={"n"}} elseif self.world.links[from..":s"]==to then return {rooms={from,to},commands={"s"}} end; return nil,"no route" end
    return map
  end
  return f
end

local function findAlias(f,pattern) for _,alias in pairs(f.aliases) do if alias.pattern==pattern then return alias.fn end end end
local function fire(f,name,arg)
  for _,event in pairs(f.events) do if event.name==name then event.fn(nil,arg) end end
end

test("mapper release defaults are ready after version 0.2.49",function()
  eq(Defaults.version,"0.2.50"); eq(Defaults.mapper.enabled,true); eq(Defaults.mapper.walk_timeout,12)
  eq(Defaults.mapper.minimum_height,90); eq(Defaults.mapper.schema,1)
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
