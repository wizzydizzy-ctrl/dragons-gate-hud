local Collector=require("command_collector")
local Parser=require("command_parser")
local inventory={"Items carried:","  A torch [1.0 lb].","Your inventory totals 1.0 lbs.",">"}
local stat={"Body Armor: 4%.","OR: 18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","::: Equipment Readied :::","  A spear.",">"}
local info={"You are Test Tester, a stocky bodied 28 year old Entropic Male young Monitanian.  You are 6'10\" and weigh 309 lbs.","Str Int Wis Dex Agi Con Cha Wil Voi Per App","Good Low Fair Fair Fair Good Good Good Aver Fair Fair",">"}
local religion={"You are a Novitiate follower of Unknown.","You are Balanced within your Entropic alignment.",">"}
local skills={"Skill                     Remain Level","Biting                    105    4","Clawing                   276    2",">"}
local function fake()
  local f={next=0,triggers={},events={},timers={},sent={}}
  local function id(self,prefix) self.next=self.next+1; return prefix..self.next end
  function f:addLineTrigger(fn) local key=id(self,"t"); self.triggers[key]=fn; return key end
  function f:killTrigger(key) self.triggers[key]=nil end
  function f:addEvent(name,fn) local key=id(self,"e"); self.events[key]={name=name,fn=fn}; return key end
  function f:killEvent(key) self.events[key]=nil end
  function f:schedule(delay,fn) self.last_delay=delay; local key=id(self,"m"); self.timers[key]=fn; return key end
  function f:cancelTimer(key) self.timers[key]=nil end
  function f:sendCommand(command) self.sent[#self.sent+1]=command end
  function f:line(value) for _,fn in pairs(self.triggers) do fn(value) end end
  function f:lines(values) for _,value in ipairs(values) do self:line(value) end end
  function f:outgoing(command) for _,event in pairs(self.events) do if event.name=="sysDataSendRequest" then event.fn(nil,command) end end end
  function f:disconnect() for _,event in pairs(self.events) do if event.name=="sysDisconnectionEvent" then event.fn() end end end
  function f:fireTimer() local key,fn=next(self.timers); if key then self.timers[key]=nil; fn() end end
  function f:owned() local n=0; for _ in pairs(self.triggers) do n=n+1 end; for _ in pairs(self.events) do n=n+1 end; for _ in pairs(self.timers) do n=n+1 end; return n end
  return f
end

test("collector runs one sequential refresh after character entry",function()
  local f=fake(); local changes=0; local c=Collector.new(f,Parser,function() changes=changes+1 end); c:start()
  f:line("Welcome to Dragon's Gate, Test!"); eq(f.sent[1],"inventory"); eq(#f.sent,1)
  f:lines(inventory); eq(f.sent[2],"stat")
  f:lines(stat); eq(f.sent[3],"info")
  f:lines(info); eq(f.sent[4],"info religion")
  f:lines(religion); eq(f.sent[5],"skill")
  f:lines(skills); eq(changes,5); eq(c.snapshot.religion.deity,"Unknown"); eq(#c.snapshot.skills.items,2)
  f:line("Welcome to Dragon's Gate, Test!"); eq(#f.sent,5)
end)
test("collector can refresh after an in-session package install",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start()
  eq(c:refresh(),true); eq(f.sent[1],"inventory"); eq(c.refreshed,true); eq(f.last_delay>=20,true)
  eq(c:refresh(),false); eq(#f.sent,1)
end)
test("collector captures manual info religion commands",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("info religion"); f:lines(religion); eq(c.snapshot.religion.rank,"Novitiate")
end)
test("collector refreshes skills whenever skill is entered manually",function()
  local f=fake(); local changed; local c=Collector.new(f,Parser,function(_,key) changed=key end); c:start(); f:outgoing("skill"); f:lines(skills)
  eq(changed,"skills"); eq(c.snapshot.skills.items[1].name,"Biting")
end)
test("collector captures manual commands and removes owned runtime",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inventory"); f:lines(inventory); eq(c.snapshot.inventory.total_weight,1); c:shutdown(); eq(f:owned(),0)
end)
test("collector treats inv as a manual inventory command",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:outgoing("inv"); f:lines(inventory); eq(c.snapshot.inventory.total_weight,1)
end)
test("collector reports explicit game delay lines",function()
  local f=fake(); local delay; local c=Collector.new(f,Parser,function() end,function(value) delay=value end); c:start(); f:line("[8 sec. delay]"); eq(delay,8)
end)
test("collector timeout preserves old data and advances startup",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c.snapshot.inventory={total_weight=7}; c:start(); f:line("Welcome to Dragon's Gate, Test!"); f:fireTimer(); eq(c.snapshot.inventory.total_weight,7); eq(f.sent[2],"stat")
end)
test("disconnect permits one refresh after re-entry",function()
  local f=fake(); local c=Collector.new(f,Parser,function() end); c:start(); f:line("Welcome to Dragon's Gate, Test!"); f:disconnect(); f:line("Welcome to Dragon's Gate, Test!"); eq(f.sent[#f.sent],"inventory")
end)
