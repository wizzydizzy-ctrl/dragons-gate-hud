local Settings={CURRENT_SCHEMA=1}
local function copy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}; if seen[value] then return seen[value] end
  local result={}; seen[value]=result; for k,v in pairs(value) do result[copy(k,seen)]=copy(v,seen) end; return result
end
local function overlay(target,source)
  for k,v in pairs(source or {}) do if type(v)=="table" and type(target[k])=="table" then overlay(target[k],v) else target[k]=copy(v) end end
end
function Settings.merge(defaults,overrides) local result=copy(defaults or {}); overlay(result,overrides or {}); return result end
function Settings.migrate(input)
  local result=copy(input or {}); local changed=false; local schema=tonumber(result.schema) or 0
  if schema<1 then result.update=result.update or {}; result.update.auto_apply=false; result.auto_update=nil; result.schema=1; changed=true end
  return result,changed
end
return Settings
