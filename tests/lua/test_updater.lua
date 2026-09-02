local Updater=require("updater"); local SHA=require("sha256"); local Adapter=require("mudlet_adapter")
local function releaseManifest(version)
  return {package="DragonsGateHUD",version=version,minimum_mudlet="5.0.0",archive_url="https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/download/v"..version.."/DragonsGateHUD.mpackage",sha256=string.rep("a",64),archive_size=100}
end
local updateSettings={version="0.2.70",github={owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},update={package_limit=1000}}
test("update staging lives outside the installed package directory",function()
  local base=Adapter.updateBase("/profile")
  eq(base,"/profile/DGHUDUpdater")
  eq(base:find("/DragonsGateHUD",1,true),nil)
end)
test("verified update archive retains the Mudlet package name",function()
  eq(Adapter.updateArchivePath("/profile"),"/profile/DGHUDUpdater/staging/DragonsGateHUD.mpackage")
end)
test("stable manifest downloads use a unique cache-busting URL",function()
  local url=Adapter.manifestUrl({owner="wizzydizzy-ctrl",repository="dragons-gate-hud"},1788221000)
  eq(url,"https://github.com/wizzydizzy-ctrl/dragons-gate-hud/releases/latest/download/manifest.json?dghud=1788221000")
end)
test("character prompt detection accepts an echoed command but rejects account menu",function()
  eq(Adapter.characterPrompt(">dghud update"),true)
  eq(Adapter.characterPrompt("Your selection? dghud update"),false)
end)
test("update lock rejects overlapping operations",function() local u=Updater.new({},{}); eq(u:acquire("update"),true); local ok,err=u:acquire("check"); eq(ok,nil); eq(err,"update already in progress"); u:release(); eq(u:acquire("check"),true) end)
test("download events correlate by exact owned path",function() local u=Updater.new({},{data_dir="/profile/DragonsGateHUD"}); u.expected_path="/profile/DragonsGateHUD/staging/package.mpackage"; eq(u:acceptDownload("/other/script/file"),false); eq(u:acceptDownload(u.expected_path),true) end)
test("archive checksum mismatch blocks replacement",function() local called=false; local u=Updater.new({replacePackage=function() called=true end},{}); local ok=u:installVerified("payload",string.rep("0",64)); eq(ok,nil); eq(called,false); eq(SHA.hex("payload")~=string.rep("0",64),true) end)
test("successful verified install requires health check",function() local calls=0; local u=Updater.new({replacePackage=function() calls=calls+1; return true end,healthCheck=function() return true end},{}); eq(u:installVerified("payload",SHA.hex("payload")),true); eq(calls,1) end)
test("async install verifies before replacement and completes after health check",function()
  local order={}
  local adapter={
    replacePackageAsync=function(_,payload,name,done)
      order[#order+1]="replace:"..name..":"..payload
      done(true)
    end,
    healthCheck=function() order[#order+1]="health"; return true end,
  }
  local result
  local u=Updater.new(adapter,{})
  eq(u:installVerifiedAsync("payload",SHA.hex("payload"),function(ok,err) result={ok,err} end),true)
  eq(order[1],"replace:DragonsGateHUD:payload")
  eq(order[2],"health")
  eq(result[1],true)
end)
test("successful in-session update refreshes command-backed character data",function()
  local refreshed=false
  local adapter={replacePackageAsync=function(_,_,_,done) done(true) end,healthCheck=function() return true end,refreshCharacterData=function() refreshed=true; return true end}
  local u=Updater.new(adapter,{}); u.refresh_after_install=true
  u:installVerifiedAsync("payload",SHA.hex("payload"),function() end)
  eq(refreshed,true)
end)
test("startup check skips installation when current and continues startup",function()
  local order={}; local completed
  local adapter={checkLatestAsync=function(_,updater,done) order[#order+1]="check"; done(releaseManifest("0.2.70")) end}
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err}; order[#order+1]="commands" end),true)
  eq(table.concat(order,","),"check,commands"); eq(completed[1],false); eq(completed[2],nil); eq(u.lock,nil)
end)
test("startup check updates before allowing startup commands",function()
  local order={}; local completed
  local adapter={
    checkLatestAsync=function(_,updater,done) order[#order+1]="check"; done(releaseManifest("0.2.71")) end,
    startUpdate=function(_,updater,done) order[#order+1]="update"; done(true); return true end,
    isCharacterActive=function() return true end,
  }
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err}; order[#order+1]="commands" end),true)
  eq(table.concat(order,","),"check,update,commands"); eq(completed[1],true); eq(completed[2],nil); eq(u.lock,nil)
end)
test("startup check failure reports briefly and still allows startup commands",function()
  local reported; local completed
  local adapter={
    checkLatestAsync=function(_,updater,done) done(nil,"network timed out") end,
    reportUpdateCheckFailure=function(_,message) reported=message end,
  }
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function(updated,err) completed={updated,err} end),true)
  eq(reported,"network timed out"); eq(completed[1],false); eq(completed[2],"network timed out"); eq(u.lock,nil)
end)
test("startup check contains adapter exceptions and still allows startup commands",function()
  local reported; local completed
  local adapter={
    checkLatestAsync=function() error("network exploded") end,
    reportUpdateCheckFailure=function(_,message) reported=message end,
  }
  local u=Updater.new(adapter,updateSettings)
  local ok,err=u:checkAtCharacterEntry(function(updated,message) completed={updated,message} end)
  eq(ok,nil); eq(err,"network exploded"); eq(reported,"network exploded"); eq(completed[1],false); eq(completed[2],"network exploded"); eq(u.lock,nil)
end)
test("startup check rejects overlap and completes only once",function()
  local manifestDone; local completions=0
  local adapter={checkLatestAsync=function(_,_,done) manifestDone=done; return true end}
  local u=Updater.new(adapter,updateSettings)
  eq(u:checkAtCharacterEntry(function() completions=completions+1 end),true)
  local ok,err=u:checkAtCharacterEntry(function() completions=completions+1 end); eq(ok,nil); eq(err,"startup check already in progress")
  manifestDone(releaseManifest("0.2.70")); manifestDone(releaseManifest("0.2.70")); eq(completions,1)
end)
test("async checksum mismatch never starts replacement",function()
  local called=false
  local u=Updater.new({replacePackageAsync=function() called=true end},{})
  local result
  local ok=u:installVerifiedAsync("payload",string.rep("0",64),function(success,err) result={success,err} end)
  eq(ok,nil)
  eq(called,false)
  eq(result[1],nil)
  eq(result[2],"package checksum mismatch")
end)
test("async failed health check triggers rollback",function()
  local rolledBack=false
  local adapter={
    replacePackageAsync=function(_,_,_,done) done(true) end,
    healthCheck=function() return nil,"HUD did not start" end,
    rollbackAsync=function(_,_,done) rolledBack=true; done(true) end,
  }
  local result
  local u=Updater.new(adapter,{})
  u:installVerifiedAsync("payload",SHA.hex("payload"),function(ok,err) result={ok,err} end)
  eq(rolledBack,true)
  eq(result[1],nil)
  eq(result[2],"HUD did not start")
end)
