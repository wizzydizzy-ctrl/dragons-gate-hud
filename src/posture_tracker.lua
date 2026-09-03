local Posture={}; Posture.__index=Posture

local standing={"You stand up%f[%A]","You are already standing!"}
local sitting={"You sit down%f[%A]","You sit up%.","You are already seated!","You are seated%.","You lie down%.","You stumble and fall down!","You fall back and lie down%.","You pass out!","You pass out from blood loss%.","You pass out from the drain!","You faint dead away%.","You lose consciousness%."}
local unconsciousOn={"You fall asleep%.","You lose consciousness%.","You are unconscious, you can't do that!"}

local function contains(line,patterns)
  for _,pattern in ipairs(patterns) do if line:find(pattern) then return true end end
  return false
end

function Posture.new(adapter,onChange)
  local self=setmetatable({adapter=adapter,onChange=onChange,state={standing=nil,sitting=nil,unconscious=nil}},Posture)
  if adapter.setPostureVariables then pcall(adapter.setPostureVariables,adapter,self.state) end
  return self
end
function Posture:publish()
  if self.adapter.setPostureVariables then self.adapter:setPostureVariables(self.state) end
  if self.onChange then self.onChange(self:status()) end
  return true
end
function Posture:onLine(line)
  line=tostring(line or ""); local changed=false
  if contains(line,standing) then self.state.standing=true; self.state.sitting=false; changed=true
  elseif contains(line,sitting) then self.state.sitting=true; self.state.standing=false; changed=true end
  if contains(line,unconsciousOn) then self.state.unconscious=true; changed=true
  elseif line:find("You regain consciousness%.") then self.state.unconscious=false; changed=true end
  if changed then return self:publish() end
  return false
end
function Posture:status() return {standing=self.state.standing,sitting=self.state.sitting,unconscious=self.state.unconscious} end

return Posture
