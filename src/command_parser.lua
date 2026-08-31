local Parser={}
local ATTRS={"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}
local function clean(value)
  return tostring(value or ""):gsub("\27%[[%d;]*m",""):gsub("\27%[[%d;]*[A-Za-z]",""):gsub("%s+$","")
end
local function hasPrompt(lines) for _,raw in ipairs(lines or {}) do if clean(raw):match("^>%s*$") then return true end end return false end

function Parser.parseInventory(lines)
  local result={items={}}
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw); local name,weight=line:match("^%s+(.+)%s+%[([%d%.]+)%s+lbs?%]%.$")
    if name then result.items[#result.items+1]={name=name,weight=tonumber(weight)} end
    local total=line:match("^Your inventory totals ([%d%.]+) lbs?%.$")
    if total then result.total_weight=tonumber(total); return result end
  end
  return nil,"incomplete inventory response"
end

function Parser.parseStat(lines)
  if not hasPrompt(lines) then return nil,"incomplete stat response" end
  local result={equipment={}}; local reading=false
  for _,raw in ipairs(lines or {}) do
    local line=clean(raw)
    result.body_armor=result.body_armor or tonumber(line:match("^Body Armor:%s*(%d+)%%%."))
    local orv,dr,move,max,damage,stance=line:match("^OR:%s*(%d+)%s+DR:%s*(%d+)%s+Move Rate:%s*(%d+)/(%d+)%s+UDs%s+Dam Bonus:%s*(%S+)%s+Stance:%s*(%S+)")
    if orv then result.or_rating=tonumber(orv); result.dr=tonumber(dr); result.move={current=tonumber(move),maximum=tonumber(max)}; result.damage_bonus=damage; result.stance=stance end
    local position=line:match("^You are in the (.-) of the area!$"); if position then result.area_position=position end
    if line:find("novice protection",1,true) then result.novice_protected=true end
    if line:find("Equipment Readied",1,true) then reading=true
    elseif reading and line:match("^%s+%S") then local item=line:match("^%s+(.+)%.$"); if item then result.equipment[#result.equipment+1]=item end end
  end
  if not result.body_armor and not result.or_rating then return nil,"unrecognized stat response" end
  return result
end

function Parser.parseInfo(lines)
  local result={physical={},attributes={}}
  for i,raw in ipairs(lines or {}) do
    local line=clean(raw)
    local full,description,age,alignment,sex,stage,race,height,weight=line:match("^You are (.-), (.-) (%d+) year old (%S+) (%S+) (%S+) (%S+)%.%s+You are (.-) and weigh (%d+) lbs%.$")
    if full then result.character={full_name=full,alignment=alignment,race=race}; result.physical={description=description,age=tonumber(age),sex=sex,life_stage=stage,height=height,weight=tonumber(weight)} end
    if line:match("^%s*Str%s+Int%s+Wis%s+Dex%s+Agi%s+Con%s+Cha%s+Wil%s+Voi%s+Per%s+App%s*$") then
      local values={}; for value in clean(lines[i+1] or ""):gmatch("%S+") do values[#values+1]=value end
      if #values==11 then for n,key in ipairs(ATTRS) do result.attributes[key]=values[n] end end
    end
  end
  if not result.physical.age or not result.attributes.STR then return nil,"unrecognized info response" end
  return result
end

function Parser.isComplete(command,lines)
  local fn={inventory=Parser.parseInventory,stat=Parser.parseStat,info=Parser.parseInfo}
  return fn[command] and (command=="info" or hasPrompt(lines)) and fn[command](lines)~=nil or false
end
return Parser
