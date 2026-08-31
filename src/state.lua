local State = {}
local function tableAt(value) return type(value)=="table" and value or {} end
local function number(value) value=tonumber(value); return value or 0 end
local function percent(current, maximum)
  current,maximum=number(current),number(maximum)
  if maximum<=0 then return 0 end
  local value=current/maximum*100
  if value<0 then value=0 elseif value>100 then value=100 end
  return math.floor(value*10+0.5)/10
end
local function resource(vitals,key)
  local current,maximum=number(vitals[key]),number(vitals[key.."_max"])
  return {current=current,maximum=maximum,percent=percent(current,maximum),visible=maximum>0}
end
function State.normalize(source)
  source=tableAt(source); local char=tableAt(source.Char); local status=tableAt(char.Status); local vitals=tableAt(char.Vitals)
  local roomRoot=tableAt(source.Room); local room=tableAt(roomRoot.Info)
  local name=tostring(status.name or ""); local surname=tostring(status.surname or ""); local full=(name.." "..surname):match("^%s*(.-)%s*$"); if full=="" then full="Unknown" end
  return {character={name=name,surname=surname,full_name=full,race=status.race or "Unknown",class=status.class or "Unknown",alignment=status.alignment or "Unknown"},vitals={hp=resource(vitals,"hp"),fatigue=resource(vitals,"fatigue"),psi=resource(vitals,"psi"),web=resource(vitals,"web"),carry=resource(vitals,"carry"),gold=number(vitals.gold),silver=number(vitals.silver),position=number(vitals.position),roundtime=number(vitals.roundtime),weapon_readied=vitals.weapon_readied==true,shield_readied=vitals.shield_readied==true},room={name=room.name or "Unknown room",num=room.num,area=room.area,environment=room.environment or "Unknown",exits=tableAt(room.exits),flags=tableAt(room.flags),players=tableAt(roomRoot.Players),wrong_direction=roomRoot.WrongDir}}
end
return State
