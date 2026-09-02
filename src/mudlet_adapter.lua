local View=require("view"); local Storage=require("chat_storage"); local MapAdapter=require("map_adapter"); local SHA256=require("sha256")
local Adapter={}; Adapter.__index=Adapter
function Adapter.updateBase(home) return home.."/DGHUDUpdater" end
function Adapter.updateArchivePath(home) return Adapter.updateBase(home).."/staging/DragonsGateHUD.mpackage" end
function Adapter.verifyArchive(payload,digest) return type(payload)=="string" and type(digest)=="string" and SHA256.hex(payload)==digest end
function Adapter.manifestUrl(github,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/latest/download/manifest.json?dghud="..tostring(nonce)
end
function Adapter.versionManifestUrl(github,version,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/download/v"..tostring(version).."/manifest.json?dghud="..tostring(nonce)
end
local updateNonce=0
function Adapter.new() return setmetatable({},Adapter) end
function Adapter:getBorders() return getBorderLeft(),getBorderTop(),getBorderRight(),getBorderBottom() end
function Adapter:getWindowSize() return getMainWindowSize() end
function Adapter:setBorders(l,t,r,b) setBorderLeft(l);setBorderTop(t);setBorderRight(r);setBorderBottom(b) end
function Adapter:suppressDefaultMapInfo(api)
  api=api or _G
  if type(api.disableMapInfo)~="function" then return true end
  local ok,err=pcall(function()
    api.disableMapInfo("Short")
    api.disableMapInfo("Full")
    if type(api.updateMap)=="function" then api.updateMap() end
  end)
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:centerMap(roomID)
  local ok,err=pcall(function() centerview(roomID); updateMap() end)
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:createView(settings)
  local view=View.new(settings)
  if view.setMapCenterCallback then view:setMapCenterCallback(function(roomID) return self:centerMap(roomID) end) end
  return view
end
function Adapter:createMapAdapter(api)
  local map=MapAdapter.new(api or MapAdapter.mudletApi(_G))
  function map:setCurrent(roomID)
    if not self:isOwned(roomID) then return nil,"room "..tostring(roomID).." is not owned by DragonsGateHUD" end
    return self:center(roomID)
  end
  return map
end
function Adapter:createChatStorage(visibleLimit) return Storage.new(Storage.mudletApi(),getMudletHomeDir().."/DragonsGateHUD/chat",visibleLimit) end
function Adapter:addEvent(name,fn) return registerAnonymousEventHandler(name,fn) end
function Adapter:killEvent(id) return killAnonymousEventHandler(id) end
function Adapter:addAlias(pattern,fn) return tempAlias(pattern,fn) end
function Adapter:killAlias(id) return killAlias(id) end
function Adapter:addLineTrigger(fn) return tempRegexTrigger("^.*$",function() fn(line or "") end) end
function Adapter:addColorizerTrigger(fn)
  return tempRegexTrigger([=[(?i)^\s*(?:\[[^\r\n\[\]]+\]|Obvious\s+(?:exits|paths)\s*:[^\r\n]*)\s*$]=],function()
    fn(line or (type(getCurrentLine)=="function" and getCurrentLine() or ""))
  end)
end
function Adapter:applyLineColors(segments,api)
  api=api or _G
  if type(segments)~="table" or type(api.selectSection)~="function" or type(api.setFgColor)~="function" then return nil,"Mudlet line-color API is unavailable" end
  local ok,err=pcall(function()
    for _,item in ipairs(segments) do
      local color=item.color
      assert(type(item.start)=="number" and type(item.length)=="number" and type(color)=="table","invalid color segment")
      api.selectSection(item.start-1,item.length)
      api.setFgColor(color[1],color[2],color[3])
    end
    if type(api.deselect)=="function" then api.deselect() end
  end)
  if not ok then if type(api.deselect)=="function" then pcall(api.deselect) end; return nil,tostring(err) end
  return true
end
function Adapter:killTrigger(id) return killTrigger(id) end
function Adapter:epoch() return os.time() end
function Adapter:localTime() return os.date("%I:%M:%S %p"):gsub("^0","") end
function Adapter:startClockTimer(fn) return tempTimer(1,fn,true) end
function Adapter:stopClockTimer(id) return killTimer(id) end
function Adapter:cleanupClock() return os.time() end
function Adapter:cleanupToken(source)
  source=source or io
  if type(source)~="table" or type(source.open)~="function" then return nil,"secure random source is unavailable" end
  local openOK,file=pcall(source.open,"/dev/urandom","rb")
  if not openOK or not file then return nil,"secure random source is unavailable" end
  local readOK,bytes=pcall(file.read,file,16)
  if type(file.close)=="function" then pcall(file.close,file) end
  if not readOK then return nil,"secure random source read failed" end
  if type(bytes)~="string" or #bytes~=16 then return nil,"secure random source returned incomplete data" end
  return SHA256.hex(bytes):sub(1,16)
end
function Adapter:refreshMap(api)
  api=api or _G
  if type(api.updateMap)~="function" then return nil,"Mudlet mapper API updateMap is unavailable" end
  local ok,err=pcall(api.updateMap)
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:reportMapCleanup(message,isError)
  local color=isError and "red" or "gold"
  local ok,err=pcall(cecho,"\n<"..color..">[DGHUD Map]<reset> "..tostring(message).."\n")
  if not ok then return nil,tostring(err) end
  return true
end
function Adapter:timestamp() return os.date("%Y-%m-%dT%H:%M:%S%z") end
function Adapter:reportChatErrorOnce(message) cecho("\n<red>[DGHUD Chat]<reset> "..tostring(message).."\n") end
function Adapter:reportChatStatus(status)
  status=type(status)=="table" and status or {}
  local storage=status.storage_key or "unknown"; local error=status.last_storage_error or "none"
  cecho("\n<gold>[DGHUD Chat]<reset> filter="..tostring(status.active_filter or "OFF").." visible="..tostring(status.visible_count or 0).." storage="..tostring(storage).." last storage error="..tostring(error).."\n")
  return status
end
function Adapter:reportColorizerStatus(enabled)
  cecho("\n<gold>[DGHUD Colors]<reset> "..(enabled and "ON" or "OFF").."\n")
  return true
end
function Adapter:schedule(seconds,fn) return tempTimer(seconds,fn) end
function Adapter:cancelTimer(id) return killTimer(id) end
function Adapter:sendCommand(command) return send(command) end
function Adapter:getGMCP() return gmcp or {} end
function Adapter.characterPrompt(value) return tostring(value or ""):match("^>")~=nil end
function Adapter:isCharacterActive() return Adapter.characterPrompt(getCurrentLine and getCurrentLine() or "") end
function Adapter:mudletVersion()
  if type(getMudletVersion)~="function" then return nil end
  local ok,major,minor,revision=pcall(getMudletVersion,"table"); if not ok then return nil end
  if type(major)=="table" then return major end
  if tonumber(major) and tonumber(minor) and tonumber(revision) then return {major,minor,revision} end
  return nil
end
function Adapter:refreshCharacterData()
  local controller=DGHUD and DGHUD.controller
  if not controller then return nil,"HUD controller is unavailable" end
  if controller.character_entry_started then return true end
  if type(controller.onCharacterEntry)=="function" then return controller:onCharacterEntry() end
  return nil,"HUD startup refresh is unavailable"
end
function Adapter:reportUpdateCheckFailure(message) cecho("\n<yellow>[DGHUD Update]<reset> Version check failed: "..tostring(message).."; refreshing character data.\n") end
function Adapter:openSettings() cecho("\n<gold>[DGHUD]<reset> Settings: "..getMudletHomeDir().."/DragonsGateHUD/settings.lua\n") end
local function readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local data=f:read("*a"); f:close(); return data end
local function writeFile(path,data) local f=assert(io.open(path,"wb")); f:write(data); f:close() end
local function hasPackage(name) for _,value in ipairs(getPackages() or {}) do if value==name then return true end end return false end
function Adapter:checkLatestAsync(updater,done)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=Adapter.updateBase(getMudletHomeDir()); local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local manifestPath=staging.."/startup-manifest.json"; local ids={}; local timeoutId; local finished=false
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; if timeoutId then killTimer(timeoutId); timeoutId=nil end end
  local function finish(manifest,message) if finished then return end; finished=true; cleanup(); done(manifest,message) end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,url) if url and url:find(github.repository,1,true) then finish(nil,message) end end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,path)
    if path~=manifestPath then return end
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then finish(nil,"manifest is missing or too large"); return end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then finish(nil,"manifest JSON is invalid"); return end
    local valid,why=updater:validateManifest(manifest); if not valid then finish(nil,why); return end
    finish(manifest)
  end)
  updateNonce=updateNonce+1
  downloadFile(manifestPath,Adapter.manifestUrl(github,tostring(os.time()).."-"..tostring(updateNonce)))
  timeoutId=tempTimer(policy.timeout_seconds or 30,function() timeoutId=nil; finish(nil,"download timed out") end)
  return true
end
function Adapter:startUpdate(updater,done)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=Adapter.updateBase(getMudletHomeDir()); local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local manifestPath=staging.."/manifest.json"; local packagePath=Adapter.updateArchivePath(getMudletHomeDir())
  local rollbackManifestPath=staging.."/rollback-manifest.json"; local rollbackPackagePath=staging.."/rollback.mpackage"
  local currentPath=base.."/current.mpackage"; local currentManifestPath=base.."/current-manifest.json"; local previousPath=base.."/previous.mpackage"
  local ids={}; local timers={}; local timeoutId; local expectedPath; local expectedUrl; local targetManifest; local targetManifestRaw; local rollbackManifest; local previousDigest; local finished=false
  local function schedule(delay,fn) local id; id=tempTimer(delay,function() for i,value in ipairs(timers) do if value==id then table.remove(timers,i); break end end; fn() end); timers[#timers+1]=id; return id end
  local function disarmTimeout() if timeoutId then killTimer(timeoutId); timeoutId=nil end end
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; for _,id in ipairs(timers) do killTimer(id) end; timers={}; disarmTimeout(); updater:release() end
  local function fail(message) if finished then return end; finished=true; cleanup(); cecho("\n<red>[DGHUD Update]<reset> "..tostring(message).."\n"); if done then done(nil,message) end end
  local function armTimeout() disarmTimeout(); timeoutId=tempTimer(policy.timeout_seconds or 30,function() timeoutId=nil; if updater.lock then fail("download timed out") end end) end
  local function request(path,url) expectedPath=path; expectedUrl=url; updater.expected_path=path; armTimeout(); downloadFile(path,url) end
  local function parseManifest(path)
    local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then return nil,nil,"manifest is missing or too large" end
    local ok,manifest=pcall(yajl.to_value,raw); if not ok then return nil,nil,"manifest JSON is invalid" end
    local valid,why=updater:validateManifest(manifest); if not valid then return nil,nil,why end
    return manifest,raw
  end
  local function exactInstalled(manifest) return manifest and tostring(manifest.version)==tostring(settings.version) end
  local beginReplacement
  local function stageRollback(payload)
    if not Adapter.verifyArchive(payload,rollbackManifest.sha256) then return fail("rollback package checksum mismatch") end
    writeFile(previousPath,payload); previousDigest=SHA256.hex(payload); beginReplacement()
  end
  local function bootstrapRollback()
    local cached=readFile(currentPath); local cachedManifestRaw=readFile(currentManifestPath)
    if cached and cachedManifestRaw then
      local ok,cachedManifest=pcall(yajl.to_value,cachedManifestRaw)
      if ok then
        local valid=updater:validateManifest(cachedManifest)
        if valid and exactInstalled(cachedManifest) and #cached<=(policy.package_limit or 10485760) and Adapter.verifyArchive(cached,cachedManifest.sha256) then rollbackManifest=cachedManifest; return stageRollback(cached) end
      end
    end
    updateNonce=updateNonce+1
    request(rollbackManifestPath,Adapter.versionManifestUrl(github,settings.version,tostring(os.time()).."-"..tostring(updateNonce)))
  end
  beginReplacement=function()
    disarmTimeout(); expectedPath=nil; expectedUrl=nil
    self.replacePackageAsync=function(_,data,name,replaceDone)
      if name~="DragonsGateHUD" then replaceDone(nil,"package identity mismatch"); return end
      writeFile(packagePath,data)
      if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
      if hasPackage(name) then local removed=uninstallPackage(name); if removed==nil then replaceDone(nil,"could not remove existing HUD package"); return end end
      schedule(0.25,function()
        local installed=installPackage(packagePath)
        if installed==nil then replaceDone(nil,"could not install HUD package"); return end
        schedule(0.40,function() replaceDone(true) end)
      end)
    end
    self.healthCheck=function() return DGHUD and DGHUD.healthCheck and DGHUD.healthCheck() end
    self.rollbackAsync=function(_,name,rollbackDone)
      local rollbackPayload=readFile(previousPath)
      if name~="DragonsGateHUD" or not rollbackPayload then rollbackDone(nil,"no rollback package available"); return end
      if not Adapter.verifyArchive(rollbackPayload,previousDigest) then rollbackDone(nil,"rollback package checksum mismatch"); return end
      if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
      if hasPackage(name) then uninstallPackage(name) end
      schedule(0.25,function()
        local restored=installPackage(previousPath)
        schedule(0.40,function() rollbackDone(restored~=nil,restored==nil and "could not restore rollback package" or nil) end)
      end)
    end
    local completed=false
    local started,why=updater:installVerifiedAsync(readFile(packagePath),targetManifest.sha256,function(installed,message)
      completed=true
      if not installed then fail(message); return end
      writeFile(currentPath,readFile(packagePath)); writeFile(currentManifestPath,targetManifestRaw)
      if finished then return end; finished=true; cleanup(); cecho("\n<green>[DGHUD Update]<reset> Installed version "..targetManifest.version.."\n"); if done then done(true) end
    end)
    if not started and not completed then fail(why) end
  end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,url) if expectedUrl and url==expectedUrl then fail(message) end end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,path)
    if finished or path~=expectedPath then return end
    disarmTimeout(); expectedPath=nil; expectedUrl=nil
    if path==manifestPath then
      local manifest,raw,why=parseManifest(path); if not manifest then return fail(why) end
      targetManifest=manifest; targetManifestRaw=raw; request(packagePath,manifest.archive_url)
    elseif path==packagePath then
      local payload=readFile(path)
      if not payload or #payload>(policy.package_limit or 10485760) then return fail("package is missing or too large") end
      if not Adapter.verifyArchive(payload,targetManifest.sha256) then return fail("package checksum mismatch") end
      bootstrapRollback()
    elseif path==rollbackManifestPath then
      local manifest,_,why=parseManifest(path); if not manifest then return fail("rollback bootstrap failed: "..tostring(why)) end
      if not exactInstalled(manifest) then return fail("rollback bootstrap returned the wrong installed version") end
      rollbackManifest=manifest
      local cached=readFile(currentPath)
      if cached and #cached<=(policy.package_limit or 10485760) and Adapter.verifyArchive(cached,manifest.sha256) then stageRollback(cached)
      else request(rollbackPackagePath,manifest.archive_url) end
    elseif path==rollbackPackagePath then
      local payload=readFile(path)
      if not payload or #payload>(policy.package_limit or 10485760) then return fail("rollback package is missing or too large") end
      stageRollback(payload)
    end
  end)
  updateNonce=updateNonce+1
  local latest=Adapter.manifestUrl(github,tostring(os.time()).."-"..tostring(updateNonce))
  request(manifestPath,latest)
  return true
end
return Adapter
