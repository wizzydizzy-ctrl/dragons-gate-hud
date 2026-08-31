local SHA256=require("sha256"); local Release=require("release")
local Updater={}; Updater.__index=Updater
function Updater.new(adapter,settings) return setmetatable({adapter=adapter,settings=settings or {},lock=nil,expected_path=nil},Updater) end
function Updater:acquire(operation) if self.lock then return nil,self.lock.." already in progress" end; self.lock=operation; return true end
function Updater:release() self.lock=nil; self.expected_path=nil; self.refresh_after_install=nil end
function Updater:acceptDownload(path) return type(path)=="string" and path==self.expected_path end
function Updater:installVerified(payload,expected)
  if type(payload)~="string" or SHA256.hex(payload)~=tostring(expected):lower() then return nil,"package checksum mismatch" end
  if not self.adapter.replacePackage then return nil,"package adapter unavailable" end
  local ok,err=self.adapter:replacePackage(payload,"DragonsGateHUD"); if not ok then return nil,err or "package installation failed" end
  if self.adapter.healthCheck then local healthy,healthErr=self.adapter:healthCheck(); if not healthy then if self.adapter.rollback then self.adapter:rollback("DragonsGateHUD") end; return nil,healthErr or "post-install health check failed" end end
  return true
end
function Updater:installVerifiedAsync(payload,expected,done)
  done=done or function() end
  if type(payload)~="string" or SHA256.hex(payload)~=tostring(expected):lower() then done(nil,"package checksum mismatch"); return nil,"package checksum mismatch" end
  if not self.adapter.replacePackageAsync then done(nil,"package adapter unavailable"); return nil,"package adapter unavailable" end
  self.adapter:replacePackageAsync(payload,"DragonsGateHUD",function(ok,err)
    if not ok then done(nil,err or "package installation failed"); return end
    if self.adapter.healthCheck then
      local healthy,healthErr=self.adapter:healthCheck()
      if not healthy then
        local message=healthErr or "post-install health check failed"
        if self.adapter.rollbackAsync then self.adapter:rollbackAsync("DragonsGateHUD",function() done(nil,message) end)
        else done(nil,message) end
        return
      end
    end
    if self.refresh_after_install and self.adapter.refreshCharacterData then self.adapter:refreshCharacterData() end
    done(true)
  end)
  return true
end
function Updater:validateManifest(manifest)
  local github=self.settings.github or {}; local update=self.settings.update or {}
  return Release.validateManifest(manifest,{owner=github.owner,repository=github.repository,package_limit=update.package_limit})
end
function Updater:check()
  local ok,err=self:acquire("check"); if not ok then return nil,err end
  if not self.adapter.fetchManifest then self:release(); return nil,"manifest adapter unavailable" end
  local success,result=pcall(self.adapter.fetchManifest,self.adapter,self.settings); self:release(); if not success then return nil,result end; return result
end
function Updater:update()
  local ok,err=self:acquire("update"); if not ok then return nil,err end
  if not self.adapter.startUpdate then self:release(); return nil,"update adapter unavailable" end
  self.refresh_after_install=self.adapter.isCharacterActive and self.adapter:isCharacterActive() or false
  local success,result,message=pcall(self.adapter.startUpdate,self.adapter,self); if not success then self:release(); return nil,result end
  if result==nil then self:release(); return nil,message end; return true
end
function Updater:cancel() if self.adapter.cancelUpdate then self.adapter:cancelUpdate() end; self:release(); return true end
return Updater
