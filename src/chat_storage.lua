local Storage={}
Storage.__index=Storage

local function trim(value)
  return tostring(value or ""):match("^%s*(.-)%s*$")
end

function Storage.safeCharacter(name)
  local safe=trim(name):lower():gsub("[^a-z0-9_-]+","_"):gsub("_+","_"):gsub("^_+",""):gsub("_+$","")
  return safe~="" and safe or "unknown"
end

local function path(base,name)
  return base.."/"..name
end

local function date(timestamp)
  return tostring(timestamp or ""):match("^(%d%d%d%d%-%d%d%-%d%d)T") or os.date("%Y-%m-%d")
end

local function datedFiles(files)
  local result={}
  for _,file in ipairs(files or {}) do
    if type(file)=="string" and file:match("^%d%d%d%d%-%d%d%-%d%d%.jsonl$") then result[#result+1]=file end
  end
  table.sort(result,function(a,b) return a>b end)
  return result
end

local function lines(text)
  local result={}
  for line in (tostring(text or "").."\n"):gmatch("(.-)\n") do
    if line~="" then result[#result+1]=line end
  end
  return result
end

function Storage.new(api,basePath,visibleLimit)
  assert(type(api)=="table","storage api is required")
  return setmetatable({api=api,basePath=tostring(basePath or ""),visibleLimit=math.max(1,math.floor(tonumber(visibleLimit) or 1000)),reportedMalformed=false},Storage)
end

function Storage:append(entry)
  if type(entry)~="table" then return nil,"chat entry is required" end
  local character=Storage.safeCharacter(entry.character)
  local directory=path(self.basePath,character)
  local ok,err=self.api.mkdir(self.basePath)
  if not ok then return nil,err or "could not create chat storage" end
  ok,err=self.api.mkdir(directory)
  if not ok then return nil,err or "could not create character storage" end
  local encoded=self.api.encode(entry)
  if type(encoded)~="string" then return nil,"could not encode chat entry" end
  return self.api.append(path(directory,date(entry.timestamp)..".jsonl"),encoded.."\n")
end

function Storage:reportMalformed()
  if self.reportedMalformed then return end
  self.reportedMalformed=true
  if type(self.api.report)=="function" then pcall(self.api.report,"skipped malformed chat log entry") end
end

function Storage:loadRecent(character)
  local directory=path(self.basePath,Storage.safeCharacter(character))
  local files=self.api.list(directory)
  local newestFirst={}
  for _,file in ipairs(datedFiles(files)) do
    local content=self.api.read(path(directory,file))
    local fileLines=lines(content)
    for index=#fileLines,1,-1 do
      local ok,entry=pcall(self.api.decode,fileLines[index])
      if ok and type(entry)=="table" then
        newestFirst[#newestFirst+1]=entry
        if #newestFirst>=self.visibleLimit then break end
      else
        self:reportMalformed()
      end
    end
    if #newestFirst>=self.visibleLimit then break end
  end
  local chronological={}
  for index=#newestFirst,1,-1 do chronological[#chronological+1]=newestFirst[index] end
  return chronological
end

function Storage:close()
  return true
end

local function startsWith(value,prefix)
  return value:sub(1,#prefix)==prefix and (value==prefix or value:sub(#prefix+1,#prefix+1)=="/")
end

local function safeRelative(value,root,allowFile)
  if type(value)~="string" or not startsWith(value,root) then return nil end
  local relative=value:sub(#root+1):match("^/(.+)$")
  if not relative then return value==root and "" or nil end
  for segment in relative:gmatch("[^/]+") do
    if not segment:match("^[a-z0-9_-]+$") and not (allowFile and segment:match("^%d%d%d%d%-%d%d%-%d%d%.jsonl$")) then return nil end
  end
  return relative
end

function Storage.mudletApi(home)
  home=tostring(home or getMudletHomeDir()):gsub("/+$","")
  local root=home.."/DragonsGateHUD/chat"
  local function ensure(directory)
    local relative=safeRelative(directory,root,false)
    if relative==nil then return nil,"unsafe chat storage path" end
    if not lfs or type(lfs.mkdir)~="function" then return nil,"filesystem is unavailable" end
    local current=home
    for _,segment in ipairs({"DragonsGateHUD","chat"}) do
      current=current.."/"..segment
      local ok,err=lfs.mkdir(current)
      if not ok and (type(lfs.attributes)~="function" or lfs.attributes(current,"mode")~="directory") then return nil,err or "could not create chat storage" end
    end
    for segment in relative:gmatch("[^/]+") do
      current=current.."/"..segment
      local ok,err=lfs.mkdir(current)
      if not ok and (type(lfs.attributes)~="function" or lfs.attributes(current,"mode")~="directory") then return nil,err or "could not create chat storage" end
    end
    return true
  end
  local function open(pathname,mode)
    if not safeRelative(pathname,root,true) then return nil,"unsafe chat storage path" end
    if not io or type(io.open)~="function" then return nil,"file access is unavailable" end
    return io.open(pathname,mode)
  end
  return {
    mkdir=ensure,
    append=function(pathname,text)
      local file,err=open(pathname,"ab")
      if not file then return nil,err end
      local ok,writeErr=file:write(text)
      file:close()
      if not ok then return nil,writeErr or "could not append chat log" end
      return true
    end,
    list=function(directory)
      if safeRelative(directory,root,false)==nil then return {} end
      if not lfs or type(lfs.dir)~="function" then return {} end
      local ok,iterator,state=pcall(lfs.dir,directory)
      if not ok then return {} end
      local files={}
      for name in iterator,state do if name~="." and name~=".." then files[#files+1]=name end end
      return files
    end,
    read=function(pathname)
      local file=open(pathname,"rb")
      if not file then return nil end
      local content=file:read("*a")
      file:close()
      return content
    end,
    encode=function(entry) return yajl.to_string(entry) end,
    decode=function(line) return yajl.to_value(line) end,
    report=function(message) if type(cecho)=="function" then cecho("\n<red>[DGHUD Chat]</red> "..tostring(message).."\n") end end,
  }
end

return Storage
