local State=require("state"); local Events=require("events"); local Layout=require("layout"); local Parser=require("command_parser"); local Collector=require("command_collector"); local ChatParser=require("chat_parser"); local ChatHistory=require("chat_history"); local ChatController=require("chat_controller"); local MapperModel=require("mapper_model"); local MapAdapter=require("map_adapter"); local Automapper=require("automapper"); local SpecialTransition=require("special_transition"); local MapWalker=require("map_walker")
local Main={}; Main.__index=Main
function Main.new(adapter,settings) return setmetatable({adapter=adapter,settings=settings,runtime={events={},aliases={}},started=false,roundtime_display=0,managed_rooms={}},Main) end
function Main.installChatApi(namespace)
  local chat=type(namespace.chat)=="table" and namespace.chat or {}
  namespace.chat=chat
  chat.capture=function(category,text,metadata)
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller; local chat=controller and controller.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:capture(category,text,metadata)
    end
  chat.setFilter=function(filter)
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller; local chat=controller and controller.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:setFilter(filter)
    end
  chat.status=function()
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller
      if not controller then return nil,"HUD is not running" end
      return controller:chatStatus()
    end
  return chat
end
function Main:refresh() local normalized=State.normalize(self.adapter:getGMCP(),self.collector and self.collector.snapshot or {}); normalized.vitals.roundtime=self.roundtime_display or normalized.vitals.roundtime; self.view:update(normalized); self.last_state=normalized; if self.chat then self.chat:syncCharacter() end; return true end
function Main:characterName() return self.last_state and self.last_state.character and self.last_state.character.full_name or nil end
function Main:onCharacterEntry()
  if self.character_entry_started then return false end
  self.character_entry_started=true
  local function refreshCommands()
    local collector=self.collector
    if collector then collector:refresh() end
  end
  if not self.updater or not self.updater.checkAtCharacterEntry then refreshCommands(); return true end
  local ok,err=self.updater:checkAtCharacterEntry(function() refreshCommands() end)
  if not ok then refreshCommands() end
  return ok,err
end
function Main:startChat()
  local settings=self.settings.chat or {}
  if settings.enabled==false then return true end
  local visibleLimit=ChatHistory.visibleLimit(settings.visible_limit)
  local storage=self.adapter:createChatStorage(visibleLimit)
  self.chat=ChatController.new(self.adapter,ChatParser,ChatHistory.new(visibleLimit,settings.dedupe_seconds or 3),storage,function(entries,categories,filter)
    if self.view and self.view.renderChat then self.view:renderChat(entries,categories,filter) end
  end,function() return self:characterName() end)
  if self.view and self.view.setChatFilterCallback then
    self.view:setChatFilterCallback(function(category)
      local chat=self.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:setFilter(category)
    end)
  end
  return self.chat:start()
end
function Main:chatStatus()
  if not self.chat then return {active_filter="OFF",visible_count=0,storage_key=nil,last_storage_error=nil} end
  return self.chat:status()
end
function Main:reportChatStatus()
  local status=self:chatStatus()
  local reporter=self.adapter and self.adapter.reportChatStatus
  if type(reporter)=="function" then
    local ok,result=pcall(reporter,self.adapter,status)
    if ok then return result end
  end
  return status
end
function Main:scheduleRoundtimeTick()
  if self.roundtime_timer or self.roundtime_display<=0 then return end
  self.roundtime_timer=self.adapter:schedule(1,function() self.roundtime_timer=nil; self.roundtime_display=math.max(0,self.roundtime_display-1); self:refresh(); self:scheduleRoundtimeTick() end)
end
function Main:onRoundtime(value)
  value=math.max(0,math.floor(tonumber(value) or 0)); if self.roundtime_timer then self.adapter:cancelTimer(self.roundtime_timer); self.roundtime_timer=nil end
  self.roundtime_display=value; if self.walker then self.walker:onRoundtime(value) end; self:refresh(); self:scheduleRoundtimeTick(); return true
end
function Main:applyResponsiveLayout()
  local width,height=self.adapter:getWindowSize(); local layout=Layout.compute(width,height,self.settings.chat,self.settings.mapper); self.current_layout=layout
  self.adapter:setBorders(layout.console_left or layout.left,layout.top,layout.console_right or layout.right,layout.bottom)
  if self.view and self.view.applyLayout then self.view:applyLayout(layout) end; return layout
end
function Main:mapperEnabled() return not (self.settings.mapper and self.settings.mapper.enabled==false) end
function Main:mapperStatus(kind,message,isError)
  self.last_mapper_status=tostring(message or kind or "none")
  if kind=="invalid_room" or kind=="ownership_conflict" or kind=="error" or isError==true then self.last_mapper_error=tostring(message or "unknown mapper error") end
  if self.adapter.reportMapperStatus then self.adapter:reportMapperStatus(kind,message) end
end
function Main:mapToolbarAction(action)
  local current=self.automapper and self.automapper:currentRoom()
  if not current then local err="current room is unavailable"; self:mapperStatus("error",err,true); return nil,err end
  local callOk,result,err=pcall(function()
    if action=="center" then return self.map:center(current) end
    if action=="larger" or action=="smaller" then
      local settings=self.settings.mapper or {}
      return self.map:zoom(current,action,settings.zoom_step,settings.zoom_min,settings.zoom_max)
    end
    return nil,"unknown map toolbar action "..tostring(action)
  end)
  if not callOk then err=result; result=nil end
  if result==nil or result==false then err=err or "map toolbar action failed"; self:mapperStatus("error",err,true); return nil,err end
  if action=="center" then self:mapperStatus("centered","Map centered on room "..tostring(current))
  else self:mapperStatus("zoom","Map zoom "..tostring(result)) end
  return result
end
function Main:callSpecialTransition(method,...)
  local tracker=self.special_transition
  if not tracker then return nil end
  local callOk,result,err=pcall(tracker[method],tracker,...)
  if not callOk then err=result; result=nil end
  if err then self:mapperStatus("error",err,true) end
  return result,err
end
function Main:callAutomapper(method,...)
  local callOk,result,err=pcall(self.automapper[method],self.automapper,...)
  if not callOk then
    err=result; result=nil
    pcall(self.automapper.onWrongDirection,self.automapper)
    self:mapperStatus("error",err,true)
  end
  return result,err
end
function Main:mapStatus()
  local managed=0; for _ in pairs(self.managed_rooms or {}) do managed=managed+1 end
  return {
    enabled=self:mapperEnabled(),
    current_room=self.automapper and self.automapper:currentRoom() or nil,
    managed_count=managed,
    active_destination=self.walker and self.walker.destination or "none",
    last_error=self.last_mapper_error or "none",
    last_status=self.last_mapper_status or "none",
  }
end
function Main:reportMapStatus()
  local status=self:mapStatus()
  if self.adapter and type(self.adapter.reportMapStatus)=="function" then return self.adapter:reportMapStatus(status) end
  local line="enabled="..tostring(status.enabled).." current room="..tostring(status.current_room or "none").." managed="..tostring(status.managed_count).." destination="..tostring(status.active_destination or "none").." last status="..tostring(status.last_status).." last error="..tostring(status.last_error)
  if type(_G.cecho)=="function" then pcall(_G.cecho,"\n<gold>[DGHUD Map]<reset> "..line.."\n") end
  return status
end
function Main:routeShape(fromID,toID,route)
  if type(route)~="table" then return nil,"invalid map route" end
  local commands=type(route.commands)=="table" and route.commands or route
  local path=type(route.rooms)=="table" and route.rooms or (type(_G.speedWalkPath)=="table" and _G.speedWalkPath or nil)
  if not path then return nil,"map route did not provide room numbers" end
  local rooms={}; for index,value in ipairs(path) do rooms[index]=tonumber(value) end
  local copiedCommands={}; for index,value in ipairs(commands) do copiedCommands[index]=value end
  if #rooms==#copiedCommands then table.insert(rooms,1,tonumber(fromID)) end
  if #rooms~=#copiedCommands+1 then return nil,"map route rooms and commands do not match" end
  if tonumber(rooms[1])~=tonumber(fromID) or tonumber(rooms[#rooms])~=tonumber(toID) then return nil,"map route endpoints do not match" end
  return {rooms=rooms,commands=copiedCommands}
end
function Main:walkTo(destination,providedRoute)
  if not self:mapperEnabled() then return nil,"mapper is disabled" end
  destination=tonumber(destination)
  if not destination or destination<=0 or destination%1~=0 then return nil,"destination room must be a positive integer" end
  local current=self.automapper and self.automapper:currentRoom()
  if not current then return nil,"current room is unavailable" end
  local route,routeErr=providedRoute,nil; if not route then route,routeErr=self.map:route(current,destination) end
  if not route then return nil,routeErr or "route unavailable" end
  local shaped,shapeErr=self:routeShape(current,destination,route); if not shaped then return nil,shapeErr end
  local ok,err=self.walker:start(shaped,destination); if not ok then return nil,err end
  return true
end
function Main:installMapClickHook()
  if not self:mapperEnabled() then return true end
  self.previous_speed_walk=rawget(_G,"doSpeedWalk")
  local controller=self
  self.speed_walk_hook=function()
    local path=type(_G.speedWalkPath)=="table" and _G.speedWalkPath or nil
    local destination=path and path[#path] or nil
    local owned=destination~=nil and controller.map and type(controller.map.isOwned)=="function"
    if owned then for _,roomID in ipairs(path) do if not controller.map:isOwned(tonumber(roomID)) then owned=false; break end end end
    if not owned then
      if type(controller.previous_speed_walk)=="function" then return controller.previous_speed_walk() end
      return nil,"clicked route is not owned by DragonsGateHUD"
    end
    return controller:walkTo(destination,{rooms=path,commands=_G.speedWalkDir or {}})
  end
  _G.doSpeedWalk=self.speed_walk_hook
end
function Main:removeMapClickHook()
  if self.speed_walk_hook and rawget(_G,"doSpeedWalk")==self.speed_walk_hook then _G.doSpeedWalk=self.previous_speed_walk end
  self.speed_walk_hook=nil; self.previous_speed_walk=nil
end
function Main:start()
  if self.started then return true end
  self.original_borders={0,0,0,0}
  local mapOk,map,mapErr=pcall(function() if self.adapter.createMapAdapter then return self.adapter:createMapAdapter() end; return MapAdapter.new(MapAdapter.mudletApi(_G)) end)
  if not mapOk then self:shutdown(); return nil,map end
  if not map then self:shutdown(); return nil,mapErr or "map adapter construction failed" end
  self.map=map
  if self.adapter.suppressDefaultMapInfo then
    local infoOk,infoResult,infoErr=pcall(self.adapter.suppressDefaultMapInfo,self.adapter)
    if not infoOk then self:mapperStatus("warning","Map information cleanup failed: "..tostring(infoResult),true)
    elseif infoResult==nil then self:mapperStatus("warning","Map information cleanup failed: "..tostring(infoErr),true) end
  end
  if type(self.map.clearOwnedRoomNames)=="function" then
    local cleanupOk,cleanupResult,cleanupErr=pcall(self.map.clearOwnedRoomNames,self.map)
    if not cleanupOk then self:mapperStatus("warning","Map label cleanup failed: "..tostring(cleanupResult),true)
    elseif cleanupResult==nil then self:mapperStatus("warning","Map label cleanup failed: "..tostring(cleanupErr),true) end
  end
  local factory=self.createAutomapper or function(_,model,adapter,status) return Automapper.new(model,adapter,status) end
  local automapperOk,automapper,automapperErr=pcall(factory,self,MapperModel,self.map,function(kind,message) self:mapperStatus(kind,message) end)
  if not automapperOk then self:shutdown(); return nil,automapper end
  if not automapper then self:shutdown(); return nil,automapperErr or "automapper construction failed" end
  self.automapper=automapper
  self.special_transition=SpecialTransition.new(MapperModel,self.adapter,(self.settings.mapper and self.settings.mapper.special_timeout) or 3)
  local walkerAdapter={owner=self}
  function walkerAdapter:sendCommand(command)
    self.owner.generated_command=command
    local ok,err=self.owner.adapter:sendCommand(command)
    if ok==false or err~=nil then self.owner.generated_command=nil; return nil,err or "movement command failed" end
    return true
  end
  function walkerAdapter:validateStep(fromID,toID,command) return self.owner.map:validateRouteStep(fromID,toID,command) end
  function walkerAdapter:schedule(delay,callback) return self.owner.adapter:schedule(delay,callback) end
  function walkerAdapter:cancelTimer(id) return self.owner.adapter:cancelTimer(id) end
  function walkerAdapter:clearGenerated() self.owner.generated_command=nil end
  self.walker=MapWalker.new(walkerAdapter,function(kind,message,isError) self:mapperStatus(kind,message,isError) end,(self.settings.mapper and self.settings.mapper.walk_timeout) or 12)
  local initialVitals=self.adapter:getGMCP(); initialVitals=initialVitals and initialVitals.Char and initialVitals.Char.Vitals
  self.walker:onRoundtime(initialVitals and initialVitals.roundtime or 0)
  self:installMapClickHook()
  local startupOk,startupErr=pcall(function()
  self.view=self.adapter:createView(self.settings)
  if self.view.setMapZoomCallback then self.view:setMapZoomCallback(function(action) return self:mapToolbarAction(action) end) end
  self:applyResponsiveLayout()
  self.collector=Collector.new(self.adapter,Parser,function() self:refresh() end,function(value) self:onRoundtime(value) end,function() self:onCharacterEntry() end); local collectorOk,collectorErr=self.collector:start(); if not collectorOk then error(collectorErr,0) end
  if self.adapter.isCharacterActive and self.adapter:isCharacterActive() then self:onCharacterEntry() end
  for _,name in ipairs(Events.gmcp) do local eventName=name; self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(eventName,function()
    if eventName=="gmcp.Char.Vitals" and self.walker then local data=self.adapter:getGMCP(); local vitals=data and data.Char and data.Char.Vitals; self.walker:onRoundtime(vitals and vitals.roundtime or 0) end
    self:refresh()
  end) end
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.room,function()
    local data=self.adapter:getGMCP(); local info=data and data.Room and data.Room.Info; local ok,err
    if self:mapperEnabled() then
      local transition=self:callSpecialTransition("onRoom",info and info.num)
      if transition then self:callAutomapper("onSpecialTransition",transition) end
      ok,err=self:callAutomapper("onRoom",info); if ok and info and tonumber(info.num) then self.managed_rooms[tonumber(info.num)]=true end
    else self:callSpecialTransition("cancel","disabled"); ok=true end
    if self.walker and self.walker:active() then
      local vitals=data and data.Char and data.Char.Vitals; self.walker:onRoundtime(vitals and vitals.roundtime or 0)
      if not ok then self.walker:stop(err or "room mapping failed",true) else self.walker:onRoom(info and info.num) end
    end; self:refresh()
  end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.wrong,function(_,direction) self:callSpecialTransition("cancel","wrong_direction"); self.automapper:onWrongDirection(direction); self.walker:onWrongDirection(); self:refresh() end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.outgoing,function(_,command)
    local canonical=MapperModel.direction(command); local generated=command==self.generated_command
    if generated then self.generated_command=nil end
    self.walker:onManualMovement(command,generated)
    if self:mapperEnabled() then
      self.automapper:onOutgoing(command)
      if canonical then self:callSpecialTransition("cancel","direction") else self:callSpecialTransition("onOutgoing",command,self.automapper:currentRoom()) end
    else self:callSpecialTransition("cancel","disabled") end
  end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.disconnect,function() self.character_entry_started=false; self:callSpecialTransition("cancel","disconnect"); self.automapper:onDisconnect(); self.walker:stop("disconnected") end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent("sysWindowResizeEvent",function() self:applyResponsiveLayout() end)
  local function aliasArgument(value) return value or (type(_G.matches)=="table" and _G.matches[2]) end
  local commands={function() if self.updater then self.updater:check() end end,function() if self.updater then self.updater:update() end end,function() self:reload() end,function() if self.adapter.openSettings then self.adapter:openSettings() end end,function() if self.adapter.requestPurge then self.adapter:requestPurge() end end,function() return self:reportChatStatus() end,function(value) return self:walkTo(aliasArgument(value)) end,function() return self.walker:stop("requested") end,function() local room=self.automapper:currentRoom(); if not room then return nil,"current room is unavailable" end; return self.map:center(room) end}
  for i,pattern in ipairs(Events.aliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(pattern,commands[i]) end
  self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias("^dghud mapstatus$",function() return self:reportMapStatus() end)
  self.started=true; local data=self.adapter:getGMCP(); if self:mapperEnabled() and data and data.Room and data.Room.Info then local mapped=self.automapper:onRoom(data.Room.Info); if mapped and tonumber(data.Room.Info.num) then self.managed_rooms[tonumber(data.Room.Info.num)]=true end end; self:refresh()
  local chatStarted,chatErr=self:startChat(); if not chatStarted then error(chatErr,0) end
  end)
  if not startupOk then pcall(function() self:shutdown() end); return nil,startupErr end
  return true
end
function Main:shutdown()
  if self.roundtime_timer then self.adapter:cancelTimer(self.roundtime_timer); self.roundtime_timer=nil end
  local chat=self.chat; self.chat=nil; if chat then chat:shutdown() end
  if self.collector then self.collector:shutdown(); self.collector=nil end
  if self.walker then self.walker:shutdown(); self.walker=nil end; self.generated_command=nil; self:removeMapClickHook()
  if self.special_transition then self:callSpecialTransition("shutdown"); self.special_transition=nil end
  if self.automapper then self.automapper:shutdown(); self.automapper=nil end; self.map=nil
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end; for _,id in ipairs(self.runtime.aliases) do self.adapter:killAlias(id) end
  self.runtime={events={},aliases={}}; if self.view then self.view:delete(); self.view=nil end
  if self.original_borders then self.adapter:setBorders(self.original_borders[1],self.original_borders[2],self.original_borders[3],self.original_borders[4]); self.original_borders=nil end
  self.character_entry_started=false; self.started=false; return true
end
function Main:reload() self:shutdown(); return self:start() end
function Main:healthCheck()
  local chatEnabled=not (self.settings.chat and self.settings.chat.enabled==false)
  if not self.started or not self.view or not self.collector or not self.collector.started or not self.automapper or not self.special_transition or (chatEnabled and (not self.chat or not self.chat.started or not self.chat.trigger)) or #self.runtime.events~=(#Events.gmcp+5) then return nil,"HUD is not healthy" end
  local ok=pcall(function() self:refresh() end); if not ok then return nil,"state refresh failed" end; return true
end
return Main
