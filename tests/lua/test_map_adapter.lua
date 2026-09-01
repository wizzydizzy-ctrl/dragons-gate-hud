local Adapter=require("map_adapter")

local function fakeMapApi(seed)
  local api={rooms=seed or {},areas={},areaUser={},nextArea=1,fail={},path=nil,refreshed=0,deletedRooms={},deletedAreas={}}
  local function gate(name)
    if api.fail[name]=="throw" then error(name.." exploded") end
    if api.fail[name] then return nil,name.." rejected" end
    return true
  end
  function api.roomExists(id) local ok,e=gate("roomExists"); if not ok then return nil,e end; return api.rooms[id]~=nil end
  function api.addRoom(id) local ok,e=gate("addRoom"); if not ok then return nil,e end; api.rooms[id]={user={},exits={},stubs={}}; return true end
  function api.deleteRoom(id) local ok,e=gate("deleteRoom"); if not ok then return nil,e end; api.rooms[id]=nil; api.deletedRooms[#api.deletedRooms+1]=id; return true end
  function api.getAreaTable() local ok,e=gate("getAreaTable"); if not ok then return nil,e end; local t={}; for n,id in pairs(api.areas) do t[n]=id end; return t end
  function api.addAreaName(name) local ok,e=gate("addAreaName"); if not ok then return nil,e end; if api.areas[name] then return nil,"area already exists" end; local id=api.nextArea; api.nextArea=id+1; api.areas[name]=id; api.areaUser[id]={}; return id end
  function api.deleteArea(id) local ok,e=gate("deleteArea"); if not ok then return nil,e end; for name,areaID in pairs(api.areas) do if areaID==id then api.areas[name]=nil end end; api.areaUser[id]=nil; api.deletedAreas[#api.deletedAreas+1]=id; return true end
  function api.setAreaUserData(id,k,v) local ok,e=gate("setAreaUserData"); if not ok then return nil,e end; api.areaUser[id]=api.areaUser[id] or {}; api.areaUser[id][k]=v; return true end
  function api.getAreaUserData(id,k) local ok,e=gate("getAreaUserData"); if not ok then return nil,e end; return api.areaUser[id] and api.areaUser[id][k] end
  function api.setRoomArea(id,v) local ok,e=gate("setRoomArea"); if not ok then return nil,e end; api.rooms[id].area=v; return true end
  function api.setRoomName(id,v) local ok,e=gate("setRoomName"); if not ok then return nil,e end; api.rooms[id].name=v; return true end
  function api.setRoomCoordinates(id,x,y,z) local ok,e=gate("setRoomCoordinates"); if not ok then return nil,e end; local r=api.rooms[id]; r.x=x;r.y=y;r.z=z; return true end
  function api.setRoomUserData(id,k,v) local ok,e=gate("setRoomUserData"); if not ok then return nil,e end; api.rooms[id].user[k]=v; return true end
  function api.getRoomUserData(id,k) local ok,e=gate("getRoomUserData"); if not ok then return nil,e end; return api.rooms[id] and api.rooms[id].user[k] end
  function api.setExitStub(id,d) local ok,e=gate("setExitStub"); if not ok then return nil,e end; api.rooms[id].stubs[d]=true; return true end
  function api.setExit(id,to,d) local ok,e=gate("setExit"); if not ok then return nil,e end; api.rooms[id].exits[d]=to; return true end
  function api.getRoomCoordinates(id) local ok,e=gate("getRoomCoordinates"); if not ok then return nil,e end; local r=api.rooms[id]; return r and r.x,r and r.y,r and r.z end
  function api.getRoomsByPosition(area,x,y,z) local ok,e=gate("getRoomsByPosition"); if not ok then return nil,e end; local out,i={},0; for id,r in pairs(api.rooms) do if r.area==area and r.x==x and r.y==y and r.z==z then out[i]=id;i=i+1 end end; return out end
  function api.centerview(id) local ok,e=gate("centerview"); if not ok then return nil,e end; api.centered=id; return true end
  function api.getPath(a,b) local ok,e=gate("getPath"); if not ok then return nil,e end; return api.path or {a.."-"..b} end
  function api.updateMap() local ok,e=gate("updateMap"); if not ok then return nil,e end; api.refreshed=api.refreshed+1; return true end
  return api
end

local function descriptor(id,area,name)
  return {id=id,name=name or ("Room "..id),area_key=area or "A",environment="Plain",flags={"indoor"},exits={}}
end

test("creates a fully tagged room and finalizes readiness last",function()
  local api=fakeMapApi(); local calls={}; local native=api.setRoomUserData
  api.setRoomUserData=function(id,k,v) calls[#calls+1]=k; return native(id,k,v) end
  assert(Adapter.new(api):ensureRoom(descriptor(176,"1","Training square."),{x=0,y=1,z=2}))
  local r=api.rooms[176]; eq(r.name,"Training square."); eq(r.user["dghud.owner"],"DragonsGateHUD"); eq(calls[#calls],"dghud.state"); eq(r.user["dghud.state"],"ready")
  eq(r.user["dghud.mapper_schema"],"1"); eq(r.user["dghud.environment"],"Plain"); eq(r.user["dghud.flags"],"indoor")
  eq(r.x,0); eq(r.y,1); eq(r.z,2); eq(api.areaUser[r.area]["dghud.owner"],"DragonsGateHUD")
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

test("refuses an unowned canonical room collision without mutation",function()
  local original={name="Personal",user={},x=8,exits={},stubs={}}; local api=fakeMapApi({[176]=original})
  local ok,e=Adapter.new(api):ensureRoom(descriptor(176),{x=0}); eq(ok,nil); eq(e,"room 176 is not owned by DragonsGateHUD"); eq(original.name,"Personal"); eq(original.x,8)
end)

test("updates owned rooms and retains ownership on failure",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(1),{})); assert(map:ensureRoom(descriptor(1,"A","Changed"),{x=2,y=3,z=0})); eq(api.rooms[1].name,"Changed")
  api.fail.setRoomName=true; local ok,e=map:ensureRoom(descriptor(1,"A","Nope"),{}); eq(ok,nil); eq(e,"setRoomName rejected"); eq(api.rooms[1].user["dghud.owner"],"DragonsGateHUD")
end)

test("post-create room mutation failures remain safely retryable",function()
  for _,name in ipairs({"setRoomArea","setRoomName","setRoomCoordinates"}) do
    local api=fakeMapApi(); local map=Adapter.new(api); api.fail[name]=true; local ok,e=map:ensureRoom(descriptor(20),{})
    eq(ok,nil); eq(e,name.." rejected"); eq(api.rooms[20].user["dghud.owner"],"DragonsGateHUD"); eq(api.rooms[20].user["dghud.state"],"provisional")
    api.fail[name]=nil; assert(map:ensureRoom(descriptor(20),{})); eq(api.rooms[20].user["dghud.state"],"ready")
  end
  for failureCall=2,6 do
    local api=fakeMapApi(); local map=Adapter.new(api); local native=api.setRoomUserData; local calls=0
    api.setRoomUserData=function(...) calls=calls+1; if calls==failureCall then return nil,"room metadata rejected" end; return native(...) end
    local ok,e=map:ensureRoom(descriptor(21),{}); eq(ok,nil); eq(e,"room metadata rejected"); api.setRoomUserData=native
    assert(map:ensureRoom(descriptor(21),{})); eq(api.rooms[21].user["dghud.owner"],"DragonsGateHUD"); eq(api.rooms[21].user["dghud.state"],"ready")
  end
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

test("reads zero-indexed occupancy route and view",function()
  local api=fakeMapApi(); local map=Adapter.new(api); assert(map:ensureRoom(descriptor(10,"7"),{x=3,y=4,z=1})); local p=assert(map:coordinates(10)); eq(p.x,3); eq(p.y,4); eq(p.z,1)
  local occupied=assert(map:roomsAt("7",3,4,1)); eq(occupied[0],10); api.path={"n","e"}; eq(assert(map:route(10,20))[2],"e"); assert(map:setCurrent(10)); assert(map:center(10)); eq(api.refreshed,1)
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

test("production route isolates speedWalkDir",function()
  local globals={speedWalkDir={"old"}}; globals.getPath=function() globals.speedWalkDir={"north","east"}; return true end
  local steps=assert(Adapter.new(Adapter.mudletApi(globals)):route(1,3)); eq(steps[1],"north"); globals.speedWalkDir[1]="changed"; eq(steps[1],"north")
end)
