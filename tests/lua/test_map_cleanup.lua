local Cleanup=require("map_cleanup")

local function listEq(actual,expected)
  eq(#actual,#expected)
  for index,value in ipairs(expected) do eq(actual[index],value) end
end

local function fakeMap()
  local map={
    owner="DragonsGateHUD",
    rooms={
      [50]={exists=true,owned=false,area=7,partition="personal"},
      [100]={exists=true,owned=true,area=7,partition="legacy"},
      [200]={exists=true,owned=true,area=8,partition="A"},
      [201]={exists=true,owned=true,area=8,partition="A"},
      [900]={exists=true,owned=true,area=42,partition="special:900"},
      [901]={exists=true,owned=true,area=42,partition="special:900"},
    },
    areas={
      [7]={id=7,exists=true,owned=false},
      [8]={id=8,exists=true,owned=true},
      [42]={id=42,exists=true,owned=true},
    },
    areaRoomsByID={[7]={50,100},[8]={201,200},[42]={901,900}},
    areaNames={Personal=7,Alpha=8,["Dragons Gate - Submap 900"]=42},
    inbound={}, deleteOrder={}, deleteCalls=0, areaDeleteCalls=0,
  }
  map.api={getAreaTable=function() return map.areaNames end}
  function map:roomRecord(id)
    local room=self.rooms[id]
    if not room then return {exists=false,owned=false,placement_needed=true} end
    local copy={}; for key,value in pairs(room) do copy[key]=value end
    return copy
  end
  function map:areaRecord(id)
    local area=self.areas[id]
    if not area then return nil,"mapper area "..tostring(id).." does not exist" end
    local copy={}; for key,value in pairs(area) do copy[key]=value end
    return copy
  end
  function map:roomsInArea(id)
    local source=self.areaRoomsByID[id] or {}
    local result={}; for _,roomID in ipairs(source) do result[#result+1]=roomID end
    table.sort(result); return result
  end
  function map:inboundSources(ids)
    local selected={}; for _,id in ipairs(ids) do selected[id]=true end
    local result={}
    for source,destinations in pairs(self.inbound) do
      if not selected[source] then
        for _,destination in ipairs(destinations) do
          if selected[destination] then result[#result+1]=source; break end
        end
      end
    end
    table.sort(result); return result
  end
  function map:deleteOwnedRoom(id)
    self.deleteCalls=self.deleteCalls+1
    if self.failRoom==id then return nil,"delete failed" end
    if not self.rooms[id] or not self.rooms[id].owned then return nil,"not owned" end
    self.rooms[id]=nil; self.deleteOrder[#self.deleteOrder+1]=id
    for _,ids in pairs(self.areaRoomsByID) do
      for index=#ids,1,-1 do if ids[index]==id then table.remove(ids,index) end end
    end
    return true
  end
  function map:deleteEmptyOwnedArea(id)
    self.areaDeleteCalls=self.areaDeleteCalls+1
    if not self.areas[id] or not self.areas[id].owned or #(self.areaRoomsByID[id] or {})>0 then return nil,"area not empty and owned" end
    self.areas[id]=nil; return true
  end
  function map:invalidateDeleted(ids,areaID)
    self.invalidated={room_ids=ids,area_id=areaID}; return true
  end
  return map
end

local function fakeRuntime()
  local runtime={snapshot={current_room=1,walking=false,route_rooms={},pending_automap=false,pending_special=false},beforeCalls=0,afterCalls=0}
  function runtime:safetySnapshot()
    local copy={}
    for key,value in pairs(self.snapshot) do
      if type(value)=="table" then copy[key]={}; for index,item in ipairs(value) do copy[key][index]=item end else copy[key]=value end
    end
    return copy
  end
  function runtime:beforeDelete(plan) self.beforeCalls=self.beforeCalls+1; self.beforePlan=plan; return true end
  function runtime:afterDelete(result) self.afterCalls=self.afterCalls+1; self.afterResult=result; return true end
  return runtime
end

local function fixture()
  local now=1000; local serial=0; local map=fakeMap(); local runtime=fakeRuntime()
  local cleanup=Cleanup.new(map,runtime,function() return now end,function() serial=serial+1; return "token"..serial end,30)
  return cleanup,map,runtime,function(value) now=value end
end

test("room preview resolves one owned room into an immutable sorted plan",function()
  local cleanup=fixture(); local preview=assert(cleanup:previewRoom(100))
  eq(preview.operation,"delete_room"); eq(preview.target,"100"); eq(preview.area_id,7); listEq(preview.room_ids,{100}); eq(preview.token,"token1")
  preview.room_ids[1]=999; preview.blockers[1]="changed"
  local pending=assert(cleanup:pending()); listEq(pending.room_ids,{100}); eq(#pending.blockers,0)
end)

test("area preview resolves only exact names and numeric IDs",function()
  local cleanup=fixture(); local byName=assert(cleanup:previewArea("Alpha")); listEq(byName.room_ids,{200,201}); eq(byName.area_id,8)
  local byID=assert(cleanup:previewArea("8")); eq(byID.area_id,8)
  local result,err=cleanup:previewArea("Al"); eq(result,nil); eq(err,"mapper area Al does not exist")
end)

test("ambiguous exact area names are rejected",function()
  local cleanup,map=fixture(); map.areaNames={[1]="Alpha",Alpha=8,["Alpha duplicate"]=8}
  local result,err=cleanup:previewArea("Alpha"); eq(result,nil); eq(err,"mapper area Alpha is ambiguous")
end)

test("submap preview requires exact persisted partition on every room",function()
  local cleanup,map=fixture(); local preview=assert(cleanup:previewSubmap(900))
  eq(preview.operation,"clear_submap"); eq(preview.target,"900"); eq(preview.partition,"special:900"); listEq(preview.room_ids,{900,901})
  map.rooms[901].partition="special:other"
  local result,err=cleanup:previewSubmap(900); eq(result,nil); eq(err,"room 901 is outside partition special:900")
end)

test("preview rejects unowned rooms and areas",function()
  local cleanup=fixture(); local result,err=cleanup:previewRoom(50); eq(result,nil); eq(err,"room 50 is not owned by DragonsGateHUD")
  result,err=cleanup:previewArea("Personal"); eq(result,nil); eq(err,"mapper area 7 is not owned by DragonsGateHUD")
end)

test("current route walking and pending movement block previews",function()
  local cases={
    {field="current_room",value=100,error="cleanup includes the current room"},
    {field="route_rooms",value={100},error="cleanup intersects the active route"},
    {field="walking",value=true,error="map walking is active"},
    {field="pending_automap",value=true,error="automapper movement is pending"},
    {field="pending_special",value=true,error="special transition is pending"},
  }
  for _,case in ipairs(cases) do
    local cleanup,_,runtime=fixture(); runtime.snapshot[case.field]=case.value
    local result,err=cleanup:previewRoom(100); eq(result,nil); eq(err,case.error); eq(cleanup:pending(),nil)
  end
end)

test("personal inbound sources block preview but owned sources do not",function()
  local cleanup,map=fixture(); map.inbound[50]={100}
  local result,err=cleanup:previewRoom(100); eq(result,nil); eq(err,"unowned room 50 has an inbound exit")
  map.inbound={[200]={100}}; local preview=assert(cleanup:previewRoom(100)); listEq(preview.inbound_sources,{200})
end)

test("new previews replace old tokens and cancellation clears pending",function()
  local cleanup=fixture(); local first=assert(cleanup:previewRoom(100)); local second=assert(cleanup:previewArea(8))
  local result,err=cleanup:confirm(first.token); eq(result,nil); eq(err,"cleanup confirmation token is invalid")
  eq(cleanup:cancel(),true); eq(cleanup:pending(),nil)
  result,err=cleanup:confirm(second.token); eq(result,nil); eq(err,"cleanup confirmation token is invalid")
end)

test("confirmation tokens expire after thirty seconds and are consumed",function()
  local cleanup,map,_,setNow=fixture(); local preview=assert(cleanup:previewRoom(100)); setNow(1031)
  local result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup confirmation token has expired"); eq(map.deleteCalls,0)
  result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup confirmation token is invalid")
end)

test("confirmation rebuilds the plan and rejects changed membership",function()
  local cleanup,map=fixture(); local preview=assert(cleanup:previewSubmap(900)); map.areaRoomsByID[42]={900,901,902}
  local result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup preview is stale"); eq(map.deleteCalls,0)
end)

test("confirmation rejects stale ownership inbound and safety snapshots",function()
  local mutations={
    function(map) map.rooms[100].owned=false end,
    function(map) map.inbound[200]={100} end,
    function(_,runtime) runtime.snapshot.current_room=2 end,
  }
  for _,mutate in ipairs(mutations) do
    local cleanup,map,runtime=fixture(); local preview=assert(cleanup:previewRoom(100)); mutate(map,runtime)
    local result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup preview is stale"); eq(map.deleteCalls,0)
  end
end)

test("confirmation token is one use and successful room deletion runs lifecycle",function()
  local cleanup,map,runtime=fixture(); local preview=assert(cleanup:previewRoom(100)); local result=assert(cleanup:confirm(preview.token))
  listEq(result.deleted,{100}); eq(result.failed,nil); eq(result.area_deleted,false); eq(runtime.beforeCalls,1); eq(runtime.afterCalls,1); eq(map.invalidated.area_id,nil)
  local repeated,err=cleanup:confirm(preview.token); eq(repeated,nil); eq(err,"cleanup confirmation token is invalid")
end)

test("area cleanup deletes rooms ascending then deletes and invalidates the empty owned area",function()
  local cleanup,map,runtime=fixture(); local preview=assert(cleanup:previewArea("Alpha")); local result=assert(cleanup:confirm(preview.token))
  listEq(map.deleteOrder,{200,201}); listEq(result.deleted,{200,201}); eq(result.area_deleted,true); eq(map.areaDeleteCalls,1)
  eq(map.invalidated.area_id,8); listEq(map.invalidated.room_ids,{200,201}); eq(runtime.afterResult.area_deleted,true)
end)

test("partial failure stops deletion and reports exact untouched rooms",function()
  local cleanup,map,runtime=fixture(); map.failRoom=201; local preview=assert(cleanup:previewArea(8)); local result=assert(cleanup:confirm(preview.token))
  listEq(result.deleted,{200}); eq(result.failed,201); eq(result.error,"delete failed"); listEq(result.untouched,{201}); eq(result.area_deleted,false)
  eq(map.areaDeleteCalls,0); eq(runtime.afterCalls,1); listEq(map.invalidated.room_ids,{200})
end)

test("area deletion failure is reported after all rooms are deleted",function()
  local cleanup,map,runtime=fixture(); function map:deleteEmptyOwnedArea() self.areaDeleteCalls=self.areaDeleteCalls+1; return nil,"area delete failed" end
  local result=assert(cleanup:confirm(assert(cleanup:previewArea(8)).token)); listEq(result.deleted,{200,201}); eq(result.failed,nil); eq(result.area_deleted,false); eq(result.area_error,"area delete failed"); eq(runtime.afterCalls,1)
end)
