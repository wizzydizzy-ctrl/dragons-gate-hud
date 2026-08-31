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

test("retains successive append-only entries in one dated log",function()
  local api=fakeStorageApi()
  local storage=Storage.new(api,"/chat",1000)
  assert(storage:append({timestamp="2026-08-31T13:00:00-04:00",character="Dace",message="first"}))
  assert(storage:append({timestamp="2026-08-31T13:01:00-04:00",character="Dace",message="second"}))
  eq(api.files["/chat/dace/2026-08-31.jsonl"],"first\nsecond\n")
end)

test("contains mkdir encode and append exceptions",function()
  for _,name in ipairs({"mkdir","encode","append"}) do
    local api=fakeStorageApi()
    api[name]=function() error(name.." failure") end
    local protected,result,err=pcall(function()
      return Storage.new(api,"/chat",1000):append({timestamp="2026-08-31T13:00:00-04:00",character="Dace",message="hello"})
    end)
    eq(protected,true)
    eq(result,nil)
    eq(type(err),"string")
  end
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

test("returns the newest N entries in chronological order across dated files",function()
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl","2026-08-31.jsonl"}
  api.files["/chat/dace/2026-08-30.jsonl"]="old-one\nold-two\n"
  api.files["/chat/dace/2026-08-31.jsonl"]="new-one\nnew-two\nnew-three\n"
  api.decoded={
    ["old-one"]={message="old-one"},["old-two"]={message="old-two"},
    ["new-one"]={message="new-one"},["new-two"]={message="new-two"},["new-three"]={message="new-three"},
  }
  local entries=Storage.new(api,"/chat",4):loadRecent("Dace")
  eq(#entries,4)
  eq(entries[1].message,"old-two")
  eq(entries[2].message,"new-one")
  eq(entries[3].message,"new-two")
  eq(entries[4].message,"new-three")
end)

test("contains list errors and recovers after a read error",function()
  local unavailable=fakeStorageApi()
  unavailable.list=function() error("directory unavailable") end
  local protected,entries=pcall(function() return Storage.new(unavailable,"/chat",1000):loadRecent("Dace") end)
  eq(protected,true)
  eq(#entries,0)
  local api=fakeStorageApi()
  api.listed={"2026-08-30.jsonl","2026-08-31.jsonl"}
  api.read=function(path)
    if path=="/chat/dace/2026-08-31.jsonl" then error("read failure") end
    return "older\n"
  end
  api.decoded={older={message="older"}}
  protected,entries=pcall(function() return Storage.new(api,"/chat",1000):loadRecent("Dace") end)
  eq(protected,true)
  eq(#entries,1)
  eq(entries[1].message,"older")
end)

test("exposes the latest internal storage failure for diagnostics",function()
  local api=fakeStorageApi()
  api.list=function() error("directory unavailable") end
  local storage=Storage.new(api,"/chat",1000)
  eq(#storage:loadRecent("Dace"),0)
  eq(storage:lastError():find("directory unavailable",1,true)~=nil,true)
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
  eq(api.append("/profile/DragonsGateHUD/chat/dace/../escape.jsonl","bad"),nil)
  lfs,io,yajl=originalLfs,originalIo,originalYajl
end)

test("Mudlet storage factory appends valid in-root JSONL paths",function()
  local originalLfs,originalIo,originalYajl=lfs,io,yajl
  local opened={}
  lfs={mkdir=function() return true end,dir=function() return function() return nil end end}
  io={open=function(pathname,mode)
    opened.path,opened.mode=pathname,mode
    return {write=function(_,text) opened.text=text; return true end,close=function() return true end}
  end}
  yajl={to_string=function() return "{}" end,to_value=function() return {} end}
  local api=Storage.mudletApi("/profile")
  eq(api.append("/profile/DragonsGateHUD/chat/dace/2026-08-31.jsonl","entry\n"),true)
  eq(opened.path,"/profile/DragonsGateHUD/chat/dace/2026-08-31.jsonl")
  eq(opened.mode,"ab")
  eq(opened.text,"entry\n")
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
