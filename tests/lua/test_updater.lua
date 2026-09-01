local Updater=require("updater"); local SHA=require("sha256"); local Adapter=require("mudlet_adapter")
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
