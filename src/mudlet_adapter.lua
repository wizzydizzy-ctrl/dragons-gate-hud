local View=require("view")
local Adapter={}; Adapter.__index=Adapter
function Adapter.new() return setmetatable({},Adapter) end
function Adapter:getBorders() return getBorderLeft(),getBorderTop(),getBorderRight(),getBorderBottom() end
function Adapter:setBorders(l,t,r,b) setBorderLeft(l);setBorderTop(t);setBorderRight(r);setBorderBottom(b) end
function Adapter:createView(settings) return View.new(settings) end
function Adapter:addEvent(name,fn) return registerAnonymousEventHandler(name,fn) end
function Adapter:killEvent(id) return killAnonymousEventHandler(id) end
function Adapter:addAlias(pattern,fn) return tempAlias(pattern,fn) end
function Adapter:killAlias(id) return killAlias(id) end
function Adapter:getGMCP() return gmcp or {} end
function Adapter:openSettings() cecho("\n<gold>[DGHUD]</gold> Settings: "..getMudletHomeDir().."/DragonsGateHUD/settings.lua\n") end
local function readFile(path) local f=io.open(path,"rb"); if not f then return nil end; local data=f:read("*a"); f:close(); return data end
local function writeFile(path,data) local f=assert(io.open(path,"wb")); f:write(data); f:close() end
local function hasPackage(name) for _,value in ipairs(getPackages() or {}) do if value==name then return true end end return false end
function Adapter:startUpdate(updater)
  local settings=updater.settings; local github=settings.github or {}; local policy=settings.update or {}
  if github.owner=="GITHUB_OWNER" or not tostring(github.owner):match("^[%w_.-]+$") or not tostring(github.repository):match("^[%w_.-]+$") then return nil,"configure the GitHub owner and repository first" end
  local base=getMudletHomeDir().."/DragonsGateHUD"; local staging=base.."/staging"; lfs.mkdir(base); lfs.mkdir(staging)
  local manifestPath=staging.."/manifest.json"; local packagePath=staging.."/DragonsGateHUD.mpackage"; local ids={}; local timeoutId
  local function cleanup() for _,id in ipairs(ids) do killAnonymousEventHandler(id) end; ids={}; if timeoutId then killTimer(timeoutId); timeoutId=nil end; updater:release() end
  local function fail(message) cleanup(); cecho("\n<red>[DGHUD Update]</red> "..tostring(message).."\n") end
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
      self.replacePackage=function(_,data,name)
        if name~="DragonsGateHUD" then return nil,"package identity mismatch" end
        local verified=staging.."/verified.mpackage"; writeFile(verified,data)
        if hasPackage(name) then local removed=uninstallPackage(name); if removed==nil then return nil,"could not remove existing HUD package" end end
        local installed=installPackage(verified); if installed==nil then if old then installPackage(previous) end; return nil,"could not install HUD package" end
        return true
      end
      self.healthCheck=function() return DGHUD and DGHUD.healthCheck and DGHUD.healthCheck() end
      self.rollback=function() if readFile(previous) then uninstallPackage("DragonsGateHUD"); return installPackage(previous) end end
      local installed,why=updater:installVerified(payload,manifest.sha256); if not installed then return fail(why) end
      writeFile(current,payload); cleanup(); cecho("\n<green>[DGHUD Update]</green> Installed version "..manifest.version.."\n")
    end
  end)
  updater.expected_path=manifestPath
  local latest="https://github.com/"..github.owner.."/"..github.repository.."/releases/latest/download/manifest.json"
  downloadFile(manifestPath,latest)
  timeoutId=tempTimer(policy.timeout_seconds or 30,function() timeoutId=nil; if updater.lock then fail("download timed out") end end)
  return true
end
return Adapter
