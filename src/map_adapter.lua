local MapAdapter={}
MapAdapter.__index=MapAdapter
local unpackValues=table.unpack or unpack

local reverse={n="s",ne="sw",e="w",se="nw",s="n",sw="ne",w="e",nw="se",up="down",down="up",["in"]="out",out="in"}

local function areaName(key)
  local destination=tostring(key):match("^special:(%d+)$")
  return destination and ("Dragons Gate - Submap "..destination) or ("Dragons Gate - "..tostring(key))
end

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

local function rollbackCreated(api,deleteName,id,originalError)
  local deleted,deleteError=invoke(api,deleteName,id)
  if deleted==nil then
    return nil,tostring(originalError).."; rollback failed: "..tostring(deleteError)
  end
  return nil,originalError
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
  local name=areaName(key)
  local areas,areasErr=read(self.api,"getAreaTable")
  if areas==nil then return nil,areasErr end
  local area=areas[name]
  local createdThisCall=false
  if area~=nil then
    local owner,ownerErr=read(self.api,"getAreaUserData",area,"dghud.owner")
    if ownerErr then return nil,ownerErr end
    if owner~=self.owner and self.createdAreas[area]~=true then return nil,"area "..name.." is not owned by DragonsGateHUD" end
  else
    local addErr
    area,addErr=invoke(self.api,"addAreaName",name)
    if area==nil then return nil,addErr end
    createdThisCall=true
    self.createdAreas[area]=true
  end
  local areaOperations={{"setAreaUserData",area,"dghud.owner",self.owner},{"setAreaUserData",area,"dghud.state","provisional"},{"setAreaUserData",area,"dghud.mapper_schema",self.schema}}
  for index,operation in ipairs(areaOperations) do
    local ok,err=invoke(self.api,unpackValues(operation))
    if ok==nil then
      if createdThisCall and index==1 then
        local _,rollbackError=rollbackCreated(self.api,"deleteArea",area,err)
        self.createdAreas[area]=nil
        return nil,rollbackError
      end
      return nil,err
    end
  end
  local readyOk,readyErr=invoke(self.api,"setAreaUserData",area,"dghud.state","ready"); if readyOk==nil then return nil,readyErr end
  self.createdAreas[area]=nil
  self.areas[key]=area
  return area
end

function MapAdapter:roomRecord(roomID)
  local ready,readyErr=requireCapabilities(self.api,{"roomExists","getRoomUserData","getRoomArea","getRoomCoordinates"})
  if not ready then return nil,readyErr end
  local exists,existsErr=read(self.api,"roomExists",roomID)
  if exists==nil then return nil,existsErr or "Mudlet mapper API roomExists failed" end
  local record={exists=not not exists,owned=false}
  if not exists then return record end
  local owner,ownerErr=read(self.api,"getRoomUserData",roomID,"dghud.owner")
  if owner==nil and ownerErr~=nil then return nil,ownerErr end
  record.owned=owner==self.owner
  local partition,partitionErr=read(self.api,"getRoomUserData",roomID,"dghud.partition")
  if partition==nil and partitionErr~=nil then return nil,partitionErr end
  if partition~=nil and tostring(partition)~="" then record.partition=tostring(partition) end
  local area,areaErr=read(self.api,"getRoomArea",roomID)
  if area==nil and areaErr~=nil then return nil,areaErr end
  record.area=area
  local x,y,z=read(self.api,"getRoomCoordinates",roomID)
  if x==nil and y~=nil then return nil,y end
  if x~=nil then record.coordinates={x=x,y=y,z=z} end
  return record
end

local function partitionForArea(self,area)
  if area==nil then return nil,"map area is unavailable" end
  local areas,areasErr=read(self.api,"getAreaTable")
  if areas==nil then return nil,areasErr end
  local partition
  for name,id in pairs(areas) do
    if id==area then
      local destination=tostring(name):match("^Dragons Gate %- Submap (%d+)$")
      partition=destination and ("special:"..destination) or tostring(name):match("^Dragons Gate %- (.+)$")
      if partition then break end
    end
  end
  partition=partition or ("area:"..tostring(area))
  self.areas[partition]=area
  return partition
end

function MapAdapter:effectivePartition(roomID)
  local record,recordErr=self:roomRecord(roomID)
  if record==nil then return nil,recordErr end
  if not record.exists then return nil,"room "..tostring(roomID).." does not exist" end
  if not record.owned then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
  if record.partition then return record.partition end
  return partitionForArea(self,record.area)
end

function MapAdapter:ensureRoom(room,coordinates,partitionKey)
  if type(room)~="table" or room.id==nil then return nil,"room ID is required" end
  coordinates=coordinates or {}
  local ready,readyErr=requireCapabilities(self.api,{"roomExists","addRoom","deleteRoom","getAreaTable","addAreaName","deleteArea","setAreaUserData","getAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","getRoomUserData","getRoomArea","getRoomCoordinates"})
  if not ready then return nil,readyErr end
  local record,recordErr=self:roomRecord(room.id)
  if record==nil then return nil,recordErr end
  local exists=record.exists
  if exists and not record.owned and self.createdRooms[room.id]~=true then
    return nil,"room "..tostring(room.id).." is not owned by DragonsGateHUD"
  end
  local continuingCreation=exists and self.createdRooms[room.id]==true
  local needsPlacement=not exists or continuingCreation
  local effectiveKey
  if needsPlacement then
    effectiveKey=record.partition or tostring(partitionKey or room.area_key or "unknown")
  else
    effectiveKey=record.partition
    if not effectiveKey then
      effectiveKey,recordErr=partitionForArea(self,record.area)
      if effectiveKey==nil then return nil,recordErr end
    end
  end
  local area=record.area
  if needsPlacement then
    local areaErr
    area,areaErr=self:ensureArea(effectiveKey)
    if area==nil then return nil,areaErr end
  end
  local createdThisCall=false
  if not exists then
    local added,addErr=invoke(self.api,"addRoom",room.id)
    if added==nil then return nil,addErr end
    createdThisCall=true
    self.createdRooms[room.id]=true
  end
  if needsPlacement then
    local ownerOk,ownerErr=invoke(self.api,"setRoomUserData",room.id,"dghud.owner",self.owner)
    if ownerOk==nil then
      if createdThisCall then
        local _,rollbackError=rollbackCreated(self.api,"deleteRoom",room.id,ownerErr)
        self.createdRooms[room.id]=nil
        return nil,rollbackError
      end
      return nil,ownerErr
    end
    local provisionalOk,provisionalErr=invoke(self.api,"setRoomUserData",room.id,"dghud.state","provisional"); if provisionalOk==nil then return nil,provisionalErr end
  end
  local operations={
    {"setRoomUserData",room.id,"dghud.mapper_schema",self.schema},
    {"setRoomUserData",room.id,"dghud.environment",tostring(room.environment or "")},
    {"setRoomUserData",room.id,"dghud.flags",table.concat(room.flags or {},",")},
    {"setRoomName",room.id,tostring(room.name or ("Room "..tostring(room.id)))},
  }
  if not record.partition then operations[#operations+1]={"setRoomUserData",room.id,"dghud.partition",effectiveKey} end
  local gameArea,gameAreaErr=read(self.api,"getRoomUserData",room.id,"dghud.game_area")
  if gameArea==nil and gameAreaErr~=nil then return nil,gameAreaErr end
  if gameArea==nil or tostring(gameArea)=="" then operations[#operations+1]={"setRoomUserData",room.id,"dghud.game_area",tostring(room.area_key)} end
  if needsPlacement then
    operations[#operations+1]={"setRoomArea",room.id,area}
    operations[#operations+1]={"setRoomCoordinates",room.id,tonumber(coordinates.x) or 0,tonumber(coordinates.y) or 0,tonumber(coordinates.z) or 0}
  end
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
  local names={"addRoom","deleteRoom","addAreaName","deleteArea","getAreaTable","setAreaUserData","getAreaUserData","setRoomArea","getRoomArea","setRoomName","setRoomCoordinates","setRoomUserData","getRoomUserData","setExitStub","setExit","getRoomCoordinates","getRoomsByPosition","setRoomIDbyHash","centerview","updateMap"}
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
  local mutations={addRoom=true,deleteRoom=true,addAreaName=true,deleteArea=true,setAreaUserData=true,setRoomArea=true,setRoomName=true,setRoomCoordinates=true,setRoomUserData=true,setExitStub=true,setExit=true,setRoomIDbyHash=true,centerview=true,updateMap=true}
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
