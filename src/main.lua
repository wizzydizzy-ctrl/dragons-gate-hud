local State=require("state"); local Events=require("events"); local Layout=require("layout"); local Parser=require("command_parser"); local Collector=require("command_collector")
local Main={}; Main.__index=Main
function Main.new(adapter,settings) return setmetatable({adapter=adapter,settings=settings,runtime={events={},aliases={}},started=false},Main) end
function Main:refresh() local normalized=State.normalize(self.adapter:getGMCP(),self.collector and self.collector.snapshot or {}); self.view:update(normalized); self.last_state=normalized; return true end
function Main:applyResponsiveLayout()
  local width,height=self.adapter:getWindowSize(); local layout=Layout.compute(width,height); self.current_layout=layout
  self.adapter:setBorders(layout.left,layout.top,layout.right,layout.bottom)
  if self.view and self.view.applyLayout then self.view:applyLayout(layout) end; return layout
end
function Main:start()
  if self.started then return true end
  self.original_borders={0,0,0,0}
  self.view=self.adapter:createView(self.settings)
  self:applyResponsiveLayout()
  self.collector=Collector.new(self.adapter,Parser,function() self:refresh() end); self.collector:start()
  for _,name in ipairs(Events.gmcp) do self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent(name,function() self:refresh() end) end
  self.runtime.events[#self.runtime.events+1]=self.adapter:addEvent("sysWindowResizeEvent",function() self:applyResponsiveLayout() end)
  local commands={function() if self.updater then self.updater:check() end end,function() if self.updater then self.updater:update() end end,function() self:reload() end,function() if self.adapter.openSettings then self.adapter:openSettings() end end,function() if self.adapter.requestPurge then self.adapter:requestPurge() end end}
  for i,pattern in ipairs(Events.aliases) do self.runtime.aliases[#self.runtime.aliases+1]=self.adapter:addAlias(pattern,commands[i]) end
  self.started=true; local ok,err=pcall(function() self:refresh() end); if not ok then self:shutdown(); return nil,err end; return true
end
function Main:shutdown()
  if self.collector then self.collector:shutdown(); self.collector=nil end
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end; for _,id in ipairs(self.runtime.aliases) do self.adapter:killAlias(id) end
  self.runtime={events={},aliases={}}; if self.view then self.view:delete(); self.view=nil end
  if self.original_borders then self.adapter:setBorders(self.original_borders[1],self.original_borders[2],self.original_borders[3],self.original_borders[4]); self.original_borders=nil end
  self.started=false; return true
end
function Main:reload() self:shutdown(); return self:start() end
function Main:healthCheck() if not self.started or not self.view or not self.collector or not self.collector.started or #self.runtime.events~=(#Events.gmcp+1) then return nil,"HUD is not healthy" end; local ok=pcall(function() self:refresh() end); if not ok then return nil,"state refresh failed" end; return true end
return Main
