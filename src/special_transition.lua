local Special={}; Special.__index=Special

local exclusions={
  dghud=true,walkto=true,walkstop=true,mapcenter=true,
  inventory=true,inv=true,stat=true,info=true,look=true,l=true,who=true,
  say=true,whisper=true,link=true,
}

local function normalize(value)
  return tostring(value or ""):lower():match("^%s*(.-)%s*$")
end

local function positive(value)
  local number=tonumber(value)
  return number and number==number and number~=math.huge and number~=-math.huge and number>0 and number%1==0
end

local function excluded(value)
  return exclusions[value:match("^(%S+)") or ""]==true
end

function Special.new(model,adapter,timeoutSeconds,onStatus)
  return setmetatable({model=model,adapter=adapter,timeout_seconds=tonumber(timeoutSeconds) or 3,onStatus=onStatus or function() end},Special)
end

function Special:status(kind)
  pcall(self.onStatus,kind)
end

function Special:pending()
  return self.candidate
end

function Special:cancel(reason)
  local timer=self.timer
  local owned=timer~=nil or self.candidate~=nil
  self.timer=nil; self.candidate=nil
  if timer~=nil then
    local callOk,ok,err=pcall(self.adapter.cancelTimer,self.adapter,timer)
    if not callOk then return nil,ok end
    if ok==false or ok==nil and err then return nil,err or "special transition timer cancellation failed" end
  end
  if owned and reason then self:status(reason) end
  return true
end

function Special:onOutgoing(command,originID)
  self:cancel("replaced")
  local value=normalize(command)
  if not positive(originID) or value=="" or self.model.direction(value) or excluded(value) then return nil end
  local timer,err
  local callOk
  callOk,timer,err=pcall(self.adapter.schedule,self.adapter,self.timeout_seconds,function()
    if self.timer==timer then self.timer=nil; self.candidate=nil; self:status("expired") end
  end)
  if not callOk then err=timer; timer=nil end
  if not timer then return nil,err or "special transition timer could not be created" end
  self.timer=timer; self.candidate={from=tonumber(originID),command=value}
  return true
end

function Special:onRoom(roomID)
  local destination=positive(roomID) and tonumber(roomID) or nil
  if not self.candidate or not destination or destination==self.candidate.from then return nil end
  local result={from=self.candidate.from,to=destination,command=self.candidate.command,kind="special"}
  local ok,err=self:cancel("confirmed")
  if not ok then return nil,err end
  return result
end

function Special:shutdown()
  return self:cancel("shutdown")
end

return Special
