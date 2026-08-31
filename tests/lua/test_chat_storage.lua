local Storage=require("chat_storage")

local function fakeStorageApi()
  local api={directories={},appends={},files={}}
  function api.mkdir(path) api.directories[#api.directories+1]=path; return true end
  function api.append(path,text)
    api.lastPath=path
    api.appends[#api.appends+1]={path=path,text=text}
    api.files[path]=(api.files[path] or "")..text
    return true
  end
  function api.list(path) return api.listed or {} end
  function api.read(path) return api.files[path] end
  function api.encode(entry) return entry.message end
  function api.decode(line) return api.decoded and api.decoded[line] or nil,"invalid json" end
  return api
end

local function fakeStorageApiWithLines(lines)
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl"}
  api.files["/chat/dace_alterac/2026-08-30.jsonl"]=table.concat(lines,"\n").."\n"
  api.decoded={['{"category":"ESP","message":"valid"}']={category="ESP",message="valid"}}
  return api
end

test("sanitizes character paths and appends dated JSONL",function()
  local api=fakeStorageApi()
  local storage=Storage.new(api,"/profile/DragonsGateHUD/chat",1000)
  assert(storage:append({timestamp="2026-08-31T13:00:00-04:00",character="Dace/Alterac",category="ROOM",message="hello"}))
  eq(api.lastPath,"/profile/DragonsGateHUD/chat/dace_alterac/2026-08-31.jsonl")
  eq(api.appends[1].text,"hello\n")
  eq(Storage.safeCharacter("../../Dace"),"dace")
  eq(Storage.safeCharacter("/absolute"),"absolute")
  eq(Storage.safeCharacter(nil),"unknown")
end)

test("skips malformed JSONL while loading later entries",function()
  local api=fakeStorageApiWithLines({'not json','{"category":"ESP","message":"valid"}'})
  local entries=Storage.new(api,"/chat",1000):loadRecent("Dace Alterac")
  eq(#entries,1)
  eq(entries[1].message,"valid")
end)

test("reports malformed JSONL once without interrupting recovery",function()
  local api=fakeStorageApiWithLines({'not json','still not json','{"category":"ESP","message":"valid"}'})
  api.reports=0
  api.report=function() api.reports=api.reports+1 end
  local entries=Storage.new(api,"/chat",1000):loadRecent("Dace Alterac")
  eq(#entries,1)
  eq(api.reports,1)
end)

test("loads newest dated files first without deleting older logs",function()
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl","2026-08-31.jsonl","notes.txt"}
  api.files["/chat/dace/2026-08-31.jsonl"]="newest\n"
  api.files["/chat/dace/2026-08-30.jsonl"]="older\n"
  api.decoded={newest={message="newest"},older={message="older"}}
  local storage=Storage.new(api,"/chat",1)
  local entries=storage:loadRecent("Dace")
  eq(#entries,1)
  eq(entries[1].message,"newest")
  eq(#api.appends,0)
end)

test("Mudlet storage factory confines file access beneath its chat root",function()
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  local made={}
  lfs={mkdir=function(directory) made[#made+1]=directory; return true end,dir=function() return function() return nil end end}
  io={open=function() error("unexpected file access") end}
  yajl={to_string=function() return "{}" end,to_value=function() return {} end}
  local api=Storage.mudletApi("/profile")
  assert(api.mkdir("/profile/DragonsGateHUD/chat/dace"))
  eq(made[1],"/profile/DragonsGateHUD")
  eq(made[2],"/profile/DragonsGateHUD/chat")
  eq(made[3],"/profile/DragonsGateHUD/chat/dace")
  eq(api.mkdir("/tmp/escape"),nil)
  eq(api.append("/tmp/escape/log.jsonl","bad"),nil)
  lfs,io,yajl=originalLfs,originalIo,originalYajl
end)

test("Mudlet storage factory accepts existing owned directories",function()
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  lfs={mkdir=function() return nil,"File exists" end,attributes=function() return "directory" end,dir=function() return function() return nil end end}
  io={open=function() error("unexpected file access") end}
  yajl={to_string=function() return "{}" end,to_value=function() return {} end}
  local api=Storage.mudletApi("/profile")
  eq(api.mkdir("/profile/DragonsGateHUD/chat/dace"),true)
  lfs,io,yajl=originalLfs,originalIo,originalYajl
end)
