local Adapter=require("map_adapter")
local Automapper=require("automapper")
local Model=require("mapper_model")

local function fakeMapApi(seed)
  local api={rooms=seed or {},areas={},areaUser={},nextArea=1,fail={},path=nil,refreshed=0,deletedRooms={},deletedAreas={},special={},specialAdds=0,zoom={}}
  local function gate(name)
    if api.fail[name]=="throw" then error(name.." exploded") end
    if api.fail[name] then return nil,name.." rejected" end
    return true
  end
  function api.roomExists(id) local ok,e=gate("roomExists"); if not ok then return nil,e end; return api.rooms[id]~=nil end
  function api.addRoom(id) local ok,e=gate("addRoom"); if not ok then return nil,e end; api.rooms[id]={area=-1,x=0,y=0,z=0,user={},exits={},stubs={}}; return true end
  function api.deleteRoom(id) local ok,e=gate("deleteRoom"); if not ok then return nil,e end; api.rooms[id]=nil; api.deletedRooms[#api.deletedRooms+1]=id; return true end
  function api.getAreaTable() local ok,e=gate("getAreaTable"); if not ok then return nil,e end; local t={}; for n,id in pairs(api.areas) do t[n]=id end; return t end
  function api.addAreaName(name) local ok,e=gate("addAreaName"); if not ok then return nil,e end; if api.areas[name] then return nil,"area already exists" end; local id=api.nextArea; api.nextArea=id+1; api.areas[name]=id; api.areaUser[id]={}; return id end
  function api.deleteArea(id) local ok,e=gate("deleteArea"); if not ok then return nil,e end; for name,areaID in pairs(api.areas) do if areaID==id then api.areas[name]=nil end end; api.areaUser[id]=nil; api.deletedAreas[#api.deletedAreas+1]=id; return true end
  function api.setAreaUserData(id,k,v) local ok,e=gate("setAreaUserData"); if not ok then return nil,e end; api.areaUser[id]=api.areaUser[id] or {}; api.areaUser[id][k]=v; return true end
  function api.getAreaUserData(id,k) local ok,e=gate("getAreaUserData"); if not ok then return nil,e end; return api.areaUser[id] and api.areaUser[id][k] end
  function api.getAreaRooms1(id)
    local ok,e=gate("getAreaRooms1"); if not ok then return nil,e end
    local out,index={},0
    for roomID,room in pairs(api.rooms) do if room.area==id then out[index]=roomID; index=index+1 end end
    return out
  end
  function api.setRoomArea(id,v) local ok,e=gate("setRoomArea"); if not ok then return nil,e end; api.rooms[id].area=v; return true end
  function api.getRoomArea(id) local ok,e=gate("getRoomArea"); if not ok then return nil,e end; return api.rooms[id] and api.rooms[id].area end
  function api.setRoomName(id,v) local ok,e=gate("setRoomName"); if not ok then return nil,e end; api.rooms[id].name=v; return true end
  function api.setRoomCoordinates(id,x,y,z) local ok,e=gate("setRoomCoordinates"); if not ok then return nil,e end; local r=api.rooms[id]; r.x=x;r.y=y;r.z=z; return true end
  function api.setRoomUserData(id,k,v) local ok,e=gate("setRoomUserData"); if not ok then return nil,e end; api.rooms[id].user[k]=v; return true end
  function api.getRoomUserData(id,k)
    local ok,e=gate("getRoomUserData"); if not ok then return nil,e end
    local room=api.rooms[id]
    if not room then return "" end
    local value=room.user[k]
    return value==nil and "" or value
  end
  function api.setExitStub(id,d) local ok,e=gate("setExitStub"); if not ok then return nil,e end; api.rooms[id].stubs[d]=true; return true end
  function api.setExit(id,to,d) local ok,e=gate("setExit"); if not ok then return nil,e end; api.rooms[id].exits[d]=to; return true end
  function api.getRoomExits(id)
    local ok,e=gate("getRoomExits"); if not ok then return nil,e end
    local out={}; for direction,to in pairs((api.rooms[id] and api.rooms[id].exits) or {}) do out[direction]=to end; return out
  end
  function api.addSpecialExit(from,to,command)
    local ok,e=gate("addSpecialExit"); if not ok then return nil,e end
    api.special[from]=api.special[from] or {}; api.special[from][command]=to; api.specialAdds=api.specialAdds+1; return true
  end
  function api.getSpecialExits(from,listAll)
    local ok,e=gate("getSpecialExits"); if not ok then return nil,e end
    eq(listAll,true)
    local grouped={}
    for command,to in pairs(api.special[from] or {}) do grouped[to]=grouped[to] or {}; grouped[to][command]="0" end
    return grouped
  end
  function api.getRoomCoordinates(id) local ok,e=gate("getRoomCoordinates"); if not ok then return nil,e end; local r=api.rooms[id]; return r and r.x,r and r.y,r and r.z end
  function api.getRooms() local ok,e=gate("getRooms"); if not ok then return nil,e end; local out={}; for id,r in pairs(api.rooms) do out[r.name or ("Room "..id)]=id end; return out end
  function api.getRoomsByPosition(area,x,y,z) local ok,e=gate("getRoomsByPosition"); if not ok then return nil,e end; local out,i={},0; for id,r in pairs(api.rooms) do if r.area==area and r.x==x and r.y==y and r.z==z then out[i]=id;i=i+1 end end; return out end
  function api.getMapZoom(area) local ok,e=gate("getMapZoom"); if not ok then return nil,e end; return api.zoom[area] end
  function api.setMapZoom(value,area) local ok,e=gate("setMapZoom"); if not ok then return nil,e end; api.zoom[area]=value; return true end
  function api.centerview(id) local ok,e=gate("centerview"); if not ok then return nil,e end; api.centered=id; return true end
  function api.getPath(a,b) local ok,e=gate("getPath"); if not ok then return nil,e end; return api.path or {a.."-"..b} end
  function api.updateMap() local ok,e=gate("updateMap"); if not ok then return nil,e end; api.refreshed=api.refreshed+1; return true end
  return api
end

local function descriptor(id,area,name)
  return {id=id,name=name or ("Room "..id),area_key=area or "A",environment="Plain",flags={"indoor"},exits={}}
end

local function gmcpRoom(id,area,name,exits)
  return {num=id,name=name or ("Room "..id),area=area or 1,environment="Plain",flags={"indoor"},exits=exits or {}}
end

test("creates a fully tagged room and finalizes readiness last",function()
  local api=fakeMapApi(); local calls={}; local native=api.setRoomUserData
  api.setRoomUserData=function(id,k,v) calls[#calls+1]=k; return native(id,k,v) end
  assert(Adapter.new(api):ensureRoom(descriptor(176,"1","Training square."),{x=0,y=1,z=2}))
  local r=api.rooms[176]; eq(r.name,""); eq(r.user["dghud.owner"],"DragonsGateHUD"); eq(calls[#calls],"dghud.state"); eq(r.user["dghud.state"],"ready")
  eq(r.user["dghud.mapper_schema"],"1"); eq(r.user["dghud.environment"],"Plain"); eq(r.user["dghud.flags"],"indoor")
  eq(r.x,0); eq(r.y,1); eq(r.z,2); eq(api.areaUser[r.area]["dghud.owner"],"DragonsGateHUD")
end)

test("HUD rooms keep native mapper labels blank while preserving descriptive metadata",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(176,"1","Training square."),{x=0,y=0,z=0}))
  eq(api.rooms[176].name,"")
  eq(api.rooms[176].user["dghud.room_name"],"Training square.")
  assert(map:ensureRoom(descriptor(176,"1","Training Center."),{x=9,y=9,z=9}))
  eq(api.rooms[176].name,"")
  eq(api.rooms[176].user["dghud.room_name"],"Training Center.")
end)

test("legacy label cleanup changes only HUD-owned rooms",function()
  local api=fakeMapApi({
    [10]={name="Old HUD label",user={["dghud.owner"]="DragonsGateHUD"}},
    [11]={name="Personal room",user={}},
    [12]={name="Other package",user={["dghud.owner"]="SomeoneElse"}},
  })
  local count=assert(Adapter.new(api):clearOwnedRoomNames())
  eq(count,1); eq(api.rooms[10].name,""); eq(api.rooms[11].name,"Personal room"); eq(api.rooms[12].name,"Other package")
end)

test("legacy label cleanup deduplicates room ids and reports read failures",function()
  local api=fakeMapApi({[10]={name="Old",user={["dghud.owner"]="DragonsGateHUD"}}})
  local nativeGetRooms=api.getRooms
  api.getRooms=function() return {Old=10,Duplicate="10",invalid="nope"} end
  eq(Adapter.new(api):clearOwnedRoomNames(),1)
  api.getRooms=nativeGetRooms
  api.fail.getRooms=true
  local count,err=Adapter.new(api):clearOwnedRoomNames(); eq(count,nil); eq(err,"getRooms rejected")
end)

test("reuses a persisted owned area after adapter reload",function()
  local api=fakeMapApi(); assert(Adapter.new(api):ensureRoom(descriptor(1,"Castle"),{})); local area=api.rooms[1].area
  assert(Adapter.new(api):ensureRoom(descriptor(2,"Castle"),{})); eq(api.rooms[2].area,area); eq(api.nextArea,2)
end)

test("rejects an unowned area collision before adding a room",function()
  local api=fakeMapApi(); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={}; api.nextArea=42
  local ok,e=Adapter.new(api):ensureRoom(descriptor(7,"Castle"),{}); eq(ok,nil); eq(e,"area Dragons Gate - Castle is not owned by DragonsGateHUD"); eq(api.rooms[7],nil)
end)

test("creates distinct areas with distinct IDs",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1,"A"),{})); assert(map:ensureRoom(descriptor(2,"B"),{})); assert(api.rooms[1].area~=api.rooms[2].area)
end)

test("persists a special destination partition keyed by canonical room ID",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Vault"),{x=0,y=0,z=0},"special:900"))
  eq(api.rooms[900].user["dghud.partition"],"special:900")
  eq(api.rooms[900].user["dghud.game_area"],"1")
  eq(api.areas["Dragons Gate - Submap 900"],api.rooms[900].area)
  local record=assert(Adapter.new(api):roomRecord(900))
  eq(record.exists,true); eq(record.owned,true); eq(record.partition,"special:900"); eq(record.area,api.rooms[900].area)
  eq(record.coordinates.x,0); eq(record.coordinates.y,0); eq(record.coordinates.z,0); eq(record.placement_needed,false)
end)

test("existing canonical rooms retain their area coordinates and partition",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1"),{x=0,y=0,z=0},"special:900"))
  local area=api.rooms[900].area
  assert(map:ensureRoom(descriptor(900,"2","Revisited"),{x=8,y=8,z=4},"special:other"))
  eq(api.rooms[900].area,area); eq(api.rooms[900].x,0); eq(api.rooms[900].y,0); eq(api.rooms[900].z,0)
  eq(api.rooms[900].user["dghud.partition"],"special:900")
  eq(api.rooms[900].user["dghud.game_area"],"1")
  eq(api.rooms[900].name,""); eq(api.rooms[900].user["dghud.room_name"],"Revisited")
end)

test("migrates an existing owned room to its current effective partition without moving it",function()
  local existing={name="Legacy",area=41,x=3,y=4,z=1,user={["dghud.owner"]="DragonsGateHUD",["dghud.state"]="ready"},exits={},stubs={}}
  local api=fakeMapApi({[900]=existing}); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={["dghud.owner"]="DragonsGateHUD"}; api.nextArea=42
  local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Migrated"),{x=8,y=8,z=4},"special:900"))
  eq(existing.area,41); eq(existing.x,3); eq(existing.y,4); eq(existing.z,1)
  eq(existing.user["dghud.partition"],"Castle"); eq(existing.user["dghud.game_area"],"1")
  eq(assert(map:effectivePartition(900)),"Castle"); eq(api.nextArea,42)
end)

test("migration from an unowned area never authorizes new placement",function()
  local existing={name="Legacy",area=41,x=3,y=4,z=1,user={["dghud.owner"]="DragonsGateHUD",["dghud.state"]="ready"},exits={},stubs={}}
  local api=fakeMapApi({[900]=existing}); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={}; api.nextArea=42
  local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(900,"1","Migrated"),{x=8,y=8,z=4},"special:900"))
  eq(existing.area,41); eq(existing.x,3); eq(existing.y,4); eq(existing.z,1); eq(existing.user["dghud.partition"],"Castle")

  local mutations=0
  for _,name in ipairs({"addRoom","deleteRoom","addAreaName","deleteArea","setAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData"}) do
    local native=api[name]
    api[name]=function(...) mutations=mutations+1; return native(...) end
  end
  local ok,e=map:ensureRoom(descriptor(901,"Castle"),{x=5,y=5,z=0},"Castle")
  eq(ok,nil); eq(e,"area Dragons Gate - Castle is not owned by DragonsGateHUD")
  eq(mutations,0); eq(api.rooms[901],nil); eq(api.nextArea,42)
end)

test("refuses an unowned canonical room collision with zero mutation",function()
  local original={name="Personal",area=9,user={},x=8,y=7,z=6,exits={},stubs={}}; local api=fakeMapApi({[176]=original})
  local mutations=0
  for _,name in ipairs({"addRoom","deleteRoom","addAreaName","deleteArea","setAreaUserData","setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData"}) do
    local native=api[name]
    api[name]=function(...) mutations=mutations+1; return native(...) end
  end
  local map=Adapter.new(api); local record=assert(map:roomRecord(176))
  eq(record.exists,true); eq(record.owned,false); eq(record.area,9); eq(record.coordinates.x,8)
  local ok,e=map:ensureRoom(descriptor(176),{x=0},"special:176")
  eq(ok,nil); eq(e,"room 176 is not owned by DragonsGateHUD"); eq(mutations,0)
  eq(original.name,"Personal"); eq(original.area,9); eq(original.x,8); eq(original.y,7); eq(original.z,6); eq(next(original.user),nil)
end)

test("updates owned rooms and retains ownership on failure",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(1,"A","Changed"),{x=2,y=3,z=0})); eq(api.rooms[1].name,""); eq(api.rooms[1].user["dghud.room_name"],"Changed")
  api.fail.setRoomName=true; local ok,e=map:ensureRoom(descriptor(1,"A","Nope"),{}); eq(ok,nil); eq(e,"setRoomName rejected"); eq(api.rooms[1].user["dghud.owner"],"DragonsGateHUD")
end)

test("post-create room mutation failures remain safely retryable",function()
  for _,name in ipairs({"setRoomArea","setRoomName","setRoomCoordinates"}) do
    local api=fakeMapApi(); local map=Adapter.new(api); api.fail[name]=true; local ok,e=map:ensureRoom(descriptor(20),{})
    eq(ok,nil); eq(e,name.." rejected"); eq(api.rooms[20].user["dghud.owner"],"DragonsGateHUD"); eq(api.rooms[20].user["dghud.state"],"provisional")
    api.fail[name]=nil; assert(map:ensureRoom(descriptor(20),{x=2,y=3,z=4})); eq(api.rooms[20].user["dghud.state"],"ready")
    assert(api.rooms[20].area); eq(api.rooms[20].x,2); eq(api.rooms[20].y,3); eq(api.rooms[20].z,4)
  end
  for failureCall=2,6 do
    local api=fakeMapApi(); local map=Adapter.new(api); local native=api.setRoomUserData; local calls=0
    api.setRoomUserData=function(...) calls=calls+1; if calls==failureCall then return nil,"room metadata rejected" end; return native(...) end
    local ok,e=map:ensureRoom(descriptor(21),{}); eq(ok,nil); eq(e,"room metadata rejected"); api.setRoomUserData=native
    assert(map:ensureRoom(descriptor(21),{})); eq(api.rooms[21].user["dghud.owner"],"DragonsGateHUD"); eq(api.rooms[21].user["dghud.state"],"ready")
  end
end)

test("fresh adapter recovers an owned room after its provisional state write failed",function()
  local api=fakeMapApi(); local native=api.setRoomUserData; local rejectProvisional=true
  api.setRoomUserData=function(id,k,v)
    if rejectProvisional and k=="dghud.state" and v=="provisional" then return nil,"provisional state rejected" end
    return native(id,k,v)
  end
  local ok,e=Adapter.new(api):ensureRoom(descriptor(22,"Castle"),{x=1,y=2,z=3},"special:22")
  eq(ok,nil); eq(e,"provisional state rejected"); assert(api.rooms[22]); eq(api.rooms[22].user["dghud.owner"],"DragonsGateHUD")
  eq(api.rooms[22].user["dghud.state"],nil); eq(api.rooms[22].user["dghud.mapper_schema"],nil); eq(api.rooms[22].user["dghud.environment"],nil)
  eq(api.rooms[22].user["dghud.flags"],nil); eq(api.rooms[22].user["dghud.partition"],nil); eq(api.rooms[22].user["dghud.game_area"],nil)
  eq(api.rooms[22].area,-1); eq(api.rooms[22].x,0); eq(api.rooms[22].y,0); eq(api.rooms[22].z,0); eq(#api.deletedRooms,0)
  local interrupted=assert(Adapter.new(api):roomRecord(22))
  eq(interrupted.state,nil); eq(interrupted.mapper_schema,nil); eq(interrupted.environment,nil)
  eq(interrupted.flags,nil); eq(interrupted.partition,nil); eq(interrupted.game_area,nil); eq(interrupted.placement_needed,true)

  rejectProvisional=false
  local mutations={}; local nativeArea=api.setRoomArea; local nativeCoordinates=api.setRoomCoordinates
  api.setRoomUserData=function(id,k,v) mutations[#mutations+1]=k.."="..v; return native(id,k,v) end
  api.setRoomArea=function(id,v) mutations[#mutations+1]="area="..v; return nativeArea(id,v) end
  api.setRoomCoordinates=function(id,x,y,z) mutations[#mutations+1]="coordinates="..x..","..y..","..z; return nativeCoordinates(id,x,y,z) end
  assert(Adapter.new(api):ensureRoom(descriptor(22,"Castle"),{x=1,y=2,z=3},"special:22"))
  local intendedArea=api.areas["Dragons Gate - Submap 22"]; eq(api.rooms[22].area,intendedArea)
  eq(api.rooms[22].user["dghud.partition"],"special:22"); eq(api.rooms[22].user["dghud.game_area"],"Castle")
  eq(api.rooms[22].x,1); eq(api.rooms[22].y,2); eq(api.rooms[22].z,3); eq(api.rooms[22].user["dghud.state"],"ready")
  eq(mutations[#mutations-4],"dghud.partition=special:22"); eq(mutations[#mutations-3],"dghud.game_area=Castle")
  eq(mutations[#mutations-2],"area="..intendedArea); eq(mutations[#mutations-1],"coordinates=1,2,3"); eq(mutations[#mutations],"dghud.state=ready")
  eq(#api.deletedRooms,0)
end)

test("fresh automapper retry places an owner-only special destination in its destination submap",function()
  local api=fakeMapApi(); local rejectProvisional=false; local nativeUserData=api.setRoomUserData; local statuses={}
  api.setRoomUserData=function(id,key,value)
    if rejectProvisional and id==900 and key=="dghud.state" and value=="provisional" then return nil,"provisional state rejected" end
    return nativeUserData(id,key,value)
  end
  local first=Automapper.new(Model,Adapter.new(api),function(kind,message) statuses[#statuses+1]={kind=kind,message=message} end)
  assert(first:onRoom(gmcpRoom(100,1,"Outside")))
  assert(first:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  rejectProvisional=true
  local ok,e=first:onRoom(gmcpRoom(900,1,"Inside")); eq(ok,nil); eq(e,"provisional state rejected")
  eq(api.rooms[900].area,-1); eq(api.rooms[900].x,0); eq(api.rooms[900].y,0); eq(api.rooms[900].z,0)

  rejectProvisional=false
  ok,e=first:onRoom(gmcpRoom(900,1,"Inside refreshed"))
  eq(ok,nil); eq(e,"room 900 placement requires an observed transition")
  eq(statuses[#statuses].kind,"invalid_room"); eq(statuses[#statuses].message,e)
  local stillInterrupted=assert(Adapter.new(api):roomRecord(900))
  eq(stillInterrupted.placement_needed,true); eq(stillInterrupted.state,nil); eq(stillInterrupted.partition,nil)
  eq(stillInterrupted.area,-1); eq(stillInterrupted.coordinates.x,0); eq(stillInterrupted.coordinates.y,0); eq(stillInterrupted.coordinates.z,0)
  eq(first:currentRoom(),nil); eq(api.special[100],nil)

  local retried=Automapper.new(Model,Adapter.new(api),function() end)
  assert(retried:onRoom(gmcpRoom(100,1,"Outside")))
  assert(retried:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  assert(retried:onRoom(gmcpRoom(900,1,"Inside")))
  local submapArea=api.areas["Dragons Gate - Submap 900"]
  local record=assert(Adapter.new(api):roomRecord(900))
  eq(record.partition,"special:900"); eq(record.area,submapArea)
  eq(record.coordinates.x,0); eq(record.coordinates.y,0); eq(record.coordinates.z,0); eq(record.state,"ready")
  eq(api.special[100]["go gate"],900)
end)

test("fresh automapper retry derives coordinates for a provisional directional continuation",function()
  local api=fakeMapApi(); local statuses={}
  assert(Adapter.new(api):ensureRoom(descriptor(900,"1","Root"),{x=0,y=0,z=0},"special:900"))
  local submapArea=api.areas["Dragons Gate - Submap 900"]

  local first=Automapper.new(Model,Adapter.new(api),function(kind,message) statuses[#statuses+1]={kind=kind,message=message} end)
  assert(first:onRoom(gmcpRoom(900,1,"Root",{"north"})))
  assert(first:onOutgoing("north"))
  api.fail.setRoomCoordinates=true
  local ok,e=first:onRoom(gmcpRoom(901,1,"Hall",{"south"}))
  eq(ok,nil); eq(e,"setRoomCoordinates rejected")
  local interrupted=assert(Adapter.new(api):roomRecord(901))
  eq(interrupted.state,"provisional"); eq(interrupted.placement_needed,true)
  eq(interrupted.partition,"special:900"); eq(interrupted.area,submapArea)
  eq(interrupted.coordinates.x,0); eq(interrupted.coordinates.y,0); eq(interrupted.coordinates.z,0)

  api.fail.setRoomCoordinates=nil
  ok,e=first:onRoom(gmcpRoom(901,1,"Hall refreshed",{"south"}))
  eq(ok,nil); eq(e,"room 901 placement requires an observed transition")
  eq(statuses[#statuses].kind,"invalid_room"); eq(statuses[#statuses].message,e)
  local stillInterrupted=assert(Adapter.new(api):roomRecord(901))
  eq(stillInterrupted.placement_needed,true); eq(stillInterrupted.state,"provisional")
  eq(stillInterrupted.partition,"special:900"); eq(stillInterrupted.area,submapArea)
  eq(stillInterrupted.coordinates.x,0); eq(stillInterrupted.coordinates.y,0); eq(stillInterrupted.coordinates.z,0)
  eq(first:currentRoom(),nil); eq(api.rooms[900].exits.n,nil); eq(api.rooms[901].exits.s,nil)

  local retried=Automapper.new(Model,Adapter.new(api),function() end)
  assert(retried:onRoom(gmcpRoom(900,1,"Root",{"north"})))
  assert(retried:onOutgoing("north"))
  assert(retried:onRoom(gmcpRoom(901,1,"Hall",{"south"})))
  local record=assert(Adapter.new(api):roomRecord(901))
  eq(record.state,"ready"); eq(record.placement_needed,false)
  eq(record.partition,"special:900"); eq(record.area,submapArea)
  eq(record.coordinates.x,0); eq(record.coordinates.y,1); eq(record.coordinates.z,0)
  eq(api.rooms[900].exits.n,901); eq(api.rooms[901].exits.s,900)
end)

test("mature owned legacy room without state is never relocated",function()
  local existing={name="Legacy",area=41,x=3,y=4,z=1,user={["dghud.owner"]="DragonsGateHUD",["dghud.mapper_schema"]="1"},exits={},stubs={}}
  local api=fakeMapApi({[24]=existing}); api.areas["Dragons Gate - Castle"]=41; api.areaUser[41]={["dghud.owner"]="DragonsGateHUD"}; api.nextArea=42
  assert(Adapter.new(api):ensureRoom(descriptor(24,"2","Refreshed"),{x=8,y=8,z=4},"special:24"))
  eq(existing.area,41); eq(existing.x,3); eq(existing.y,4); eq(existing.z,1); eq(existing.name,""); eq(existing.user["dghud.room_name"],"Refreshed")
  eq(existing.user["dghud.partition"],"Castle"); eq(existing.user["dghud.game_area"],"2"); eq(existing.user["dghud.state"],"ready")
  eq(api.nextArea,42); eq(#api.deletedRooms,0)
end)

test("fresh adapter finishes provisional coordinates before marking the room ready",function()
  local api=fakeMapApi(); api.fail.setRoomCoordinates=true
  local ok,e=Adapter.new(api):ensureRoom(descriptor(23,"Castle"),{x=1,y=2,z=3},"special:23")
  eq(ok,nil); eq(e,"setRoomCoordinates rejected"); eq(api.rooms[23].user["dghud.state"],"provisional")
  assert(api.rooms[23].area); eq(api.rooms[23].x,0); eq(api.rooms[23].y,0); eq(api.rooms[23].z,0); eq(#api.deletedRooms,0)
  local record=assert(Adapter.new(api):roomRecord(23)); eq(record.state,"provisional"); eq(record.placement_needed,true)

  ok,e=Adapter.new(api):ensureRoom(descriptor(23,"Castle"),{x=7,y=8,z=9},"special:23")
  eq(ok,nil); eq(e,"setRoomCoordinates rejected"); eq(api.rooms[23].user["dghud.state"],"provisional"); eq(#api.deletedRooms,0)

  api.fail.setRoomCoordinates=nil
  local mutations={}; local nativeCoordinates=api.setRoomCoordinates; local nativeUserData=api.setRoomUserData
  api.setRoomCoordinates=function(...) mutations[#mutations+1]="coordinates"; return nativeCoordinates(...) end
  api.setRoomUserData=function(id,k,v) mutations[#mutations+1]=k.."="..v; return nativeUserData(id,k,v) end
  assert(Adapter.new(api):ensureRoom(descriptor(23,"Castle"),{x=7,y=8,z=9},"special:23"))
  eq(api.rooms[23].x,7); eq(api.rooms[23].y,8); eq(api.rooms[23].z,9)
  eq(api.rooms[23].user["dghud.state"],"ready"); eq(mutations[#mutations],"dghud.state=ready"); eq(#api.deletedRooms,0)
end)

test("post-create area metadata failures remain safely retryable",function()
  for _,failureCall in ipairs({2,3,4}) do
    local api=fakeMapApi(); local map=Adapter.new(api); local native=api.setAreaUserData; local calls=0
    api.setAreaUserData=function(...) calls=calls+1; if calls==failureCall then return nil,"area metadata rejected" end; return native(...) end
    local ok,e=map:ensureArea("Retry"); eq(ok,nil); eq(e,"area metadata rejected")
    local id=api.areas["Dragons Gate - Retry"]; assert(id); api.setAreaUserData=native
    assert(map:ensureArea("Retry")); eq(api.areaUser[id]["dghud.owner"],"DragonsGateHUD"); eq(api.areaUser[id]["dghud.state"],"ready")
  end
end)

test("rolls back a new area when its first ownership write fails across reload",function()
  local api=fakeMapApi(); local native=api.setAreaUserData; local calls=0
  api.setAreaUserData=function(...) calls=calls+1; if calls==1 then return nil,"area ownership rejected" end; return native(...) end
  local ok,e=Adapter.new(api):ensureArea("Restart"); eq(ok,nil); eq(e,"area ownership rejected")
  eq(api.areas["Dragons Gate - Restart"],nil); eq(#api.deletedAreas,1)
  api.setAreaUserData=native
  local area=assert(Adapter.new(api):ensureArea("Restart")); assert(area); eq(api.areaUser[area]["dghud.owner"],"DragonsGateHUD")
end)

test("rolls back a new room when its first ownership write fails across reload",function()
  local api=fakeMapApi(); local native=api.setRoomUserData; local calls=0
  api.setRoomUserData=function(...) calls=calls+1; if calls==1 then return nil,"room ownership rejected" end; return native(...) end
  local ok,e=Adapter.new(api):ensureRoom(descriptor(31,"Restart"),{}); eq(ok,nil); eq(e,"room ownership rejected")
  eq(api.rooms[31],nil); eq(api.deletedRooms[1],31)
  api.setRoomUserData=native
  assert(Adapter.new(api):ensureRoom(descriptor(31,"Restart"),{})); eq(api.rooms[31].user["dghud.owner"],"DragonsGateHUD")
end)

test("reports ownership and rollback failures together",function()
  local areaApi=fakeMapApi(); areaApi.fail.setAreaUserData=true; areaApi.fail.deleteArea=true
  local ok,e=Adapter.new(areaApi):ensureArea("Broken"); eq(ok,nil); assert(e:find("setAreaUserData rejected",1,true)); assert(e:find("rollback failed",1,true)); assert(e:find("deleteArea rejected",1,true))

  local roomApi=fakeMapApi(); assert(Adapter.new(roomApi):ensureArea("A")); roomApi.fail.setRoomUserData=true; roomApi.fail.deleteRoom=true
  ok,e=Adapter.new(roomApi):ensureRoom(descriptor(32,"A"),{}); eq(ok,nil); assert(e:find("setRoomUserData rejected",1,true)); assert(e:find("rollback failed",1,true)); assert(e:find("deleteRoom rejected",1,true))
end)

test("never deletes preexisting collisions or owned rooms on update failure",function()
  local personal={name="Personal",user={},exits={},stubs={}}; local api=fakeMapApi({[40]=personal})
  api.areas["Dragons Gate - Personal"]=9; api.areaUser[9]={}
  local map=Adapter.new(api); eq(map:ensureRoom(descriptor(40),{}),nil); eq(map:ensureArea("Personal"),nil)
  eq(#api.deletedRooms,0); eq(#api.deletedAreas,0); eq(api.rooms[40],personal); eq(api.areas["Dragons Gate - Personal"],9)

  local managed=fakeMapApi(); local managedMap=Adapter.new(managed); assert(managedMap:ensureRoom(descriptor(41),{}))
  managed.fail.setRoomName=true; eq(managedMap:ensureRoom(descriptor(41,"A","Changed"),{}),nil)
  eq(#managed.deletedRooms,0); eq(#managed.deletedAreas,0); assert(managed.rooms[41])

  local persistedArea=fakeMapApi(); assert(Adapter.new(persistedArea):ensureArea("Owned")); persistedArea.fail.setAreaUserData=true
  eq(Adapter.new(persistedArea):ensureArea("Owned"),nil); eq(#persistedArea.deletedAreas,0); assert(persistedArea.areas["Dragons Gate - Owned"])
end)

test("never adopts preexisting unowned provisional-looking objects",function()
  local api=fakeMapApi({[20]={user={['dghud.state']='provisional'},exits={},stubs={}}})
  api.areas["Dragons Gate - Personal"]=9; api.areaUser[9]={['dghud.state']='provisional'}
  local map=Adapter.new(api); local ok=map:ensureRoom(descriptor(20),{}); eq(ok,nil); ok=map:ensureArea("Personal"); eq(ok,nil)
end)

test("individual deletion accepts only a persisted HUD-owned room",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0}))
  eq(map:deleteOwnedRoom(100),true); eq(api.rooms[100],nil); eq(api.deletedRooms[1],100)

  api.rooms[101]={area=9,user={},exits={},stubs={}}
  local ok,e=map:deleteOwnedRoom(101)
  eq(ok,nil); eq(e,"room 101 is not owned by DragonsGateHUD"); eq(api.rooms[101]~=nil,true); eq(#api.deletedRooms,1)
end)

test("individual deletion rechecks persisted ownership immediately before mutation",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0}))
  assert(map:roomRecord(100)); api.rooms[100].user["dghud.owner"]="PersonalMapper"
  local ok,e=map:deleteOwnedRoom(100)
  eq(ok,nil); eq(e,"room 100 is not owned by DragonsGateHUD"); eq(api.rooms[100]~=nil,true); eq(#api.deletedRooms,0)
end)

test("area inspection and membership use persisted state and normalized sorted IDs",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  local area=assert(map:ensureArea("Owned"))
  api.getAreaRooms1=function(id) eq(id,area); return {[0]="12",[1]=10,[2]=12,[3]=0,[4]="bad",extra=11} end
  local record=assert(map:areaRecord(area)); eq(record.id,area); eq(record.exists,true); eq(record.owned,true); eq(record.owner,"DragonsGateHUD")
  local rooms=assert(map:roomsInArea(area)); eq(#rooms,3); eq(rooms[1],10); eq(rooms[2],11); eq(rooms[3],12)

  local missing,e=map:areaRecord(999)
  eq(missing,nil); eq(e,"mapper area 999 does not exist")
end)

test("unowned ordinary and special inbound sources are reported without mutation",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"A"),{x=0,y=0,z=0})); assert(map:ensureRoom(descriptor(101,"A"),{x=1,y=0,z=0}))
  api.rooms[50]={name="Personal ordinary",area=9,user={},exits={n=100},stubs={}}
  api.rooms[40]={name="Personal special",area=9,user={},exits={},stubs={}}; api.special[40]={gate=101}
  api.rooms[100].exits.s=101; api.special[101]={back=100}
  local sources=assert(map:inboundSources({101,100,101}))
  eq(#sources,2); eq(sources[1],40); eq(sources[2],50)
  eq(api.rooms[50].exits.n,100); eq(api.special[40].gate,101); eq(api.rooms[100]~=nil,true); eq(api.rooms[101]~=nil,true)
end)

test("inbound inspection fails closed on every required mapper read",function()
  for _,name in ipairs({"getRooms","getRoomExits","getSpecialExits"}) do
    local api=fakeMapApi(); api.rooms[50]={name="Personal",area=9,user={},exits={n=100},stubs={}}; api.fail[name]=true
    local sources,e=Adapter.new(api):inboundSources({100})
    eq(sources,nil); eq(e,name.." rejected")
  end
end)

test("empty area deletion requires persisted ownership and current emptiness",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  api.areas["Personal"]=41; api.areaUser[41]={}; api.nextArea=42
  local ok,e=map:deleteEmptyOwnedArea(41)
  eq(ok,nil); eq(e,"mapper area 41 is not owned by DragonsGateHUD"); eq(api.areas["Personal"],41); eq(#api.deletedAreas,0)

  local owned=assert(map:ensureArea("Owned")); api.rooms[100]={area=owned,user={["dghud.owner"]="DragonsGateHUD"},exits={},stubs={}}
  ok,e=map:deleteEmptyOwnedArea(owned)
  eq(ok,nil); eq(e,"mapper area "..owned.." is not empty"); eq(api.areas["Dragons Gate - Owned"],owned); eq(#api.deletedAreas,0)
  api.rooms[100]=nil; eq(map:deleteEmptyOwnedArea(owned),true); eq(api.areas["Dragons Gate - Owned"],nil); eq(api.deletedAreas[1],owned)
end)

test("deleted map objects are invalidated from adapter caches",function()
  local map=Adapter.new(fakeMapApi()); map.areas.A=7; map.areas.B=8; map.createdAreas[7]=true; map.createdRooms[100]=true; map.createdRooms[101]=true
  eq(map:invalidateDeleted({101,100},7),true)
  eq(map.areas.A,nil); eq(map.areas.B,8); eq(map.createdAreas[7],nil); eq(map.createdRooms[100],nil); eq(map.createdRooms[101],nil)
end)

test("creates stubs one-way and confirmed reverse links",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(2),{})); assert(map:ensureStub(1,"n"))
  assert(map:connect(1,2,"e",false)); eq(api.rooms[2].exits.w,nil); assert(map:connect(1,2,"n",true)); eq(api.rooms[2].exits.s,1)
end)

test("reports stub forward and reverse failures",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(2),{}))
  api.fail.setExitStub=true; local ok,e=map:ensureStub(1,"n"); eq(ok,nil); eq(e,"setExitStub rejected")
  api.fail.setExitStub=nil; api.fail.setExit=true; ok,e=map:connect(1,2,"n",false); eq(ok,nil); eq(e,"setExit rejected")
  api.fail.setExit=nil; local native,count=api.setExit,0; api.setExit=function(...) count=count+1; if count==2 then return nil,"reverse rejected" end; return native(...) end
  ok,e=map:connect(1,2,"n",true); eq(ok,nil); eq(e,"reverse rejected")
end)

test("adds only an observed one-way special exit and is idempotent",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  assert(map:connectSpecial(100,900,"  GO Gate  ")); assert(Adapter.new(api):connectSpecial(100,900,"GO Gate"))
  eq(api.special[100]["GO Gate"],900); eq(api.special[900],nil); eq(api.specialAdds,1)
  eq(map:specialExitMatches(100,900,"GO Gate"),true)
  eq(map:specialExitMatches(100,900,"go gate"),false)
  eq(map:specialExitMatches(100,900,"leave gate"),false)
  eq(map:specialExitMatches(100,901,"go gate"),false)
end)

test("never replaces a different-destination special exit with the same command",function()
  for _,existing in ipairs({
    {destination=777,owner="PersonalMapper"},
    {destination=901,owner="DragonsGateHUD"},
  }) do
    local api=fakeMapApi(); local map=Adapter.new(api)
    assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
    api.rooms[existing.destination]={area=77,user={["dghud.owner"]=existing.owner},exits={},stubs={}}
    api.special[100]={["go gate"]=existing.destination}
    local ok,e=map:connectSpecial(100,900,"go gate")
    eq(ok,nil); eq(e,"special exit command already has a different destination")
    eq(api.special[100]["go gate"],existing.destination); eq(api.specialAdds,0)
  end
end)

test("an exact command and destination tuple remains idempotent",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  api.special[100]={["go gate"]=900}
  assert(map:connectSpecial(100,900,"go gate"))
  eq(api.special[100]["go gate"],900); eq(api.specialAdds,0)
end)

test("contains special-exit read and write failures without inventing an edge",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  api.fail.getSpecialExits=true; local ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"getSpecialExits rejected"); eq(api.specialAdds,0)
  api.fail.getSpecialExits=nil; api.fail.addSpecialExit=true; ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"addSpecialExit rejected"); eq(api.specialAdds,0); eq(next(api.special),nil)
end)

test("rejects invalid or unowned special-exit endpoints without mapper mutation",function()
  local api=fakeMapApi(); local map=Adapter.new(api)
  assert(map:ensureRoom(descriptor(100,"1"),{},"1")); assert(map:ensureRoom(descriptor(900,"1"),{},"special:900"))
  for _,values in ipairs({{0,900,"go gate"},{100,-1,"go gate"},{100,900,"   "}}) do
    local ok=map:connectSpecial(values[1],values[2],values[3]); eq(ok,nil)
  end
  api.rooms[900].user["dghud.owner"]="PersonalMapper"
  local ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"special exit endpoints are not owned by DragonsGateHUD"); eq(api.specialAdds,0); eq(next(api.special),nil)
  api.rooms[900].user["dghud.owner"]="DragonsGateHUD"; api.rooms[100].user["dghud.owner"]="PersonalMapper"
  ok,e=map:connectSpecial(100,900,"go gate")
  eq(ok,nil); eq(e,"special exit endpoints are not owned by DragonsGateHUD"); eq(api.specialAdds,0); eq(next(api.special),nil)
end)

test("reads zero-indexed occupancy route and view",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(10,"7"),{x=3,y=4,z=1})); local p=assert(map:coordinates(10)); eq(p.x,3); eq(p.y,4); eq(p.z,1)
  local occupied=assert(map:roomsAt("7",3,4,1)); eq(occupied[0],10); api.path={"n","e"}; eq(assert(map:route(10,20))[2],"e"); assert(map:setCurrent(10)); assert(map:center(10)); eq(api.refreshed,1)
end)

test("visual zoom direction hides Mudlet numeric inversion and clamps per area",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=20
  local map=Adapter.new(api)
  eq(map:currentZoom(100),20)
  eq(map:zoom(100,"larger",2.5,3,60),17.5); eq(api.zoom[7],17.5)
  eq(map:zoom(100,"smaller",2.5,3,60),20); eq(api.zoom[7],20)
  api.zoom[7]=3; eq(map:zoom(100,"larger",2.5,3,60),3)
end)

test("zoom enforces Mudlet's absolute minimum over a lower configured minimum",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=4
  eq(Adapter.new(api):zoom(100,"larger",2.5,1,60),3)
  eq(api.zoom[7],3)
end)

test("zoom rejects a configured maximum below Mudlet's absolute minimum",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=4
  local value,e=Adapter.new(api):zoom(100,"smaller",2.5,1,2.5)
  eq(value,nil); eq(e,"map zoom bounds are invalid"); eq(api.zoom[7],4)
end)

test("zoom rejects invalid ownership and preserves the previous value on API failures",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="DragonsGateHUD"}; api.zoom[7]=20
  local map=Adapter.new(api)
  api.rooms[100].user["dghud.owner"]="PersonalMapper"
  local value,e=map:currentZoom(100); eq(value,nil); eq(e,"room 100 is not owned by DragonsGateHUD")
  value,e=map:zoom(100,"larger",2.5,3,60); eq(value,nil); eq(e,"room 100 is not owned by DragonsGateHUD"); eq(api.zoom[7],20)
  api.rooms[100].user["dghud.owner"]="DragonsGateHUD"
  for _,name in ipairs({"getRoomArea","getMapZoom","setMapZoom"}) do
    api.fail[name]=true; value,e=map:zoom(100,"larger",2.5,3,60); eq(value,nil); eq(e,name.." rejected"); eq(api.zoom[7],20); api.fail[name]=nil
  end
  api.fail.updateMap=true; value,e=map:zoom(100,"larger",2.5,3,60); eq(value,nil); eq(e,"updateMap rejected"); eq(api.zoom[7],20)
end)

test("zoom refuses an unowned area even when the room is HUD owned",function()
  local api=fakeMapApi(); api.rooms[100]={area=7,user={["dghud.owner"]="DragonsGateHUD"}}; api.areaUser[7]={["dghud.owner"]="PersonalMapper"}; api.zoom[7]=20
  local map=Adapter.new(api)
  local value,e=map:currentZoom(100)
  eq(value,nil); eq(e,"mapper area 7 is not owned by DragonsGateHUD")
  value,e=map:zoom(100,"larger",2.5,3,60)
  eq(value,nil); eq(e,"mapper area 7 is not owned by DragonsGateHUD"); eq(api.zoom[7],20)
end)

test("reload resolves persisted owned area before checking occupied coordinates",function()
  local api=fakeMapApi(); local first=Adapter.new(api)
  assert(first:ensureRoom(descriptor(10,"Castle"),{x=0,y=1,z=0}))

  local reloaded=Adapter.new(api)
  local occupied=assert(reloaded:roomsAt("Castle",0,1,0))
  eq(occupied[0],10)
end)

test("occupancy reload rejects unowned areas and propagates area query failures",function()
  local collision=fakeMapApi(); collision.areas["Dragons Gate - Castle"]=41; collision.areaUser[41]={}
  local rooms,e=Adapter.new(collision):roomsAt("Castle",0,0,0)
  eq(rooms,nil); eq(e,"area Dragons Gate - Castle is not owned by DragonsGateHUD")

  local api=fakeMapApi(); assert(Adapter.new(api):ensureRoom(descriptor(10,"Castle"),{x=0,y=1,z=0}))
  api.fail.getRoomsByPosition=true
  rooms,e=Adapter.new(api):roomsAt("Castle",0,1,0)
  eq(rooms,nil); eq(e,"getRoomsByPosition rejected")
end)

test("contains mapper API exceptions",function()
  local api=fakeMapApi(); api.fail.getAreaTable="throw"; local ok,e=Adapter.new(api):ensureRoom(descriptor(1),{}); eq(ok,nil); assert(e:find("Mudlet mapper API getAreaTable failed",1,true))
end)

test("returns explicit errors for missing capabilities",function()
  local map=Adapter.new({roomExists=function() return false end}); local ok,e=map:ensureRoom(descriptor(1),{}); eq(ok,nil); eq(e,"Mudlet mapper API addRoom is unavailable")
  local route,routeError=map:route(1,2); eq(route,nil); eq(routeError,"Mudlet mapper API getPath is unavailable")
end)

test("production factory guards area APIs",function()
  local api=Adapter.mudletApi({}); local value,e=api.getAreaTable(); eq(value,nil); eq(e,"Mudlet mapper API getAreaTable is unavailable")
end)

test("production factory exposes private rollback wrappers",function()
  local deletedRoom,deletedArea
  local api=Adapter.mudletApi({deleteRoom=function(id) deletedRoom=id end,deleteArea=function(id) deletedArea=id end})
  assert(api.deleteRoom(51)); assert(api.deleteArea(6)); eq(deletedRoom,51); eq(deletedArea,6)
end)

test("production factory exposes guarded special-exit APIs",function()
  local added; local globals={}
  globals.addSpecialExit=function(from,to,command) added={from,to,command} end
  globals.getSpecialExits=function(from,listAll) return {[900]={["go gate"]="0"}},from,listAll end
  local api=Adapter.mudletApi(globals)
  assert(api.addSpecialExit(100,900,"go gate")); eq(added[1],100); eq(added[2],900); eq(added[3],"go gate")
  local exits,from,listAll=api.getSpecialExits(100,true); eq(exits[900]["go gate"],"0"); eq(from,100); eq(listAll,true)
end)

test("production factory exposes guarded cleanup inspection APIs",function()
  local globals={}
  globals.getAreaRooms1=function(area) return {[0]=100},area end
  globals.getRoomExits=function(room) return {n=101},room end
  local api=Adapter.mudletApi(globals)
  local rooms,area=api.getAreaRooms1(7); eq(rooms[0],100); eq(area,7)
  local exits,room=api.getRoomExits(100); eq(exits.n,101); eq(room,100)
  globals.getRoomExits=function() error("inspection exploded") end
  local value,e=api.getRoomExits(100); eq(value,nil); assert(e:find("Mudlet mapper API getRoomExits failed",1,true))
end)

test("production factory exposes guarded native zoom APIs",function()
  local zoom={[7]=20}; local globals={}
  globals.getMapZoom=function(area) return zoom[area] end
  globals.setMapZoom=function(value,area) zoom[area]=value end
  local api=Adapter.mudletApi(globals)
  eq(api.getMapZoom(7),20); assert(api.setMapZoom(17.5,7)); eq(zoom[7],17.5)
end)

test("production route isolates speedWalkDir",function()
  local globals={speedWalkDir={"old"}}; globals.getPath=function() globals.speedWalkDir={"north","east"}; return true end
  local steps=assert(Adapter.new(Adapter.mudletApi(globals)):route(1,3)); eq(steps[1],"north"); globals.speedWalkDir[1]="changed"; eq(steps[1],"north")
end)
