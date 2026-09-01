local Adapter=require("map_adapter")

local function fakeMapApi(seed)
  local api={rooms=seed or {},areas={},areaUser={},nextArea=1,fail={},path=nil,refreshed=0}
  local function gate(name)
    if api.fail[name]=="throw" then error(name.." exploded") end
    if api.fail[name] then return nil,name.." rejected" end
    return true
  end
  function api.roomExists(id) local ok,e=gate("roomExists"); if not ok then return nil,e end; return api.rooms[id]~=nil end
  function api.addRoom(id) local ok,e=gate("addRoom"); if not ok then return nil,e end; api.rooms[id]={user={},exits={},stubs={}}; return true end
  function api.getAreaTable() local ok,e=gate("getAreaTable"); if not ok then return nil,e end; local t={}; for n,id in pairs(api.areas) do t[n]=id end; return t end
  function api.addAreaName(name) local ok,e=gate("addAreaName"); if not ok then return nil,e end; if api.areas[name] then return nil,"area already exists" end; local id=api.nextArea; api.nextArea=id+1; api.areas[name]=id; api.areaUser[id]={}; return id end
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

test("creates a fully tagged room and commits ownership last",function()
  local api=fakeMapApi(); local calls={}; local native=api.setRoomUserData
  api.setRoomUserData=function(id,k,v) calls[#calls+1]=k; return native(id,k,v) end
  assert(Adapter.new(api):ensureRoom(descriptor(176,"1","Training square."),{x=0,y=1,z=2}))
  local r=api.rooms[176]; eq(r.name,"Training square."); eq(r.user["dghud.owner"],"DragonsGateHUD"); eq(calls[#calls],"dghud.owner")
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

test("mutation failures never commit ownership on a new room",function()
  for _,name in ipairs({"setRoomArea","setRoomName","setRoomCoordinates","setRoomUserData"}) do
    local api=fakeMapApi(); api.fail[name]=true; local ok,e=Adapter.new(api):ensureRoom(descriptor(20),{})
    eq(ok,nil); eq(e,name.." rejected"); eq(api.rooms[20] and api.rooms[20].user["dghud.owner"],nil)
  end
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

test("production route isolates speedWalkDir",function()
  local globals={speedWalkDir={"old"}}; globals.getPath=function() globals.speedWalkDir={"north","east"}; return true end
  local steps=assert(Adapter.new(Adapter.mudletApi(globals)):route(1,3)); eq(steps[1],"north"); globals.speedWalkDir[1]="changed"; eq(steps[1],"north")
end)
