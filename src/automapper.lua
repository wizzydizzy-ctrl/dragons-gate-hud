local Automapper={}; Automapper.__index=Automapper

local teleportCommands={
  ["go portal"]=true,["go door"]=true,["go gate"]=true,["go arch"]=true,
  portal=true,door=true,gate=true,arch=true,
}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

local function contains(values,wanted)
  for _,value in ipairs(values or {}) do if value==wanted then return true end end
  return false
end

local function positiveInteger(value)
  local number=tonumber(value)
  if not number or number~=number or number==math.huge or number==-math.huge or number<=0 or number%1~=0 then return nil end
  return number
end

function Automapper.new(model,map,onStatus)
  return setmetatable({model=model,map=map,onStatus=onStatus or function() end,current_id=nil,pending=nil},Automapper)
end

function Automapper:status(kind,message)
  pcall(self.onStatus,kind,tostring(message or ""))
end

function Automapper:onOutgoing(command)
  local value=trim(command)
  local classified=value:lower()
  local direction=self.model.direction(classified)
  if direction and self.current_id then
    self.pending={from=self.current_id,direction=direction}
  elseif teleportCommands[classified] or classified:match("^walkto%s+") then
    self.pending=nil
  end
  return direction
end

function Automapper:onSpecialTransition(transition)
  local from=type(transition)=="table" and positiveInteger(transition.from) or nil
  local to=type(transition)=="table" and positiveInteger(transition.to) or nil
  local command=type(transition)=="table" and trim(transition.command) or ""
  if not from or not to or from==to or command=="" or transition.kind~="special" then
    self.pending=nil
    return nil,"invalid special transition"
  end
  self.pending={kind="special",from=from,to=to,command=command}
  return true
end

function Automapper:roomRecord(roomID)
  if type(self.map.roomRecord)=="function" then return self.map:roomRecord(roomID) end
  local coordinates,coordinatesErr=self.map:coordinates(roomID)
  if coordinates then return {exists=true,owned=true,coordinates=coordinates,placement_needed=false,legacy=true} end
  if coordinatesErr then return nil,coordinatesErr end
  return {exists=false,owned=false,placement_needed=true,legacy=true}
end

function Automapper:partitionFor(room,record)
  if record.exists and not record.placement_needed then
    if record.partition then return record.partition end
    if record.legacy then return room.area_key end
    if record.owned then return self.map:effectivePartition(room.id) end
    return room.area_key
  end
  if self.pending and self.pending.kind=="special" and self.pending.from~=room.id then
    return "special:"..tostring(room.id)
  end
  if self.pending and self.pending.direction and self.pending.from~=room.id then
    local origin,originErr=self:roomRecord(self.pending.from)
    if origin==nil then return nil,originErr end
    if origin.exists and origin.owned and origin.game_area==room.area_key then
      local originPartition=origin.partition
      if not originPartition then originPartition,originErr=self.map:effectivePartition(self.pending.from) end
      if originPartition==nil and originErr then return nil,originErr end
      if tostring(originPartition or ""):match("^special:%d+$") then return originPartition end
    end
  end
  return room.area_key
end

function Automapper:coordinatesFor(room,partition,record)
  if not record or not record.placement_needed then
    if record and record.coordinates then return record.coordinates end
    local existing,existingErr=self.map:coordinates(room.id)
    if existing then return existing end
    if existingErr then return nil,existingErr end
  end
  local desired={x=0,y=0,z=0}
  if self.pending then
    local origin=self.map:coordinates(self.pending.from)
    desired=origin and self.model.destination(origin,self.pending.direction) or desired
  end
  local occupancyErr
  local coordinates=self.model.nearestFree(desired,function(x,y,z)
    local occupied,err=self.map:roomsAt(partition,x,y,z)
    if occupied==nil then occupancyErr=err or "room occupancy lookup failed"; return false end
    for _,id in pairs(occupied) do if tonumber(id)~=room.id then return true end end
    return false
  end)
  if occupancyErr then return nil,occupancyErr end
  return coordinates
end

local function hasObservedPlacementIntent(self,room)
  local pending=self.pending
  if not pending or pending.from==room.id or self.current_id~=pending.from then return false end
  local special=pending.kind=="special" and pending.to==room.id
  local directional=pending.kind==nil and pending.direction~=nil
  if not special and not directional then return false end
  local origin,originErr=self:roomRecord(pending.from)
  if origin==nil then return nil,originErr end
  if not origin.exists or not origin.owned then return false end
  if directional then
    local coordinates,coordinatesErr=self.map:coordinates(pending.from)
    if not coordinates then return nil,coordinatesErr end
  end
  return true
end

function Automapper:onRoom(raw)
  local room,normalizeErr=self.model.normalizeRoom(raw)
  if not room then self.pending=nil; self:status("invalid_room",normalizeErr); return nil,normalizeErr end
  local sameOrigin=self.pending and self.pending.from==room.id
  local specialArrival=self.pending and self.pending.kind=="special" and not sameOrigin
  if specialArrival and self.pending.to~=room.id then
    self.pending=nil; self:status("invalid_room","special transition destination did not match GMCP room")
    return nil,"special transition destination did not match GMCP room"
  end
  local record,recordErr=self:roomRecord(room.id)
  if not record then
    if not sameOrigin or specialArrival then self.pending=nil end
    self:status("invalid_room",recordErr); return nil,recordErr
  end
  if record.exists and record.placement_needed then
    local hasIntent,intentErr=hasObservedPlacementIntent(self,room)
    if not hasIntent then
      local err=intentErr or ("room "..tostring(room.id).." placement requires an observed transition")
      if not sameOrigin or specialArrival then self.pending=nil end
      self:status("invalid_room",err); return nil,err
    end
  end
  local partition,partitionErr=self:partitionFor(room,record)
  if not partition then
    if not sameOrigin or specialArrival then self.pending=nil end
    self:status("invalid_room",partitionErr); return nil,partitionErr
  end
  local coordinates,coordinatesErr
  if specialArrival and (not record.exists or record.placement_needed) then coordinates={x=0,y=0,z=0} else coordinates,coordinatesErr=self:coordinatesFor(room,partition,record) end
  if not coordinates then
    if not sameOrigin or specialArrival then self.pending=nil end
    self:status("invalid_room",coordinatesErr); return nil,coordinatesErr
  end
  local ensured,ensureErr=self.map:ensureRoom(room,coordinates,partition)
  if not ensured then
    if not sameOrigin then self.pending=nil end
    local kind=tostring(ensureErr):find("not owned",1,true) and "ownership_conflict" or "invalid_room"
    self:status(kind,ensureErr); return nil,ensureErr
  end
  for _,direction in ipairs(room.exits) do
    local stubbed,stubErr=self.map:ensureStub(room.id,direction)
    if not stubbed then
      if not sameOrigin then self.pending=nil end
      local kind=tostring(stubErr):find("not owned",1,true) and "ownership_conflict" or "invalid_room"
      self:status(kind,stubErr); return nil,stubErr
    end
  end
  local previous=self.current_id
  if self.pending and self.pending.from~=room.id then
    local connected,connectErr
    if self.pending.kind=="special" then
      connected,connectErr=self.map:connectSpecial(self.pending.from,room.id,self.pending.command)
    else
      local reverse=self.model.opposite(self.pending.direction)
      connected,connectErr=self.map:connect(self.pending.from,room.id,self.pending.direction,contains(room.exits,reverse))
    end
    if not connected then self.pending=nil; self:status("invalid_room",connectErr); return nil,connectErr end
  end
  local hadPending=self.pending~=nil
  if not sameOrigin then self.pending=nil end; self.current_id=room.id
  local current,currentErr=self.map:setCurrent(room.id)
  if not current then self:status("invalid_room",currentErr); return nil,currentErr end
  if previous and previous~=room.id and not hadPending then self:status("teleport","room changed without a tracked direction") else self:status("mapped","room "..tostring(room.id)) end
  return true
end

function Automapper:onWrongDirection() self.pending=nil; return true end
function Automapper:onDisconnect() self.pending=nil; return true end
function Automapper:currentRoom() return self.current_id end
function Automapper:shutdown() self.pending=nil; self.current_id=nil; return true end

return Automapper
