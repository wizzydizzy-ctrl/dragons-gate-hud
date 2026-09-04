local Roller={}; Roller.__index=Roller
local order={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local ranks={awful=1,poor=2,low=3,aver=4,average=4,fair=5,good=6,great=7}

local function copy(value)
  if type(value)~="table" then return value end; local out={}; for k,v in pairs(value) do out[k]=copy(v) end; return out
end
local function trim(value) return tostring(value or ""):match("^%s*(.-)%s*$") end
local function limit(value) value=tonumber(value); return value and value>=1 and math.floor(value) or nil end
local function statText(stats)
  local out={}; for _,name in ipairs(order) do out[#out+1]=name.." "..tostring(stats[name] or 0) end; return table.concat(out,"  ")
end
function Roller.new(adapter,settings,onConfig)
  local self=setmetatable({adapter=adapter,cfg=copy(settings or {}),onConfig=onConfig},Roller); self:reset(); return self
end
function Roller:echo(message) if self.adapter.reportRoller then self.adapter:reportRoller(message) end end
function Roller:reset()
  if self.state and self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end
  self.state={active=false,rolls=0,sum=0,last=nil,best=nil,worst=nil,expecting=false,timer=nil,log=nil}; return true
end
function Roller:log(message)
  if not self.state.log or not self.adapter.appendRollerLog then return end
  local called,ok,err=pcall(self.adapter.appendRollerLog,self.adapter,self.state.log,message)
  if not called or not ok then self:echo("Logging stopped: "..tostring((not called and ok) or err or "write failed")); if self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log) end; self.state.log=nil end
end
function Roller:minimumFailures(stats)
  local out={}; if self.cfg.use_min_stats~=true then return out end
  for _,name in ipairs(order) do local needed=tonumber((self.cfg.min_stats or {})[name]); if needed and (stats[name] or 0)<needed then out[#out+1]=name.." "..stats[name].."<"..needed end end
  return out
end
function Roller:qualified(roll)
  local hard=limit(self.cfg.hard_stop); if hard and roll.total>=hard then return true,"hard stop "..hard end
  local target=limit(self.cfg.target_total); if not target or roll.total<target then return false,"below target "..tostring(target or "disabled") end
  local failures=self:minimumFailures(roll.stats); if self.cfg.require_min_stats_to_stop~=false and #failures>0 then return false,table.concat(failures,", ") end
  return true,"target "..target
end
function Roller:start()
  if self.state.active then self:echo("Already running."); return true end
  if self.adapter.standaloneRollerPresent and self.adapter:standaloneRollerPresent() then if not self.state.conflict_warned then self:echo("Built-in roller paused: the standalone og-dg-roller package is active. Disable or uninstall that package before using DGHUD's roller."); self.state.conflict_warned=true end; return nil,"standalone roller conflict" end
  self:reset(); self.state.active=true
  if self.cfg.logging_enabled~=false and self.adapter.startRollerLog then local ok,log,err=pcall(self.adapter.startRollerLog,self.adapter,self.cfg); if ok then self.state.log=log; if not log then self:echo("Logging unavailable: "..tostring(err or "unknown error")) end else self:echo("Logging unavailable: "..tostring(log)) end end
  self:log("Started")
  self:echo("Started — target "..tostring(limit(self.cfg.target_total) or "disabled").." / 77."); return true
end
function Roller:stop(reason)
  self.state.active=false; if self.state.timer then pcall(self.adapter.cancelTimer,self.adapter,self.state.timer); self.state.timer=nil end
  self:report(reason or "Stopped"); self:log(reason or "Stopped")
  if self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end
  return true
end
function Roller:rollText(roll) return "Roll #"..roll.roll.."  Total="..roll.total.."  "..statText(roll.stats) end
function Roller:report(reason)
  local s=self.state; local lines={reason or "Roller statistics","Rolls: "..s.rolls.."  Average: "..string.format("%.2f",s.rolls>0 and s.sum/s.rolls or 0)}
  if s.best then lines[#lines+1]="Best: "..self:rollText(s.best) end; if s.worst then lines[#lines+1]="Worst: "..self:rollText(s.worst) end; self:echo(table.concat(lines,"\n")); return true
end
function Roller:capture(line)
  local words={}; for word in tostring(line):gmatch("%a+") do local value=ranks[word:lower()]; if value then words[#words+1]=value end end
  if #words~=11 then return false end
  local stats,total={},0; for i,name in ipairs(order) do stats[name]=words[i]; total=total+words[i] end
  local s=self.state; s.rolls=s.rolls+1; s.sum=s.sum+total; local roll={roll=s.rolls,total=total,stats=stats}; s.last=roll
  if not s.best or total>s.best.total then s.best=roll end; if not s.worst or total<s.worst.total then s.worst=roll end
  s.fresh_roll=true; local text=self:rollText(roll); self:echo(text); self:log(text); return true
end
function Roller:reroll()
  if self.state.timer then return true end
  local delay=math.max(0,tonumber(self.cfg.reroll_delay) or 0); local called,id,err=pcall(self.adapter.schedule,self.adapter,delay,function()
    self.state.timer=nil
    if self.state.active then local called,sent,sendErr=pcall(self.adapter.sendCommand,self.adapter,tostring(self.cfg.reroll_command or "n")); if not called or sent==false or (sent==nil and sendErr~=nil) then self:stop("Could not send reroll: "..tostring((not called and sent) or sendErr or "send failed")) end end
  end)
  if not called then err=id or "timer unavailable"; id=nil end
  if not id then self:stop("Could not schedule reroll: "..tostring(err)); return nil,err end; self.state.timer=id; return true
end
function Roller:onLine(line)
  line=tostring(line or "")
  if line:match("Name%s*:%s*.-%s+Race%s*:%s*%S+") then if self.cfg.auto_start_on_name~=false and not self.state.active then return self:start() end; return self.state.active end
  if not self.state.active then return false end
  if line:lower():match("^%s*str%s+int%s+wis%s+dex%s+agi%s+con%s+cha%s+wil%s+voi%s+per%s+app%s*$") then self.state.expecting=true; self.state.fresh_roll=false; return true end
  if self.state.expecting then self.state.expecting=false; if self:capture(line) then return true end; self.state.fresh_roll=false end
  if line:lower():match("use%s+this%s+body%s*%?%s*y%s*,%s*n") then
    local roll=self.state.last; if not roll or not self.state.fresh_roll then return false end; self.state.fresh_roll=false; local cap=limit(self.cfg.max_rolls); if cap and self.state.rolls>=cap then return self:stop("Reached max rolls "..cap) end
    local ok,reason=self:qualified(roll); if ok then self:echo("TARGET HIT — prompt left waiting for manual y.\n"..self:rollText(roll)); return self:stop(reason) end
    return self:reroll()
  end
  return false
end
function Roller:set(key,value)
  key=trim(key):upper(); value=trim(value)
  local off=value:lower()=="off"
  if key=="TOTAL" then local number=limit(value); if not number and not off then return nil,"total must be 1-77 or off" end; if number and number>77 then return nil,"total must be 1-77 or off" end; self.cfg.target_total=number
  elseif key=="HARD" then local number=limit(value); if not number and not off then return nil,"hard stop must be 1-77 or off" end; if number and number>77 then return nil,"hard stop must be 1-77 or off" end; self.cfg.hard_stop=number
  elseif key=="MAX" then local number=limit(value); if not number and not off then return nil,"max must be a positive number or off" end; self.cfg.max_rolls=number
  elseif key=="DELAY" then local number=tonumber(value); if not number or number<0 then return nil,"delay must be zero or greater" end; self.cfg.reroll_delay=number
  elseif ranks[key:lower()] then return nil,"use a stat name, not a rank"
  else local valid=false; for _,name in ipairs(order) do if key==name then valid=true end end; if not valid then return nil,"unknown roller setting" end; local number=limit(value); if not number and not off then return nil,"stat minimum must be 1-7 or off" end; if number and number>7 then return nil,"stat minimum must be 1-7 or off" end; self.cfg.min_stats=self.cfg.min_stats or {}; self.cfg.min_stats[key]=number; self.cfg.use_min_stats=true end
  if self.onConfig then self.onConfig(copy(self.cfg)) end
  local shown=key=="TOTAL" and self.cfg.target_total or key=="HARD" and self.cfg.hard_stop or key=="MAX" and self.cfg.max_rolls or key=="DELAY" and self.cfg.reroll_delay or (self.cfg.min_stats or {})[key]
  self:echo("Set "..key.." to "..tostring(shown or "off")); return true
end
function Roller:command(action)
  action=trim(action); local lower=action:lower()
  if lower=="start" then return self:start() elseif lower=="stop" then return self:stop("Manual stop") elseif lower=="stats" then return self:report("Roller statistics") elseif lower=="last" then if self.state.last then self:echo(self:rollText(self.state.last)) else self:echo("No roll captured yet.") end; return true elseif lower=="reset" then self:reset(); self:echo("Reset complete."); return true end
  local key,value=action:match("^[Ss][Ee][Tt]%s+(%S+)%s+(%S+)%s*$"); if key then local ok,err=self:set(key,value); if not ok then self:echo(err) end; return ok,err end
  self:echo("Commands: rr start|stop|stats|last|reset|help; rr set total|hard|max|delay|STAT <value>"); return true
end
function Roller:shutdown() if self.state.timer then pcall(self.adapter.cancelTimer,self.adapter,self.state.timer) end; self.state.timer=nil; self.state.active=false; if self.state.log and self.adapter.closeRollerLog then pcall(self.adapter.closeRollerLog,self.adapter,self.state.log); self.state.log=nil end; return true end
Roller.order=order; Roller.ranks=ranks
return Roller
