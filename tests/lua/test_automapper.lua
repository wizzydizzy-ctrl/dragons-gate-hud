local Automapper=require("automapper")
local Model=require("mapper_model")

local function fakeMap()
  local map={rooms={},roomByID={},ensureRequests={},stubs={},links={},special={},current=nil,coordinatesByID={}}
  function map:ensureRoom(room,coordinates,partition)
    local record=self.roomByID[room.id]
    self.ensureRequests[#self.ensureRequests+1]={id=room.id,coordinates=coordinates,partition=partition}
    if record and not record.owned then return nil,"room "..room.id.." is not owned by DragonsGateHUD" end
    if self.ensureError then return nil,self.ensureError end
    if not record then
      record={room=room,coordinates=coordinates,partition=partition or room.area_key,game_area=room.area_key,owned=true}
      self.roomByID[room.id]=record; self.rooms[#self.rooms+1]=record; self.coordinatesByID[room.id]=coordinates
    else
      record.room=room
    end
    return true
  end
  function map:ensureStub(id,direction) self.stubs[#self.stubs+1]={id=id,direction=direction}; return true end
  function map:connect(from,to,direction,reverse) self.links[#self.links+1]={from=from,to=to,direction=direction,reverse=reverse}; return true end
  function map:connectSpecial(from,to,command)
    if self.specialError then return nil,self.specialError end
    self.special[#self.special+1]={from=from,to=to,command=command}; return true
  end
  function map:setCurrent(id) self.current=id; return true end
  function map:coordinates(id) return self.coordinatesByID[id] end
  function map:roomRecord(id)
    local record=self.roomByID[id]
    if not record then return {exists=false,owned=false} end
    return {exists=true,owned=record.owned,partition=record.partition,game_area=record.game_area,coordinates=record.coordinates}
  end
  function map:effectivePartition(id) local record=self.roomByID[id]; return record and record.partition end
  function map:roomsAt() return {} end
  return map
end

local function room(id,name,area,exits)
  return {num=id,name=name or ("Room "..id),area=area or 1,exits=exits or {}}
end

test("connects only the observed direction and confirmed advertised reverse",function()
  local map=fakeMap(); local statuses={}; local mapper=Automapper.new(Model,map,function(kind) statuses[#statuses+1]=kind end)
  assert(mapper:onRoom({num=100,name="A",area=1,exits={"north"}}))
  mapper:onOutgoing("north")
  assert(mapper:onRoom({num=101,name="B",area=1,exits={"south"}}))
  eq(#map.links,1); eq(map.links[1].from,100); eq(map.links[1].to,101); eq(map.links[1].direction,"n"); eq(map.links[1].reverse,true)
  eq(statuses[#statuses],"mapped")
end)

test("does not confirm reverse unless destination advertises it",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom({num=100,name="A",area=1,exits={"east"}})); mapper:onOutgoing("e")
  assert(mapper:onRoom({num=101,name="B",area=1,exits={"north"}}))
  eq(map.links[1].direction,"e"); eq(map.links[1].reverse,false)
end)

test("does not invent a link after a teleport",function()
  local map=fakeMap(); local statuses={}; local mapper=Automapper.new(Model,map,function(kind) statuses[#statuses+1]=kind end)
  assert(mapper:onRoom({num=100,name="A",area=1,exits={"north"}})); assert(mapper:onRoom({num=900,name="Elsewhere",area=2,exits={}}))
  eq(#map.links,0); eq(map.current,900); eq(statuses[#statuses],"teleport")
end)

test("special movement creates a destination-rooted submap and exact one-way edge",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"Outside",1,{"north"})))
  assert(mapper:onSpecialTransition({from=100,to=900,command="  Go Door  ",kind="special"}))
  assert(mapper:onRoom(room(900,"Inside",1,{"south"})))
  eq(map.roomByID[900].partition,"special:900")
  eq(map.coordinatesByID[900].x,0); eq(map.coordinatesByID[900].y,0); eq(map.coordinatesByID[900].z,0)
  eq(#map.special,1); eq(map.special[1].from,100); eq(map.special[1].to,900); eq(map.special[1].command,"Go Door")
end)

test("reverse special edge appears only after its exact return command is observed",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"Outside",1,{"north"})))
  assert(mapper:onSpecialTransition({from=100,to=900,command="go door",kind="special"})); assert(mapper:onRoom(room(900,"Inside",1,{"south"})))
  eq(#map.special,1)
  assert(mapper:onSpecialTransition({from=900,to=100,command="leave door",kind="special"})); assert(mapper:onRoom(room(100,"Outside",1,{"north"})))
  eq(#map.special,2); eq(map.special[2].from,900); eq(map.special[2].to,100); eq(map.special[2].command,"leave door")
end)

test("special entry reuses an existing canonical destination without changing its partition or coordinates",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(900,"Known",7)))
  map.roomByID[900].partition="persisted:900"; map.roomByID[900].coordinates={x=4,y=5,z=1}; map.coordinatesByID[900]=map.roomByID[900].coordinates
  assert(mapper:onRoom(room(100,"Outside",1)))
  assert(mapper:onSpecialTransition({from=100,to=900,command="enter known door",kind="special"})); assert(mapper:onRoom(room(900,"Known",7)))
  local request=map.ensureRequests[#map.ensureRequests]
  eq(request.partition,"persisted:900"); eq(request.coordinates.x,4); eq(request.coordinates.y,5); eq(request.coordinates.z,1)
  eq(map.roomByID[900].partition,"persisted:900"); eq(#map.rooms,2); eq(#map.special,1)
end)

test("directional exploration inherits a special partition until the game area changes",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"Outside",1,{"north"})))
  assert(mapper:onSpecialTransition({from=100,to=900,command="go gate",kind="special"})); assert(mapper:onRoom(room(900,"Inside",1,{"north"})))
  mapper:onOutgoing("north"); assert(mapper:onRoom(room(901,"Hall",1,{"south","north"})))
  eq(map.roomByID[901].partition,"special:900"); eq(map.coordinatesByID[901].y,1)
  mapper:onOutgoing("north"); assert(mapper:onRoom(room(902,"Elsewhere",2,{"south"})))
  eq(map.roomByID[902].partition,"2"); eq(map.coordinatesByID[902].y,2)
end)

test("multiple origins reuse one destination-rooted submap without duplicating the room",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"West",1))); assert(mapper:onSpecialTransition({from=100,to=900,command="go west gate",kind="special"})); assert(mapper:onRoom(room(900,"Inside",1)))
  assert(mapper:onRoom(room(200,"East",1))); assert(mapper:onSpecialTransition({from=200,to=900,command="go east gate",kind="special"})); assert(mapper:onRoom(room(900,"Inside",1)))
  eq(#map.rooms,3); eq(map.roomByID[900].partition,"special:900"); eq(#map.special,2)
  eq(map.special[1].command,"go west gate"); eq(map.special[2].command,"go east gate")
end)

test("same-room refresh preserves a pending special transition without creating an edge",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"Outside",1)))
  assert(mapper:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  assert(mapper:onRoom(room(100,"Outside refreshed",1)))
  eq(mapper.pending.from,100); eq(mapper.pending.to,900); eq(#map.special,0)
  assert(mapper:onRoom(room(900,"Inside",1)))
  eq(mapper.pending,nil); eq(#map.special,1); eq(map.special[1].command,"go gate")
end)

test("unowned special destination collision clears pending without moving or linking it",function()
  local map=fakeMap(); local personal={room=room(900,"Personal",1),coordinates={x=8,y=7,z=6},partition="personal",game_area="1",owned=false}
  map.roomByID[900]=personal; map.coordinatesByID[900]=personal.coordinates
  local mapper=Automapper.new(Model,map,function() end); assert(mapper:onRoom(room(100,"Outside",1)))
  assert(mapper:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  local ok,e=mapper:onRoom(room(900,"Collision",1)); eq(ok,nil); assert(e:find("not owned",1,true))
  eq(mapper.pending,nil); eq(map.current,100); eq(#map.special,0)
  eq(personal.partition,"personal"); eq(personal.coordinates.x,8); eq(personal.coordinates.y,7); eq(personal.coordinates.z,6)
end)

test("failed special-exit write clears pending and never records the edge",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end); assert(mapper:onRoom(room(100,"Outside",1)))
  map.specialError="addSpecialExit rejected"
  assert(mapper:onSpecialTransition({from=100,to=900,command="go gate",kind="special"}))
  local ok,e=mapper:onRoom(room(900,"Inside",1)); eq(ok,nil); eq(e,"addSpecialExit rejected")
  eq(mapper.pending,nil); eq(map.current,100); eq(#map.special,0); eq(map.roomByID[900].partition,"special:900")
end)

test("tracks exact standard directions and clears pending on exceptional movement",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom({num=100,name="A",area=1,exits={"north"}}))
  mapper:onOutgoing("say north"); eq(mapper.pending,nil)
  mapper:onOutgoing("north"); eq(mapper.pending.direction,"n")
  mapper:onWrongDirection("north"); eq(mapper.pending,nil)
  mapper:onOutgoing("n"); mapper:onOutgoing("go portal"); eq(mapper.pending,nil)
  mapper:onOutgoing("n"); mapper:onDisconnect(); eq(mapper.pending,nil)
  mapper:onOutgoing("n"); mapper:shutdown(); eq(mapper.pending,nil); eq(mapper:currentRoom(),nil)
end)

test("normalizes rooms, creates standard exit stubs, and places observed destinations",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom({num=100,name="A",area=1,exits={"north","portal","up"}}))
  eq(#map.stubs,2); eq(map.stubs[1].direction,"n"); eq(map.stubs[2].direction,"up")
  mapper:onOutgoing("n"); assert(mapper:onRoom({num=101,name="B",area=1,exits={"south"}}))
  eq(map.coordinatesByID[101].x,0); eq(map.coordinatesByID[101].y,1); eq(map.coordinatesByID[101].z,0)
end)

test("reports invalid rooms and ownership conflicts without further map mutation",function()
  local map=fakeMap(); local statuses={}; local mapper=Automapper.new(Model,map,function(kind,message) statuses[#statuses+1]={kind,message} end)
  local ok=mapper:onRoom({num="bad"}); eq(ok,nil); eq(statuses[#statuses][1],"invalid_room"); eq(#map.rooms,0)
  function map:ensureRoom() return nil,"room 77 is not owned by DragonsGateHUD" end
  ok=mapper:onRoom({num=77,name="Personal",area=1,exits={"n"}}); eq(ok,nil); eq(statuses[#statuses][1],"ownership_conflict"); eq(#map.stubs,0); eq(#map.links,0)
end)

test("preserves established coordinates on repeats reload-style hydration and revisits",function()
  local map=fakeMap(); map.coordinatesByID[100]={x=7,y=8,z=0}; map.coordinatesByID[101]={x=7,y=9,z=0}
  local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"A",1,{"north"}))); eq(map.coordinatesByID[100].x,7); eq(map.coordinatesByID[100].y,8)
  assert(mapper:onRoom(room(100,"A again",1,{"north"}))); eq(map.coordinatesByID[100].x,7); eq(map.coordinatesByID[100].y,8)
  mapper:onOutgoing("north"); assert(mapper:onRoom(room(101,"B",1,{"south"})))
  mapper:onOutgoing("south"); assert(mapper:onRoom(room(100,"A",1,{"north"})))
  eq(map.coordinatesByID[100].x,7); eq(map.coordinatesByID[100].y,8)
end)

test("same-origin updates retain pending movement until actual arrival",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"A",1,{"north"}))); mapper:onOutgoing("north")
  assert(mapper:onRoom(room(100,"A refreshed",1,{"north"})))
  eq(mapper.pending.from,100); eq(mapper.pending.direction,"n"); eq(map.coordinatesByID[100].y,0)
  assert(mapper:onRoom(room(101,"B",1,{"south"}))); eq(#map.links,1); eq(map.links[1].to,101)
end)

test("same-origin mapper mutation failures do not discard pending movement",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"A",1,{"north"}))); mapper:onOutgoing("north")
  function map:ensureRoom() return nil,"temporary mapper failure" end
  local ok=mapper:onRoom(room(100,"A refreshed",1,{"north"})); eq(ok,nil)
  eq(mapper.pending.from,100); eq(mapper.pending.direction,"n")
end)

test("conflicting directional movement replaces pending movement",function()
  local map=fakeMap(); local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"A",1,{"north","east"}))); mapper:onOutgoing("north"); mapper:onOutgoing("east")
  eq(mapper.pending.from,100); eq(mapper.pending.direction,"e")
end)

test("new teleported rooms receive deterministic nearest free coordinates",function()
  local map=fakeMap(); map.occupied={ ["0,0,0"]={100}, ["0,1,0"]={200} }
  function map:roomsAt(_,x,y,z) return self.occupied[x..","..y..","..z] or {} end
  local mapper=Automapper.new(Model,map,function() end)
  assert(mapper:onRoom(room(100,"A",1))); assert(mapper:onRoom(room(200,"B",1)))
  local placed=map.coordinatesByID[200]; eq(not (placed.x==0 and placed.y==0 and placed.z==0),true)
  local map2=fakeMap(); map2.occupied=map.occupied; map2.roomsAt=map.roomsAt
  local mapper2=Automapper.new(Model,map2,function() end); assert(mapper2:onRoom(room(200,"B",1)))
  eq(map2.coordinatesByID[200].x,placed.x); eq(map2.coordinatesByID[200].y,placed.y); eq(map2.coordinatesByID[200].z,placed.z)
end)

test("occupancy excludes the destination itself and propagates lookup failures",function()
  local map=fakeMap(); map.coordinatesByID[100]={x=0,y=0,z=0}; map.coordinatesByID[101]={x=0,y=1,z=0}
  function map:roomsAt(_,x,y,z) if y==1 then return {[0]=101} end return {} end
  local mapper=Automapper.new(Model,map,function() end); assert(mapper:onRoom(room(100,"A",1,{"north"}))); mapper:onOutgoing("north")
  assert(mapper:onRoom(room(101,"B",1,{"south"}))); eq(map.coordinatesByID[101].y,1)

  local failing=fakeMap(); function failing:roomsAt() return nil,"occupancy unavailable" end
  local errors={}; local broken=Automapper.new(Model,failing,function(kind,message) errors[#errors+1]={kind,message} end)
  local ok,err=broken:onRoom(room(300,"C",1)); eq(ok,nil); eq(err,"occupancy unavailable"); eq(#failing.rooms,0); eq(errors[#errors][1],"invalid_room")
end)
