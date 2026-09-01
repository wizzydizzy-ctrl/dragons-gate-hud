local State=require("state"); local Events=require("events"); local Layout=require("layout"); local Parser=require("command_parser"); local Collector=require("command_collector"); local ChatParser=require("chat_parser"); local ChatHistory=require("chat_history"); local ChatController=require("chat_controller"); local MapperModel=require("mapper_model"); local MapAdapter=require("map_adapter"); local Automapper=require("automapper")
local Main={}; Main.__index=Main
function Main.new(adapter,settings) return setmetatable({adapter=adapter,settings=settings,runtime={events={},aliases={}},started=false,roundtime_display=0},Main) end
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
  self.roundtime_display=value; self:refresh(); self:scheduleRoundtimeTick(); return true
end
function Main:applyResponsiveLayout()
  local width,height=self.adapter:getWindowSize(); local layout=Layout.compute(width,height,self.settings.chat); self.current_layout=layout
  self.adapter:setBorders(layout.left,layout.top,layout.right,layout.bottom)
  if self.view and self.view.applyLayout then self.view:applyLayout(layout) end; return layout
end
function Main:start()
  if self.started then return true end
  self.original_borders={0,0,0,0}
  local mapOk,map,mapErr=pcall(function() if self.adapter.createMapAdapter then return self.adapter:createMapAdapter() end; return MapAdapter.new(MapAdapter.mudletApi(_G)) end)
  if not mapOk then self:shutdown(); return nil,map end
  if not map then self:shutdown(); return nil,mapErr or "map adapter construction failed" end
  self.map=map
  local factory=self.createAutomapper or function(_,model,adapter,status) return Automapper.new(model,adapter,status) end
  local automapperOk,automapper,automapperErr=pcall(factory,self,MapperModel,self.map,function(kind,message)
    if self.adapter.reportMapperStatus then self.adapter:reportMapperStatus(kind,message) end
  end)
  if not automapperOk then self:shutdown(); return nil,automapper end
  if not automapper then self:shutdown(); return nil,automapperErr or "automapper construction failed" end
  self.automapper=automapper
  self.view=self.adapter:createView(self.settings)
  self:applyResponsiveLayout()
  self.collector=Collector.new(self.adapter,Parser,function() self:refresh() end,function(value) self:onRoundtime(value) end); self.collector:start()
  if self.adapter.isCharacterActive and self.adapter:isCharacterActive() then self.collector:refresh() end
  for _,name in ipairs(Events.gmcp) do self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(name,function() self:refresh() end) end
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.room,function()
    local data=self.adapter:getGMCP(); self.automapper:onRoom(data and data.Room and data.Room.Info); self:refresh()
  end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.wrong,function(_,direction) self.automapper:onWrongDirection(direction); self:refresh() end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.outgoing,function(_,command) self.automapper:onOutgoing(command) end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(Events.mapper.disconnect,function() self.automapper:onDisconnect() end)
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent("sysWindowResizeEvent",function() self:applyResponsiveLayout() end)
  local commands={function() if self.updater then self.updater:check() end end,function() if self.updater then self.updater:update() end end,function() self:reload() end,function() if self.adapter.openSettings then self.adapter:openSettings() end end,function() if self.adapter.requestPurge then self.adapter:requestPurge() end end,function() return self:reportChatStatus() end}
  for i,pattern in ipairs(Events.aliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(pattern,commands[i]) end
  self.started=true; local ok,err=pcall(function() local data=self.adapter:getGMCP(); if data and data.Room and data.Room.Info then self.automapper:onRoom(data.Room.Info) end; self:refresh() end); if not ok then self:shutdown(); return nil,err end
  local chatStarted,chatErr=self:startChat(); if not chatStarted then self:shutdown(); return nil,chatErr end; return true
end
function Main:shutdown()
  if self.roundtime_timer then self.adapter:cancelTimer(self.roundtime_timer); self.roundtime_timer=nil end
  local chat=self.chat; self.chat=nil; if chat then chat:shutdown() end
  if self.collector then self.collector:shutdown(); self.collector=nil end
  if self.automapper then self.automapper:shutdown(); self.automapper=nil end; self.map=nil
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end; for _,id in ipairs(self.runtime.aliases) do self.adapter:killAlias(id) end
  self.runtime={events={},aliases={}}; if self.view then self.view:delete(); self.view=nil end
  if self.original_borders then self.adapter:setBorders(self.original_borders[1],self.original_borders[2],self.original_borders[3],self.original_borders[4]); self.original_borders=nil end
  self.started=false; return true
end
function Main:reload() self:shutdown(); return self:start() end
function Main:healthCheck()
  local chatEnabled=not (self.settings.chat and self.settings.chat.enabled==false)
  if not self.started or not self.view or not self.collector or not self.collector.started or not self.automapper or (chatEnabled and (not self.chat or not self.chat.started or not self.chat.trigger)) or #self.runtime.events~=(#Events.gmcp+5) then return nil,"HUD is not healthy" end
  local ok=pcall(function() self:refresh() end); if not ok then return nil,"state refresh failed" end; return true
end
return Main
