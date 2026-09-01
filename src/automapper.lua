local Automapper={}; Automapper.__index=Automapper

local teleportCommands={
  ["go portal"]=true,["go door"]=true,["go gate"]=true,["go arch"]=true,
  portal=true,door=true,gate=true,arch=true,
}

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$"):lower()
end

local function contains(values,wanted)
  for _,value in ipairs(values or {}) do if value==wanted then return true end end
  return false
end

function Automapper.new(model,map,onStatus)
  return setmetatable({model=model,map=map,onStatus=onStatus or function() end,current_id=nil,pending=nil},Automapper)
end

function Automapper:status(kind,message)
  pcall(self.onStatus,kind,tostring(message or ""))
end

function Automapper:onOutgoing(command)
  local value=trim(command)
  local direction=self.model.direction(value)
  if direction and self.current_id then
    self.pending={from=self.current_id,direction=direction}
  elseif teleportCommands[value] or value:match("^walkto%s+") then
    self.pending=nil
  end
  return direction
end

function Automapper:coordinatesFor(room)
  local existing,existingErr=self.map:coordinates(room.id)
  if existing then return existing end
  if existingErr then return nil,existingErr end
  local desired={x=0,y=0,z=0}
  if self.pending then
    local origin=self.map:coordinates(self.pending.from)
    desired=origin and self.model.destination(origin,self.pending.direction) or desired
  end
  local occupancyErr
  local coordinates=self.model.nearestFree(desired,function(x,y,z)
    local occupied,err=self.map:roomsAt(room.area_key,x,y,z)
    if occupied==nil then occupancyErr=err or "room occupancy lookup failed"; return false end
    for _,id in pairs(occupied) do if tonumber(id)~=room.id then return true end end
    return false
  end)
  if occupancyErr then return nil,occupancyErr end
  return coordinates
end

function Automapper:onRoom(raw)
  local room,normalizeErr=self.model.normalizeRoom(raw)
  if not room then self.pending=nil; self:status("invalid_room",normalizeErr); return nil,normalizeErr end
  local sameOrigin=self.pending and self.pending.from==room.id
  local coordinates,coordinatesErr=self:coordinatesFor(room)
  if not coordinates then self:status("invalid_room",coordinatesErr); return nil,coordinatesErr end
  local ensured,ensureErr=self.map:ensureRoom(room,coordinates)
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
    local reverse=self.model.opposite(self.pending.direction)
    local connected,connectErr=self.map:connect(self.pending.from,room.id,self.pending.direction,contains(room.exits,reverse))
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
