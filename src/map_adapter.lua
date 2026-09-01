local MapAdapter={}
MapAdapter.__index=MapAdapter
local unpackValues=table.unpack or unpack

local reverse={n="s",ne="sw",e="w",se="nw",s="n",sw="ne",w="e",nw="se",up="down",down="up",["in"]="out",out="in"}

local function missing(name)
  return nil,"Mudlet mapper API "..name.." is unavailable"
end

local function invoke(api,name,...)
  local fn=api[name]
  if type(fn)~="function" then return missing(name) end
  local ok,a,b,c=pcall(fn,...)
  if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
  if a==nil and b~=nil then return nil,tostring(b) end
  if a==false then return nil,"Mudlet mapper API "..name.." failed" end
  return a,b,c
end

local function read(api,name,...)
  local fn=api[name]
  if type(fn)~="function" then return missing(name) end
  local ok,a,b,c=pcall(fn,...)
  if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
  if a==nil and b~=nil then return nil,tostring(b) end
  return a,b,c
end

local function requireCapabilities(api,names)
  for _,name in ipairs(names) do
    if type(api[name])~="function" then return missing(name) end
  end
  return true
end

function MapAdapter.new(api)
  return setmetatable({api=api or {},owner="DragonsGateHUD",schema="1",areas={},createdAreas={},createdRooms={}},MapAdapter)
end

function MapAdapter:isOwned(id)
  if type(self.api.getRoomUserData)~="function" then return false end
  local owner=read(self.api,"getRoomUserData",id,"dghud.owner")
  return owner==self.owner
end

function MapAdapter:ensureArea(areaKey)
  local key=tostring(areaKey or "unknown")
  if self.areas[key]~=nil then return self.areas[key] end
  local name="Dragons Gate - "..key
  local areas,areasErr=read(self.api,"getAreaTable")
  if areas==nil then return nil,areasErr end
  local area=areas[name]
  if area~=nil then
    local owner,ownerErr=read(self.api,"getAreaUserData",area,"dghud.owner")
    if ownerErr then return nil,ownerErr end
    if owner~=self.owner and self.createdAreas[area]~=true then return nil,"area "..name.." is not owned by DragonsGateHUD" end
  else
    local addErr
    area,addErr=invoke(self.api,"addAreaName",name)
    if area==nil then return nil,addErr end
    self.createdAreas[area]=true
  end
  local areaOperations={{"setAreaUserData",area,"dghud.owner",self.owner},{"setAreaUserData",area,"dghud.state","provisional"},{"setAreaUserData",area,"dghud.mapper_schema",self.schema}}
  for _,operation in ipairs(areaOperations) do local ok,err=invoke(self.api,unpackValues(operation)); if ok==nil then return nil,err end end
  local readyOk,readyErr=invoke(self.api,"setAreaUserData",area,"dghud.state","ready"); if readyOk==nil then return nil,readyErr end
  self.createdAreas[area]=nil
  self.areas[key]=area
  return area
end

function MapAdapter:ensureRoom(room,coordinates)
  if type(room)~="table" or room.id==nil then return nil,"room ID is required" end
  coordinates=coordinates or {}
  local ready,readyErr=requireCapabilities(self.api,{"roomExists","addRoom","getAreaTable","addAreaName","setAreaUserData","getAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","getRoomUserData"})
  if not ready then return nil,readyErr end
  local existsCall,exists,existsErr=pcall(self.api.roomExists,room.id)
  if not existsCall then return nil,"Mudlet mapper API roomExists failed: "..tostring(exists) end
  if exists==nil then return nil,existsErr or "Mudlet mapper API roomExists failed" end
  if exists and not self:isOwned(room.id) and self.createdRooms[room.id]~=true then
    return nil,"room "..tostring(room.id).." is not owned by DragonsGateHUD"
  end
  local area,areaErr=self:ensureArea(room.area_key)
  if area==nil then return nil,areaErr end
  if not exists then
    local added,addErr=invoke(self.api,"addRoom",room.id)
    if added==nil then return nil,addErr end
    self.createdRooms[room.id]=true
  end
  local ownerOk,ownerErr=invoke(self.api,"setRoomUserData",room.id,"dghud.owner",self.owner); if ownerOk==nil then return nil,ownerErr end
  local provisionalOk,provisionalErr=invoke(self.api,"setRoomUserData",room.id,"dghud.state","provisional"); if provisionalOk==nil then return nil,provisionalErr end
  local operations={
    {"setRoomUserData",room.id,"dghud.mapper_schema",self.schema},
    {"setRoomUserData",room.id,"dghud.environment",tostring(room.environment or "")},
    {"setRoomUserData",room.id,"dghud.flags",table.concat(room.flags or {},",")},
    {"setRoomArea",room.id,area},
    {"setRoomName",room.id,tostring(room.name or ("Room "..tostring(room.id)))},
    {"setRoomCoordinates",room.id,tonumber(coordinates.x) or 0,tonumber(coordinates.y) or 0,tonumber(coordinates.z) or 0},
  }
  for _,operation in ipairs(operations) do
    local ok,err=invoke(self.api,unpackValues(operation))
    if ok==nil then return nil,err end
  end
  local readyOk,readyErr=invoke(self.api,"setRoomUserData",room.id,"dghud.state","ready"); if readyOk==nil then return nil,readyErr end
  self.createdRooms[room.id]=nil
  return true
end

function MapAdapter:ensureStub(roomID,direction)
  if not self:isOwned(roomID) then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
  local ok,err=invoke(self.api,"setExitStub",roomID,direction,true)
  if ok==nil then return nil,err end
  return true
end

function MapAdapter:connect(fromID,toID,direction,confirmedReverse)
  if not self:isOwned(fromID) then return nil,"room "..tostring(fromID).." is not owned by DragonsGateHUD" end
  if not self:isOwned(toID) then return nil,"room "..tostring(toID).." is not owned by DragonsGateHUD" end
  if type(self.api.setExit)~="function" then return missing("setExit") end
  local backwards=reverse[direction]
  if confirmedReverse and not backwards then return nil,"unsupported map direction "..tostring(direction) end
  local ok,err=invoke(self.api,"setExit",fromID,toID,direction)
  if ok==nil then return nil,err end
  if confirmedReverse then
    local reverseOk,reverseErr=invoke(self.api,"setExit",toID,fromID,backwards)
    if reverseOk==nil then return nil,reverseErr end
  end
  return true
end

function MapAdapter:setCurrent(roomID)
  if not self:isOwned(roomID) then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
  local ok,err=invoke(self.api,"centerview",roomID)
  if ok==nil then return nil,err end
  return true
end

function MapAdapter:coordinates(roomID)
  local x,y,z=invoke(self.api,"getRoomCoordinates",roomID)
  if x==nil then return nil,y end
  return {x=x,y=y,z=z}
end

function MapAdapter:roomsAt(areaKey,x,y,z)
  local area,areaErr=self:ensureArea(areaKey)
  if area==nil then return nil,areaErr end
  local rooms,err=invoke(self.api,"getRoomsByPosition",area,x,y,z)
  if rooms==nil then return nil,err end
  return rooms
end

function MapAdapter:route(fromID,toID)
  local steps,err=invoke(self.api,"getPath",fromID,toID)
  if steps==nil then return nil,err end
  return steps
end

function MapAdapter:center(roomID)
  local ready,readyErr=requireCapabilities(self.api,{"centerview","updateMap"})
  if not ready then return nil,readyErr end
  local centered,centerErr=invoke(self.api,"centerview",roomID)
  if centered==nil then return nil,centerErr end
  local refreshed,refreshErr=invoke(self.api,"updateMap")
  if refreshed==nil then return nil,refreshErr end
  return true
end

function MapAdapter.mudletApi(globals)
  globals=globals or _G
  local api={}
  local names={"addRoom","addAreaName","getAreaTable","setAreaUserData","getAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","getRoomUserData","setExitStub","setExit","getRoomCoordinates","getRoomsByPosition","setRoomIDbyHash","centerview","updateMap"}
  local function wrapper(name)
    return function(...)
      local fn=globals[name]
      if type(fn)~="function" then return missing(name) end
      local ok,a,b,c=pcall(fn,...)
      if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
      if a==nil and b==nil then return true end
      return a,b,c
    end
  end
  local mutations={addRoom=true,addAreaName=true,setAreaUserData=true,setRoomArea=true,setRoomName=true,setRoomCoordinates=true,setRoomUserData=true,setExitStub=true,setExit=true,setRoomIDbyHash=true,centerview=true,updateMap=true}
  for _,name in ipairs(names) do
    if mutations[name] then
      api[name]=wrapper(name)
    else
      api[name]=function(...)
        local fn=globals[name]
        if type(fn)~="function" then return missing(name) end
        local ok,a,b,c=pcall(fn,...)
        if not ok then return nil,"Mudlet mapper API "..name.." failed: "..tostring(a) end
        return a,b,c
      end
    end
  end
  api.getPath=function(fromID,toID)
    local fn=globals.getPath
    if type(fn)~="function" then return missing("getPath") end
    local ok,found=pcall(fn,fromID,toID)
    if not ok then return nil,"Mudlet mapper API getPath failed: "..tostring(found) end
    if not found then return nil,"no map route from "..tostring(fromID).." to "..tostring(toID) end
    if type(globals.speedWalkDir)~="table" then return nil,"Mudlet mapper API getPath did not provide speedWalkDir" end
    local steps={}
    for index,direction in ipairs(globals.speedWalkDir) do steps[index]=direction end
    return steps
  end
  api.roomExists=function(id)
    if type(globals.roomExists)=="function" then
      local ok,value=pcall(globals.roomExists,id)
      if not ok then return nil,"Mudlet mapper API roomExists failed: "..tostring(value) end
      return not not value
    end
    if type(globals.getRoomName)=="function" then
      local ok,value=pcall(globals.getRoomName,id)
      if not ok then return nil,"Mudlet mapper API getRoomName failed: "..tostring(value) end
      return value~=nil and value~=""
    end
    return missing("roomExists")
  end
  return api
end

return MapAdapter
