local State=require("state"); local Events=require("events"); local Layout=require("layout"); local Parser=require("command_parser"); local Collector=require("command_collector"); local ChatParser=require("chat_parser"); local ChatHistory=require("chat_history"); local ChatController=require("chat_controller")
local Main={}; Main.__index=Main
function Main.new(adapter,settings) return setmetatable({adapter=adapter,settings=settings,runtime={events={},aliases={}},started=false,roundtime_display=0},Main) end
function Main.installChatApi(namespace)
  namespace.chat={
    capture=function(category,text,metadata)
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller; local chat=controller and controller.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:capture(category,text,metadata)
    end,
    setFilter=function(filter)
      local active=rawget(_G,"DGHUD"); local controller=active and active.controller; local chat=controller and controller.chat
      if not chat then return nil,"chatbox is not running" end
      return chat:setFilter(filter)
    end,
  }
  return namespace.chat
end
function Main:refresh() local normalized=State.normalize(self.adapter:getGMCP(),self.collector and self.collector.snapshot or {}); normalized.vitals.roundtime=self.roundtime_display or normalized.vitals.roundtime; self.view:update(normalized); self.last_state=normalized; return true end
function Main:characterName() return self.last_state and self.last_state.character and self.last_state.character.full_name or nil end
function Main:startChat()
  local settings=self.settings.chat or {}
  local storage=self.adapter:createChatStorage(settings.visible_limit or 1000)
  self.chat=ChatController.new(self.adapter,ChatParser,ChatHistory.new(settings.visible_limit or 1000,settings.dedupe_seconds or 3),storage,function(entries,categories,filter)
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
  self.view=self.adapter:createView(self.settings)
  self:applyResponsiveLayout()
  self.collector=Collector.new(self.adapter,Parser,function() self:refresh() end,function(value) self:onRoundtime(value) end); self.collector:start()
  if self.adapter.isCharacterActive and self.adapter:isCharacterActive() then self.collector:refresh() end
  for _,name in ipairs(Events.gmcp) do self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(name,function() self:refresh() end) end
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent("sysWindowResizeEvent",function() self:applyResponsiveLayout() end)
  local commands={function() if self.updater then self.updater:check() end end,function() if self.updater then self.updater:update() end end,function() self:reload() end,function() if self.adapter.openSettings then self.adapter:openSettings() end end,function() if self.adapter.requestPurge then self.adapter:requestPurge() end end}
  for i,pattern in ipairs(Events.aliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(pattern,commands[i]) end
  self.started=true; local ok,err=pcall(function() self:refresh() end); if not ok then self:shutdown(); return nil,err end
  local chatStarted,chatErr=self:startChat(); if not chatStarted then self:shutdown(); return nil,chatErr end; return true
end
function Main:shutdown()
  if self.roundtime_timer then self.adapter:cancelTimer(self.roundtime_timer); self.roundtime_timer=nil end
  local chat=self.chat; self.chat=nil; if chat then chat:shutdown() end
  if self.collector then self.collector:shutdown(); self.collector=nil end
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end; for _,id in ipairs(self.runtime.aliases) do self.adapter:killAlias(id) end
  self.runtime={events={},aliases={}}; if self.view then self.view:delete(); self.view=nil end
  if self.original_borders then self.adapter:setBorders(self.original_borders[1],self.original_borders[2],self.original_borders[3],self.original_borders[4]); self.original_borders=nil end
  self.started=false; return true
end
function Main:reload() self:shutdown(); return self:start() end
function Main:healthCheck() if not self.started or not self.view or not self.collector or not self.collector.started or not self.chat or not self.chat.started or not self.chat.trigger or #self.runtime.events~=(#Events.gmcp+1) then return nil,"HUD is not healthy" end; local ok=pcall(function() self:refresh() end); if not ok then return nil,"state refresh failed" end; return true end
return Main
