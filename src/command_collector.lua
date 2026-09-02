local Collector={}; Collector.__index=Collector
local SPECS={inventory={parser="parseInventory",snapshot="inventory"},stat={parser="parseStat",snapshot="stat"},info={parser="parseInfo",snapshot="info"},["info religion"]={parser="parseReligion",snapshot="religion"},skill={parser="parseSkills",snapshot="skills"},time={parser="parseTime",snapshot="time"}}
local PROMPT_NUDGE={inventory=true,stat=true,["info religion"]=true,skill=true,time=true}
function Collector.new(adapter,parser,onChange,onRoundtime,onCharacterEntry)
  return setmetatable({adapter=adapter,parser=parser,onChange=onChange,onRoundtime=onRoundtime,onCharacterEntry=onCharacterEntry,snapshot={},sequence={"inventory","stat","info","info religion","skill","time"},runtime={triggers={},events={}},started=false,refreshed=false,prompt_nudge_delay=.15,response_timeout=8},Collector)
end
function Collector:cancelActive()
  if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
  if self.prompt_nudge then self.adapter:cancelTimer(self.prompt_nudge); self.prompt_nudge=nil end
  self.active=nil; self.sequence_index=nil; self.retry_startup=false
end
function Collector:schedulePromptNudge(command)
  if not PROMPT_NUDGE[command] then return end
  self.prompt_nudge=self.adapter:schedule(self.prompt_nudge_delay,function()
    self.prompt_nudge=nil
    if self.active and self.active.command==command then self.adapter:sendCommand("") end
  end)
end
function Collector:begin(command,startup)
  if self.active then return false end
  self.active={command=command,lines={},startup=startup==true}
  self.timeout=self.adapter:schedule(self.response_timeout,function() self.timeout=nil; self:finish(nil) end)
  if startup then self.sending_startup_command=command; self.adapter:sendCommand(command); self.sending_startup_command=nil end
  self:schedulePromptNudge(command)
  return true
end
function Collector:refresh()
  if self.active or self.refreshed then return false end
  self.refreshed=true; self.sequence_index=1
  return self:begin(self.sequence[1],true)
end
function Collector:forceRefresh()
  if self.active then return false end
  self.refreshed=false
  return self:refresh()
end
function Collector:finish(lines)
  local active=self.active; if not active then return end
  if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
  if self.prompt_nudge then self.adapter:cancelTimer(self.prompt_nudge); self.prompt_nudge=nil end
  self.active=nil
  if lines then
    local spec=SPECS[active.command]; local fn=spec and self.parser[spec.parser]
    local ok,result=pcall(fn,lines)
    if ok and result then self.snapshot[spec.snapshot]=result; self.onChange(self.snapshot,spec.snapshot) end
  end
  if self.retry_startup and self.sequence_index then
    self.retry_startup=false; self:begin(self.sequence[self.sequence_index],true)
  elseif active.startup or self.sequence_index then
    self.sequence_index=(self.sequence_index or 1)+1; local command=self.sequence[self.sequence_index]
    if command then self:begin(command,true) else self.sequence_index=nil end
  end
end
function Collector:onLine(value)
  value=tostring(value or "")
  local delay=tonumber(value:match("%[(%d+)%s+sec%.%s+delay%]")); if delay and self.onRoundtime then self.onRoundtime(delay) end
  local character=value:match("^Welcome to Dragon's Gate, (.+)!%s*$")
  if character then
    if self.active_character==character then return end
    self:cancelActive(); self.refreshed=false; self.active_character=character; self.snapshot={}; self.onChange(self.snapshot,"reset")
    if self.onCharacterEntry then self.onCharacterEntry(character) else self:refresh() end
    return
  end
  if not self.active then return end
  if #self.active.lines==1 and self.active.lines[1]:match("^>%s*$") and not value:match("^>%s*$") then self.active.lines={} end
  self.active.lines[#self.active.lines+1]=value
  if self.parser.isComplete(self.active.command,self.active.lines) or (value:match("^>%s*$") and #self.active.lines>1) then self:finish(self.active.lines) end
end
function Collector:onOutgoing(command)
  command=tostring(command or ""):match("^%s*(.-)%s*$"):lower()
  if command=="inv" then command="inventory" end
  if not SPECS[command] or self.sending_startup_command==command then return end
  if self.active then
    if self.active.startup then self.retry_startup=true end
    if self.timeout then self.adapter:cancelTimer(self.timeout); self.timeout=nil end
    if self.prompt_nudge then self.adapter:cancelTimer(self.prompt_nudge); self.prompt_nudge=nil end
    self.active=nil
  end
  self:begin(command,false)
end
function Collector:start()
  if self.started then return true end
  self.runtime.triggers[1]=self.adapter:addLineTrigger(function(value) self:onLine(value) end)
  self.runtime.events[1]=self.adapter:addEvent("sysDataSendRequest",function(_,command) self:onOutgoing(command) end)
  self.runtime.events[2]=self.adapter:addEvent("sysDisconnectionEvent",function() self:cancelActive(); self.refreshed=false; self.active_character=nil end)
  self.started=true; return true
end
function Collector:shutdown()
  self:cancelActive()
  for _,id in ipairs(self.runtime.triggers) do self.adapter:killTrigger(id) end
  for _,id in ipairs(self.runtime.events) do self.adapter:killEvent(id) end
  self.runtime={triggers={},events={}}; self.refreshed=false; self.active_character=nil; self.started=false; return true
end
return Collector
