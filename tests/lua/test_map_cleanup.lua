local Cleanup=require("map_cleanup")
local MapAdapter=require("map_adapter")

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
  function map:areaDeletionSafe(id) if self.unsafeArea==id then return nil,"mapper area "..id.." contains labels not demonstrably owned by DragonsGateHUD" end; return true end
  function map:beginAreaRoomScan(areaIDs) self.areaScanStarts=(self.areaScanStarts or 0)+1; return {areas=areaIDs,area=1,index=1} end
  function map:scanAreaRoomBatch(scan,limit)
    self.areaScanCalls=(self.areaScanCalls or 0)+1; local out={}; local processed=0
    while processed<limit do
      local area=scan.areas[scan.area]; if not area then self.maxAreaBatch=math.max(self.maxAreaBatch or 0,processed); return out,true end
      local rooms=self.areaRoomsByID[area] or {}; local room=rooms[scan.index]
      if room then out[#out+1]={id=room,area=area}; scan.index=scan.index+1; processed=processed+1 else scan.area=scan.area+1; scan.index=1 end
    end
    self.maxAreaBatch=math.max(self.maxAreaBatch or 0,processed); return out,false
  end
  function map:beginInboundScan() self.inboundScanStarts=(self.inboundScanStarts or 0)+1; return {key=nil} end
  function map:scanInboundBatch(scan,deleting,limit)
    self.inboundScanCalls=(self.inboundScanCalls or 0)+1; local out={}; local processed=0
    while processed<limit do
      local source=next(self.rooms,scan.key); scan.key=source
      if source==nil then self.maxInboundBatch=math.max(self.maxInboundBatch or 0,processed); return out,true end
      processed=processed+1
      if not deleting[source] then
        for _,destination in ipairs(self.inbound[source] or {}) do
          if deleting[destination] then if not self.rooms[source].owned then return nil,nil,"unowned room "..source.." has an inbound exit" end; out[#out+1]=source; break end
        end
      end
    end
    self.maxInboundBatch=math.max(self.maxInboundBatch or 0,processed); return out,false
  end
  function map:defer(callback) callback(); return true end
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

test("clear-all preview selects every owned area and permits the current owned room",function()
  local cleanup,map,runtime=fixture(); runtime.snapshot.current_room=200
  local preview=assert(cleanup:previewAll())
  eq(preview.operation,"clear_all"); listEq(preview.area_ids,{8,42}); listEq(preview.room_ids,{})
  eq(preview.allow_current,true); eq(map.rooms[50].owned,false)
end)

test("clear-all preview performs no room discovery ownership or inbound iteration",function()
  local cleanup,map,runtime=fixture(); runtime.snapshot.current_room=200
  local roomRecords=0; local original=map.roomRecord; function map:roomRecord(id) roomRecords=roomRecords+1; return original(self,id) end
  local preview=assert(cleanup:previewAll()); listEq(preview.area_ids,{8,42}); listEq(preview.room_ids,{})
  eq(roomRecords,0); eq(map.areaScanStarts,nil); eq(map.inboundScanStarts,nil); eq(map.deleteCalls,0)
end)

test("area and clear-all previews refuse areas containing unowned labels",function()
  local cleanup,map=fixture(); map.unsafeArea=8
  local result,err=cleanup:previewArea(8); eq(result,nil); assert(err:find("contains labels",1,true)); eq(map.deleteCalls,0)
  result,err=cleanup:previewAll(); eq(result,nil); assert(err:find("contains labels",1,true)); eq(map.deleteCalls,0)
end)

test("large clear-all yields in bounded batches",function()
  local cleanup,map,runtime=fixture(); map.rooms={}; map.areaRoomsByID[8]={}; map.areaRoomsByID[42]={}; map.areas[42]=nil; map.areaNames={["Alpha"]=8}
  for id=1,250 do map.rooms[id]={exists=true,owned=true,area=8,partition="A"}; map.areaRoomsByID[8][id]=id end
  function map:roomsInArea() error("eager room discovery must not run") end
  function map:inboundSources() error("eager inbound discovery must not run") end
  local queued={}; function map:defer(callback) queued[#queued+1]=callback; return #queued end
  cleanup.batch_size=50; runtime.snapshot.current_room=1
  local result=assert(cleanup:confirm(assert(cleanup:previewAll()).token)); eq(result.pending,true); eq(result.background,true); eq(map.deleteCalls,0); eq(map.areaScanStarts,1); eq(map.areaScanCalls,nil)
  local maximumDeletes=0; while #queued>0 do local callback=table.remove(queued,1); local before=map.deleteCalls; callback(); maximumDeletes=math.max(maximumDeletes,map.deleteCalls-before) end
  eq(maximumDeletes,50); eq(map.maxAreaBatch,50); eq(map.maxInboundBatch<=50,true); eq(#result.deleted,250); eq(result.pending,false); eq(cleanup.busy,false); eq(runtime.afterCalls,1); eq(runtime.afterResult.pending,false)
end)

test("deferred clear-all revalidates ownership and aborts remaining batches",function()
  local cleanup,map,runtime=fixture(); map.rooms={}; map.areaRoomsByID[8]={}; map.areaRoomsByID[42]={}; map.areas[42]=nil; map.areaNames={["Alpha"]=8}
  for id=1,120 do map.rooms[id]={exists=true,owned=true,area=8,partition="A"}; map.areaRoomsByID[8][id]=id end
  local queued={}; function map:defer(callback) queued[#queued+1]=callback; return #queued end
  cleanup.batch_size=50; runtime.snapshot.current_room=1
  local result=assert(cleanup:confirm(assert(cleanup:previewAll()).token)); while #result.deleted==0 and #queued>0 do table.remove(queued,1)() end; map.rooms[51].owned=false; table.remove(queued,1)()
  eq(#result.deleted,50); eq(result.failed,51); eq(#result.untouched,70); eq(map.deleteCalls,51); eq(result.pending,false); eq(runtime.afterCalls,1); eq(map.areas[8]~=nil,true)
end)

test("clear-all confirmation deletes every owned area but preserves personal map data",function()
  local cleanup,map,runtime=fixture(); runtime.snapshot.current_room=200
  local result=assert(cleanup:confirm(assert(cleanup:previewAll()).token))
  listEq(result.deleted,{200,201,900,901}); listEq(result.deleted_areas,{8,42})
  eq(map.rooms[50]~=nil,true); eq(map.rooms[100]~=nil,true); eq(map.areas[7].owned,false)
  eq(map.areas[8],nil); eq(map.areas[42],nil); eq(runtime.afterCalls,1)
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

test("every new preview attempt invalidates the old token before builder failure",function()
  local cases={
    {attempt=function(cleanup) local result,err=cleanup:previewRoom("bad"); eq(result,nil); eq(err,"room ID must be a positive integer") end},
    {prepare=function(_,runtime) runtime.snapshot.walking=true end,attempt=function(cleanup) local result,err=cleanup:previewRoom(100); eq(result,nil); eq(err,"map walking is active") end},
    {prepare=function(map) function map:roomRecord() error("room record exploded") end end,attempt=function(cleanup) local ok,err=pcall(function() cleanup:previewRoom(100) end); eq(ok,false); eq(tostring(err):match("room record exploded")~=nil,true) end},
  }
  for _,case in ipairs(cases) do
    local cleanup,map,runtime=fixture(); local old=assert(cleanup:previewRoom(100))
    if case.prepare then case.prepare(map,runtime) end
    case.attempt(cleanup)
    local result,err=cleanup:confirm(old.token)
    eq(map.deleteCalls,0); eq(runtime.beforeCalls,0); eq(runtime.afterCalls,0)
    eq(result,nil); eq(err,"cleanup confirmation token is invalid"); eq(cleanup:pending(),nil)
  end
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

local function eqRunningRejections(calls)
  eq(calls.preview.result,nil); eq(calls.preview.error,"cleanup is already running")
  eq(calls.cancel.result,nil); eq(calls.cancel.error,"cleanup is already running")
  eq(calls.confirm.result,nil); eq(calls.confirm.error,"cleanup is already running")
end

local function attemptReentry(cleanup,token)
  local calls={}
  calls.preview={}; calls.preview.result,calls.preview.error=cleanup:previewRoom(100)
  calls.cancel={}; calls.cancel.result,calls.cancel.error=cleanup:cancel()
  calls.confirm={}; calls.confirm.result,calls.confirm.error=cleanup:confirm(token)
  return calls
end

test("valid confirmation consumes its token and locks before final rebuild",function()
  local cleanup,map,runtime=fixture(); local preview=assert(cleanup:previewRoom(100)); local calls
  local original=runtime.safetySnapshot; local count=0
  function runtime:safetySnapshot(ids)
    count=count+1
    if count==1 then calls=attemptReentry(cleanup,preview.token) end
    return original(self,ids)
  end
  assert(cleanup:confirm(preview.token)); eqRunningRejections(calls)
  local repeated,err=cleanup:confirm(preview.token); eq(repeated,nil); eq(err,"cleanup confirmation token is invalid"); eq(map.deleteCalls,1)
end)

test("cleanup remains locked throughout before and after lifecycle callbacks",function()
  local cleanup,_,runtime=fixture(); local preview=assert(cleanup:previewRoom(100)); local beforeCalls,afterCalls
  function runtime:beforeDelete() beforeCalls=attemptReentry(cleanup,preview.token); return true end
  function runtime:afterDelete() afterCalls=attemptReentry(cleanup,preview.token); return true end
  assert(cleanup:confirm(preview.token)); eqRunningRejections(beforeCalls); eqRunningRejections(afterCalls)
end)

test("expiry and clock exceptions consume the token and release the lock",function()
  local cleanup,map=fixture(); local preview=assert(cleanup:previewRoom(100)); local original=cleanup.clock
  function cleanup.clock() error("clock exploded") end
  local result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup confirmation failed: clock exploded"); eq(map.deleteCalls,0)
  result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup confirmation token is invalid")
  cleanup.clock=original; assert(cleanup:previewRoom(100))

  local cleanup2,map2,_,setNow=fixture(); local expired=assert(cleanup2:previewRoom(100)); setNow(1031)
  result,err=cleanup2:confirm(expired.token); eq(result,nil); eq(err,"cleanup confirmation token has expired"); eq(map2.deleteCalls,0)
  assert(cleanup2:previewRoom(100))
end)

test("every final rebuild dependency exception consumes the token unlocks and performs zero mutation",function()
  local cases={
    {name="room record",preview="room",install=function(cleanup,map) local original=map.roomRecord; function map:roomRecord() error("room record exploded") end; return function() map.roomRecord=original end end},
    {name="inbound",preview="room",install=function(cleanup,map) local original=map.inboundSources; function map:inboundSources() error("inbound exploded") end; return function() map.inboundSources=original end end},
    {name="safety",preview="room",install=function(cleanup,map,runtime) local original=runtime.safetySnapshot; function runtime:safetySnapshot() error("safety exploded") end; return function() runtime.safetySnapshot=original end end},
    {name="area table",preview="area",expected="cleanup preview is stale",install=function(cleanup,map) local original=map.api.getAreaTable; function map.api.getAreaTable() error("area table exploded") end; return function() map.api.getAreaTable=original end end},
    {name="area record",preview="area",install=function(cleanup,map) local original=map.areaRecord; function map:areaRecord() error("area record exploded") end; return function() map.areaRecord=original end end},
    {name="area rooms",preview="area",install=function(cleanup,map) local original=map.roomsInArea; function map:roomsInArea() error("area rooms exploded") end; return function() map.roomsInArea=original end end},
  }
  for _,case in ipairs(cases) do
    local cleanup,map,runtime=fixture()
    local preview=case.preview=="area" and assert(cleanup:previewArea("Alpha")) or assert(cleanup:previewRoom(100))
    local restore=case.install(cleanup,map,runtime)
    local result,err=cleanup:confirm(preview.token)
    eq(result,nil); eq(err,case.expected or ("cleanup confirmation failed: "..case.name.." exploded")); eq(map.deleteCalls,0); eq(runtime.beforeCalls,0); eq(runtime.afterCalls,0)
    result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,"cleanup confirmation token is invalid")
    restore(); assert(cleanup:previewRoom(100))
  end
end)

test("beforeDelete returned failures and exceptions release the lock without map mutation",function()
  for _,throws in ipairs({false,true}) do
    local cleanup,map,runtime=fixture(); local preview=assert(cleanup:previewRoom(100))
    function runtime:beforeDelete()
      if throws then error("before exploded") end
      return nil,"before rejected"
    end
    local result,err=cleanup:confirm(preview.token); eq(result,nil); eq(err,throws and "cleanup confirmation failed: before exploded" or "before rejected")
    eq(map.deleteCalls,0); eq(runtime.afterCalls,0); assert(cleanup:previewRoom(100))
  end
end)

test("thrown room deletion reports exact partial state calls afterDelete and unlocks",function()
  local cleanup,map,runtime=fixture(); local original=map.deleteOwnedRoom
  function map:deleteOwnedRoom(id) if id==201 then error("room delete exploded") end; return original(self,id) end
  local result=assert(cleanup:confirm(assert(cleanup:previewArea(8)).token))
  listEq(result.deleted,{200}); eq(result.failed,201); eq(result.error,"room delete exploded"); listEq(result.untouched,{201}); eq(result.area_deleted,false)
  eq(runtime.afterCalls,1); listEq(runtime.afterResult.deleted,{200}); eq(runtime.afterResult.failed,201)
  assert(cleanup:previewRoom(201))
end)

test("thrown area deletion is reported finalized and unlocked",function()
  local cleanup,map,runtime=fixture(); function map:deleteEmptyOwnedArea() error("area delete exploded") end
  local result=assert(cleanup:confirm(assert(cleanup:previewArea(8)).token))
  listEq(result.deleted,{200,201}); eq(result.area_deleted,false); eq(result.area_error,"area delete exploded"); eq(runtime.afterCalls,1)
  eq(cleanup:cancel(),true)
end)

test("invalidation returned failures and exceptions prevent clean success and still finalize",function()
  for _,throws in ipairs({false,true}) do
    local cleanup,map,runtime=fixture()
    function map:invalidateDeleted()
      if throws then error("invalidate exploded") end
      return nil,"invalidate rejected"
    end
    local result=assert(cleanup:confirm(assert(cleanup:previewRoom(100)).token))
    listEq(result.deleted,{100}); eq(result.invalidation_error,throws and "invalidate exploded" or "invalidate rejected"); eq(result.error,result.invalidation_error)
    eq(runtime.afterCalls,1); eq(runtime.afterResult.invalidation_error,result.invalidation_error)
    eq(cleanup:cancel(),true)
  end
end)

test("afterDelete returned failures and exceptions are reported and release the lock",function()
  for _,throws in ipairs({false,true}) do
    local cleanup,_,runtime=fixture()
    function runtime:afterDelete()
      self.afterCalls=self.afterCalls+1
      if throws then error("after exploded") end
      return nil,"after rejected"
    end
    local result=assert(cleanup:confirm(assert(cleanup:previewRoom(100)).token))
    eq(result.lifecycle_error,throws and "after exploded" or "after rejected"); eq(result.error,result.lifecycle_error); eq(runtime.afterCalls,1)
    eq(cleanup:cancel(),true)
  end
end)

local function realAdapterWithPersonalInbound(kind)
  local rooms={
    [50]={owner=nil,area=1,exits={},special={}},
    [100]={owner="DragonsGateHUD",area=2,exits={},special={}},
  }
  if kind=="ordinary" then rooms[50].exits.n=100 else rooms[50].special[100]={portal=true} end
  local api={
    roomExists=function(id) return rooms[id]~=nil end,
    getRoomUserData=function(id,key) if key=="dghud.owner" then return rooms[id] and rooms[id].owner end end,
    getRoomArea=function(id) return rooms[id] and rooms[id].area end,
    getRoomCoordinates=function() return 0,0,0 end,
    getRooms=function() return {[50]="Personal",[100]="HUD"} end,
    getRoomExits=function(id) return rooms[id].exits end,
    getSpecialExits=function(id) return rooms[id].special end,
  }
  return MapAdapter.new(api),rooms
end

test("real map adapter ordinary personal inbound exits block cleanup",function()
  local map,rooms=realAdapterWithPersonalInbound("ordinary"); local runtime=fakeRuntime()
  local cleanup=Cleanup.new(map,runtime,function() return 1000 end,function() return "ordinary" end,30)
  local result,err=cleanup:previewRoom(100); eq(result,nil); eq(err,"unowned room 50 has an inbound exit"); eq(rooms[100]~=nil,true); eq(rooms[50].exits.n,100)
end)

test("real map adapter special personal inbound exits block cleanup",function()
  local map,rooms=realAdapterWithPersonalInbound("special"); local runtime=fakeRuntime()
  local cleanup=Cleanup.new(map,runtime,function() return 1000 end,function() return "special" end,30)
  local result,err=cleanup:previewRoom(100); eq(result,nil); eq(err,"unowned room 50 has an inbound exit"); eq(rooms[100]~=nil,true); eq(rooms[50].special[100].portal,true)
end)
