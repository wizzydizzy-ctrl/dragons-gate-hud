local View=require("view"); local Storage=require("chat_storage"); local MapAdapter=require("map_adapter")
local Adapter={}; Adapter.__index=Adapter
function Adapter.updateBase(home) return home.."/DGHUDUpdater" end
function Adapter.updateArchivePath(home) return Adapter.updateBase(home).."/staging/DragonsGateHUD.mpackage" end
function Adapter.manifestUrl(github,nonce)
  return "https://github.com/"..github.owner.."/"..github.repository.."/releases/latest/download/manifest.json?dghud="..tostring(nonce)
end
local updateNonce=0
function Adapter.new() return setmetatable({},Adapter) end
function Adapter:getBorders() return getBorderLeft(),getBorderTop(),getBorderRight(),getBorderBottom() end
function Adapter:getWindowSize() return getMainWindowSize() end
function Adapter:setBorders(l,t,r,b) setBorderLeft(l);setBorderTop(t);setBorderRight(r);setBorderBottom(b) end
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
function Adapter:killTrigger(id) return killTrigger(id) end
function Adapter:epoch() return os.time() end
function Adapter:timestamp() return os.date("%Y-%m-%dT%H:%M:%S%z") end
function Adapter:reportChatErrorOnce(message) cecho("\n<red>[DGHUD Chat]<reset> "..tostring(message).."\n") end
function Adapter:reportChatStatus(status)
  status=type(status)=="table" and status or {}
  local storage=status.storage_key or "unknown"; local error=status.last_storage_error or "none"
  cecho("\n<gold>[DGHUD Chat]<reset> filter="..tostring(status.active_filter or "OFF").." visible="..tostring(status.visible_count or 0).." storage="..tostring(storage).." last storage error="..tostring(error).."\n")
  return status
end
function Adapter:schedule(seconds,fn) return tempTimer(seconds,fn) end
function Adapter:cancelTimer(id) return killTimer(id) end
function Adapter:sendCommand(command) return send(command) end
function Adapter:getGMCP() return gmcp or {} end
function Adapter.characterPrompt(value) return tostring(value or ""):match("^>")~=nil end
function Adapter:isCharacterActive() return Adapter.characterPrompt(getCurrentLine and getCurrentLine() or "") end
function Adapter:refreshCharacterData() return DGHUD and DGHUD.controller and DGHUD.controller.collector and DGHUD.controller.collector:refresh() end
function Adapter:openSettings() cecho("\n<gold>[DGHUD]<reset> Settings: "..getMudletHomeDir().."/DragonsGateHUD/settings.lua\n") end
local function readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local data=f:read("*a"); f:close(); return data end
local function writeFile(path,data) local f=assert(io.open(path,"wb")); f:write(data); f:close() end
local function hasPackage(name) for _,value in ipairs(getPackages() or {}) do if value==name then return true end end return false end
function Adapter:startUpdate(updater)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=Adapter.updateBase(getMudletHomeDir()); local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local manifestPath=staging.."/manifest.json"; local packagePath=Adapter.updateArchivePath(getMudletHomeDir()); local ids={}; local timers={}; local timeoutId
  local function schedule(delay,fn) local id; id=tempTimer(delay,function() for i,value in ipairs(timers) do if value==id then table.remove(timers,i); break end end; fn() end); timers[#timers+1]=id; return id end
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; for _,id in ipairs(timers) do killTimer(id) end; timers={}; if timeoutId then killTimer(timeoutId); timeoutId=nil end; updater:release() end
  local function fail(message) cleanup(); cecho("\n<red>[DGHUD Update]<reset> "..tostring(message).."\n") end
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,url) if url and (url:find(github.repository,1,true)) then fail(message) end end)
  ids[#ids+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,path)
    if path==manifestPath then
      local raw=readFile(path); if not raw or #raw>(policy.manifest_limit or 65536) then return fail("manifest is missing or too large") end
      local ok,manifest=pcall(yajl.to_value,raw); if not ok then return fail("manifest JSON is invalid") end
      local valid,why=updater:validateManifest(manifest); if not valid then return fail(why) end
      updater.pending_manifest=manifest; updater.expected_path=packagePath; downloadFile(packagePath,manifest.archive_url)
    elseif path==packagePath then
      local payload=readFile(path); local manifest=updater.pending_manifest
      if not payload or #payload>(policy.package_limit or 10485760) then return fail("package is missing or too large") end
      local current=base.."/current.mpackage"; local previous=base.."/previous.mpackage"; local old=readFile(current); if old then writeFile(previous,old) end
      self.replacePackageAsync=function(_,data,name,done)
        if name~="DragonsGateHUD" then done(nil,"package identity mismatch"); return end
        local verified=packagePath; writeFile(verified,data)
        if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
        if hasPackage(name) then local removed=uninstallPackage(name); if removed==nil then done(nil,"could not remove existing HUD package"); return end end
        schedule(0.25,function()
          local installed=installPackage(verified)
          if installed==nil then done(nil,"could not install HUD package"); return end
          schedule(0.40,function() done(true) end)
        end)
      end
      self.healthCheck=function() return DGHUD and DGHUD.healthCheck and DGHUD.healthCheck() end
      self.rollbackAsync=function(_,name,done)
        if name~="DragonsGateHUD" or not readFile(previous) then done(nil,"no rollback package available"); return end
        if DGHUD and DGHUD.shutdown then pcall(DGHUD.shutdown) end
        if hasPackage(name) then uninstallPackage(name) end
        schedule(0.25,function() local restored=installPackage(previous); schedule(0.40,function() done(restored~=nil) end) end)
      end
      local completed=false
      local started,why=updater:installVerifiedAsync(payload,manifest.sha256,function(installed,message)
        completed=true
        if not installed then fail(message); return end
        writeFile(current,payload); cleanup(); cecho("\n<green>[DGHUD Update]<reset> Installed version "..manifest.version.."\n")
      end)
      if not started and not completed then return fail(why) end
    end
  end)
  updater.expected_path=manifestPath
  updateNonce=updateNonce+1
  local latest=Adapter.manifestUrl(github,tostring(os.time()).."-"..tostring(updateNonce))
  downloadFile(manifestPath,latest)
  timeoutId=tempTimer(policy.timeout_seconds or 30,function() timeoutId=nil; if updater.lock then fail("download timed out") end end)
  return true
end
return Adapter
