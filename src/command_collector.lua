local Collector={}; Collector.__index=Collector
local SPECS={inventory={parser="parseInventory",snapshot="inventory"},stat={parser="parseStat",snapshot="stat"},info={parser="parseInfo",snapshot="info"},["info religion"]={parser="parseReligion",snapshot="religion"}}
function Collector.new(adapter,parser,onChange,onRoundtime)
  return setmetatable({adapter=adapter,parser=parser,onChange=onChange,onRoundtime=onRoundtime,snapshot={},sequence={"inventory","stat","info","info religion"},runtime={triggers={},events={}},started=false,refreshed=false},Collector)
end
function Collector:cancelActive()
  if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
  self.active=nil; self.sequence_index=nil
end
function Collector:begin(command,startup)
  if self.active then return false end
  self.active={command=command,lines={},startup=startup==true}
  self.timeout=self.adapter:schedule(30,function() self.timeout=nil; self:finish(nil) end)
  if startup then self.adapter:sendCommand(command) end
  return true
end
function Collector:refresh()
  if self.active or self.refreshed then return false end
  self.refreshed=true; self.sequence_index=1
  return self:begin(self.sequence[1],true)
end
function Collector:finish(lines)
  local active=self.active; if not active then return end
  if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
  self.active=nil
  if lines then
    local spec=SPECS[active.command]; local fn=spec and self.parser[spec.parser]
    local ok,result=pcall(fn,lines)
    if ok and result then self.snapshot[spec.snapshot]=result; self.onChange(self.snapshot,spec.snapshot) end
  end
  if active.startup then
    self.sequence_index=(self.sequence_index or 1)+1; local command=self.sequence[self.sequence_index]
    if command then self:begin(command,true) else self.sequence_index=nil end
  end
end
function Collector:onLine(value)
  value=tostring(value or "")
  local delay=tonumber(value:match("%[(%d+)%s+sec%.%s+delay%]")); if delay and self.onRoundtime then self.onRoundtime(delay) end
  if value:match("^Welcome to Dragon's Gate, .+!%s*$") and not self.refreshed then self:refresh(); return end
  if not self.active then return end
  self.active.lines[#self.active.lines+1]=value
  if self.parser.isComplete(self.active.command,self.active.lines) then self:finish(self.active.lines) end
end
function Collector:onOutgoing(command)
  command=tostring(command or ""):match("^%s*(.-)%s*$"):lower()
  if command=="inv" then command="inventory" end
  if not self.active and SPECS[command] then self:begin(command,false) end
end
function Collector:start()
  if self.started then return true end
  self.runtime.triggers[1]=self.adapter:addLineTrigger(function(value) self:onLine(value) end)
  self.runtime.events[1]=self.adapter:addEvent("sysDataSendRequest",function(_,command) self:onOutgoing(command) end)
  self.runtime.events[2]=self.adapter:addEvent("sysDisconnectionEvent",function() self:cancelActive(); self.refreshed=false end)
  self.started=true; return true
end
function Collector:shutdown()
  self:cancelActive()
  for _,id in ipairs(self.runtime.triggers) do self.adapter:killTrigger(id) end
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end
  self.runtime={triggers={},events={}}; self.refreshed=false; self.started=false; return true
end
return Collector
