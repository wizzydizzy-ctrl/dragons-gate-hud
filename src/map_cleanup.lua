local Cleanup={}
Cleanup.__index=Cleanup

local function positiveInteger(value)
  local number=tonumber(value)
  if not number or number~=number or number==math.huge or number==-math.huge or number<=0 or number%1~=0 then return nil end
  return number
end

local function copy(value,seen)
  if type(value)~="table" then return value end
  seen=seen or {}
  if seen[value] then error("cleanup plans must not contain cycles") end
  seen[value]=true
  local result={}
  for key,item in pairs(value) do result[copy(key,seen)]=copy(item,seen) end
  seen[value]=nil
  return result
end

local function equal(left,right,seen)
  if type(left)~=type(right) then return false end
  if type(left)~="table" then return left==right end
  seen=seen or {}
  if seen[left]==right then return true end
  seen[left]=right
  for key,value in pairs(left) do if not equal(value,right[key],seen) then return false end end
  for key in pairs(right) do if left[key]==nil then return false end end
  return true
end

local function contains(ids,target)
  for _,id in ipairs(ids or {}) do if id==target then return true end end
  return false
end

local function guardedAreaTable(map)
  local api=type(map)=="table" and map.api or nil
  local fn=type(api)=="table" and api.getAreaTable or nil
  if type(fn)~="function" then return nil,"Mudlet mapper API getAreaTable is unavailable" end
  local ok,areas,err=pcall(fn)
  if not ok then return nil,"Mudlet mapper API getAreaTable failed: "..tostring(areas) end
  if areas==nil then return nil,err or "Mudlet mapper API getAreaTable failed" end
  if type(areas)~="table" then return nil,"Mudlet mapper API getAreaTable returned invalid data" end
  return areas
end

local function resolveArea(map,target)
  local numeric=positiveInteger(target)
  if numeric then return numeric end
  local name=tostring(target or "")
  if name=="" then return nil,"mapper area target is required" end
  local areas,areasErr=guardedAreaTable(map)
  if not areas then return nil,areasErr end
  local matches={}
  local function add(value)
    local id=positiveInteger(value)
    if id then matches[id]=true end
  end
  for key,value in pairs(areas) do
    if type(key)=="string" and key==name then add(value) end
    if type(value)=="string" and value==name then add(key) end
  end
  local found
  for id in pairs(matches) do
    if found and found~=id then return nil,"mapper area "..name.." is ambiguous" end
    found=id
  end
  if not found then return nil,"mapper area "..name.." does not exist" end
  return found
end

local function roomEvidence(map,ids,areaID,partition)
  local evidence={}
  for _,roomID in ipairs(ids) do
    local record,recordErr=map:roomRecord(roomID)
    if record==nil then return nil,recordErr end
    if not record.exists then return nil,"room "..tostring(roomID).." does not exist" end
    if not record.owned then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
    if areaID and record.area~=areaID then return nil,"room "..tostring(roomID).." is outside mapper area "..tostring(areaID) end
    if partition and record.partition~=partition then return nil,"room "..tostring(roomID).." is outside partition "..partition end
    evidence[#evidence+1]={id=roomID,area=record.area,owned=true,partition=record.partition}
  end
  return evidence
end

local function safetyError(snapshot,roomIDs,allowCurrent)
  if type(snapshot)~="table" then return "cleanup safety state is unavailable" end
  if not allowCurrent and contains(roomIDs,snapshot.current_room) then return "cleanup includes the current room" end
  if snapshot.walking then return "map walking is active" end
  if type(snapshot.route_rooms)~="table" then return "cleanup safety state is unavailable" end
  for _,roomID in ipairs(snapshot.route_rooms) do if contains(roomIDs,roomID) then return "cleanup intersects the active route" end end
  if snapshot.pending_automap then return "automapper movement is pending" end
  if snapshot.pending_special then return "special transition is pending" end
  return nil
end

function Cleanup.new(map,runtime,clock,tokenFactory,ttlSeconds)
  assert(type(map)=="table","cleanup map adapter is required")
  assert(type(runtime)=="table","cleanup runtime is required")
  assert(type(clock)=="function","cleanup clock is required")
  assert(type(tokenFactory)=="function","cleanup token factory is required")
  local ttl=tonumber(ttlSeconds or 30)
  assert(ttl and ttl>0,"cleanup token lifetime must be positive")
  return setmetatable({map=map,runtime=runtime,clock=clock,tokenFactory=tokenFactory,ttl=ttl},Cleanup)
end

function Cleanup:_finishPlan(plan,issueToken)
  local evidence,evidenceErr=roomEvidence(self.map,plan.room_ids,plan.area_id,plan.partition)
  if not evidence then return nil,evidenceErr end
  plan.ownership=evidence
  local inbound,inboundErr=self.map:inboundSources(plan.room_ids)
  if inbound==nil then return nil,inboundErr end
  plan.inbound_sources=copy(inbound)
  for _,source in ipairs(inbound) do
    local record,recordErr=self.map:roomRecord(source)
    if record==nil then return nil,recordErr end
    if not record.exists or not record.owned then return nil,"unowned room "..tostring(source).." has an inbound exit" end
  end
  local snapshot,snapshotErr=self.runtime:safetySnapshot(copy(plan.room_ids))
  if snapshot==nil then return nil,snapshotErr or "cleanup safety state is unavailable" end
  local blocker=safetyError(snapshot,plan.room_ids,plan.allow_current)
  if blocker then return nil,blocker end
  plan.safety=copy(snapshot)
  plan.blockers={}
  if issueToken then
    plan.created_at=self.clock()
    plan.token=tostring(self.tokenFactory())
    if plan.token=="" then return nil,"cleanup token factory returned an empty token" end
  end
  return plan
end

function Cleanup:_roomPlan(roomID,issueToken)
  local room=positiveInteger(roomID)
  if not room then return nil,"room ID must be a positive integer" end
  local record,recordErr=self.map:roomRecord(room)
  if record==nil then return nil,recordErr end
  return self:_finishPlan({operation="delete_room",target=tostring(room),area_id=record.area,partition=nil,room_ids={room}},issueToken)
end

function Cleanup:_areaPlan(target,issueToken)
  local area,resolveErr=resolveArea(self.map,target)
  if not area then return nil,resolveErr end
  local record,recordErr=self.map:areaRecord(area)
  if record==nil then return nil,recordErr end
  if not record.owned then return nil,"mapper area "..tostring(area).." is not owned by DragonsGateHUD" end
  local rooms,roomsErr=self.map:roomsInArea(area)
  if rooms==nil then return nil,roomsErr end
  return self:_finishPlan({operation="clear_area",target=tostring(target),area_id=area,partition=nil,room_ids=copy(rooms)},issueToken)
end

function Cleanup:_submapPlan(rootRoomID,issueToken)
  local root=positiveInteger(rootRoomID)
  if not root then return nil,"submap root room ID must be a positive integer" end
  local partition="special:"..tostring(root)
  local area,resolveErr=resolveArea(self.map,"Dragons Gate - Submap "..tostring(root))
  if not area then return nil,resolveErr end
  local record,recordErr=self.map:areaRecord(area)
  if record==nil then return nil,recordErr end
  if not record.owned then return nil,"mapper area "..tostring(area).." is not owned by DragonsGateHUD" end
  local rooms,roomsErr=self.map:roomsInArea(area)
  if rooms==nil then return nil,roomsErr end
  return self:_finishPlan({operation="clear_submap",target=tostring(root),area_id=area,partition=partition,room_ids=copy(rooms)},issueToken)
end

function Cleanup:_allPlan(issueToken)
  local areas,areasErr=guardedAreaTable(self.map)
  if not areas then return nil,areasErr end
  local candidates={}
  for key,value in pairs(areas) do
    local keyID=positiveInteger(key); local valueID=positiveInteger(value)
    if keyID then candidates[keyID]=true end
    if valueID then candidates[valueID]=true end
  end
  local areaIDs={}
  for areaID in pairs(candidates) do
    local record,recordErr=self.map:areaRecord(areaID)
    if record==nil then return nil,recordErr end
    if record.exists and record.owned then areaIDs[#areaIDs+1]=areaID end
  end
  table.sort(areaIDs)
  if #areaIDs==0 then return nil,"no DragonsGateHUD map areas exist" end
  local roomSet={}
  for _,areaID in ipairs(areaIDs) do
    local rooms,roomsErr=self.map:roomsInArea(areaID)
    if rooms==nil then return nil,roomsErr end
    for _,roomID in ipairs(rooms) do roomSet[roomID]=true end
  end
  local roomIDs={}; for roomID in pairs(roomSet) do roomIDs[#roomIDs+1]=roomID end; table.sort(roomIDs)
  return self:_finishPlan({operation="clear_all",target="all",area_id=nil,area_ids=areaIDs,partition=nil,room_ids=roomIDs,allow_current=true},issueToken)
end

function Cleanup:_preview(builder,...)
  if self.busy then return nil,"cleanup is already running" end
  self.plan=nil
  local plan,err=builder(self,...,true)
  if not plan then return nil,err end
  self.plan=copy(plan)
  return copy(plan)
end

function Cleanup:previewRoom(roomID) return self:_preview(self._roomPlan,roomID) end
function Cleanup:previewArea(target) return self:_preview(self._areaPlan,target) end
function Cleanup:previewSubmap(rootRoomID) return self:_preview(self._submapPlan,rootRoomID) end
function Cleanup:previewAll()
  if self.busy then return nil,"cleanup is already running" end
  self.plan=nil
  local plan,err=self:_allPlan(true)
  if not plan then return nil,err end
  self.plan=copy(plan)
  return copy(plan)
end

function Cleanup:pending()
  return self.plan and copy(self.plan) or nil
end

function Cleanup:cancel()
  if self.busy then return nil,"cleanup is already running" end
  self.plan=nil
  return true
end

function Cleanup:_rebuild(plan)
  if plan.operation=="delete_room" then return self:_roomPlan(plan.target,false) end
  if plan.operation=="clear_area" then return self:_areaPlan(plan.target,false) end
  if plan.operation=="clear_submap" then return self:_submapPlan(plan.target,false) end
  if plan.operation=="clear_all" then return self:_allPlan(false) end
  return nil,"unknown cleanup operation"
end

local function comparable(plan)
  return {
    operation=plan.operation,target=plan.target,area_id=plan.area_id,area_ids=plan.area_ids,partition=plan.partition,allow_current=plan.allow_current,
    room_ids=plan.room_ids,ownership=plan.ownership,inbound_sources=plan.inbound_sources,safety=plan.safety,blockers=plan.blockers,
  }
end

local function exceptionMessage(value)
  local message=tostring(value)
  return message:match(":%d+: (.*)$") or message
end

local function protectedCall(fn)
  local first,second
  local ok,err=xpcall(function() first,second=fn() end,exceptionMessage)
  if not ok then return false,nil,err end
  return true,first,second
end

local function appendUntouched(result,roomIDs,index)
  for untouched=index,#roomIDs do result.untouched[#result.untouched+1]=roomIDs[untouched] end
end

function Cleanup:confirm(token)
  if self.busy then return nil,"cleanup is already running" end
  local plan=self.plan
  if not plan or tostring(token)~=plan.token then return nil,"cleanup confirmation token is invalid" end
  self.plan=nil
  self.busy=true
  local result={deleted={},deleted_areas={},failed=nil,untouched={},area_deleted=false}
  local executionStarted=false
  local failureError
  local activeRoomIndex
  local bodyOK,bodyError=xpcall(function()
    local clockOK,now,clockError=protectedCall(self.clock)
    if not clockOK then failureError="cleanup confirmation failed: "..clockError; return end
    if now-plan.created_at>self.ttl then failureError="cleanup confirmation token has expired"; return end

    local rebuildOK,rebuilt,rebuildError=protectedCall(function() return self:_rebuild(plan) end)
    if not rebuildOK then
      failureError="cleanup confirmation failed: "..tostring(rebuildError)
      return
    end
    if not rebuilt or not equal(comparable(plan),comparable(rebuilt)) then failureError="cleanup preview is stale"; return end

    local beforeOK,before,beforeError=protectedCall(function() return self.runtime:beforeDelete(copy(plan)) end)
    if not beforeOK then failureError="cleanup confirmation failed: "..beforeError; return end
    if before==nil or before==false then failureError=beforeError or "cleanup preparation failed"; return end
    executionStarted=true

    for index,roomID in ipairs(plan.room_ids) do
      activeRoomIndex=index
      local callOK,deleted,deleteError=protectedCall(function() return self.map:deleteOwnedRoom(roomID) end)
      if not callOK then deleted=nil end
      if not deleted then
        result.failed=roomID; result.error=deleteError or "room deletion failed"
        appendUntouched(result,plan.room_ids,index)
        break
      end
      result.deleted[#result.deleted+1]=roomID
      activeRoomIndex=nil
    end
    if not result.failed and plan.operation~="delete_room" then
      local areaIDs=plan.operation=="clear_all" and plan.area_ids or {plan.area_id}
      for _,areaID in ipairs(areaIDs) do
        local callOK,areaDeleted,areaError=protectedCall(function() return self.map:deleteEmptyOwnedArea(areaID) end)
        if not callOK then areaDeleted=nil end
        if areaDeleted then
          result.deleted_areas[#result.deleted_areas+1]=areaID
        else
          result.area_error=areaError or "area deletion failed"
          result.error=result.area_error
          break
        end
      end
      result.area_deleted=#result.deleted_areas==#areaIDs
    end

    local invalidatedArea=result.area_deleted and plan.area_id or nil
    local invalidateOK,invalidated,invalidateError=protectedCall(function()
      local ok,err=self.map:invalidateDeleted(copy(result.deleted),invalidatedArea)
      if not ok then return ok,err end
      if plan.operation=="clear_all" then
        for _,areaID in ipairs(result.deleted_areas) do
          ok,err=self.map:invalidateDeleted({},areaID); if not ok then return ok,err end
        end
      end
      return true
    end)
    if not invalidateOK then invalidated=nil end
    if invalidated==nil or invalidated==false then
      result.invalidation_error=invalidateError or "map cache invalidation failed"
      result.error=result.error or result.invalidation_error
    end
  end,exceptionMessage)

  if not bodyOK then
    if executionStarted then
      result.error=result.error or bodyError
      if activeRoomIndex and not result.failed then
        result.failed=plan.room_ids[activeRoomIndex]
        appendUntouched(result,plan.room_ids,activeRoomIndex)
      end
    else
      failureError="cleanup confirmation failed: "..bodyError
    end
  end

  if executionStarted then
    local afterOK,after,afterError=protectedCall(function() return self.runtime:afterDelete(copy(result)) end)
    if not afterOK then after=nil end
    if after==nil or after==false then
      result.lifecycle_error=afterError or "cleanup reconciliation failed"
      result.error=result.error or result.lifecycle_error
    end
  end
  self.busy=false
  if not executionStarted then return nil,failureError or "cleanup confirmation failed" end
  return result
end

return Cleanup
