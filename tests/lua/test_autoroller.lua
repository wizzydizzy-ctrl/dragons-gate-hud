local Roller=require("autoroller")
local function fake()
  local f={messages={},sent={},timers={},next=0}
  function f:reportRoller(value) self.messages[#self.messages+1]=value end
  function f:schedule(delay,fn) self.next=self.next+1; self.timers[self.next]={delay=delay,fn=fn}; return self.next end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:sendCommand(value) self.sent[#self.sent+1]=value end
  return f
end
local header=" Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Voi   Per   App"
local prompt="Use this body ? Y,n"

test("built-in OG roller scores eleven ranks and leaves qualifying prompt untouched",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="n",reroll_delay=.5,auto_start_on_name=true})
  assert(r:onLine("Name : Dace Alterac  Race : Monitanian")); assert(r:onLine(header)); assert(r:onLine("Great Great Great Great Great Great Great Great Great Great Great"))
  eq(r.state.last.total,77); assert(r:onLine(prompt)); eq(r.state.active,false); eq(#f.sent,0); eq(r.state.last.stats.APP,7)
end)

test("built-in OG roller rerolls only after a failed prompt",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="n",reroll_delay=.25,auto_start_on_name=true})
  r:onLine("Name : Test Tester Race : Human"); r:onLine(header); r:onLine("Low Low Low Low Low Low Low Low Low Low Low"); assert(r:onLine(prompt))
  eq(#f.sent,0); eq(f.timers[1].delay,.25); f.timers[1].fn(); eq(f.sent[1],"n"); eq(r.state.active,true)
end)

test("roller settings and per-stat minimums persist through callback",function()
  local f=fake(); local saved; local r=Roller.new(f,{target_total=60,min_stats={}},function(value) saved=value; return true end)
  assert(r:command("set total 65")); eq(r.cfg.target_total,65); eq(saved.target_total,65)
  assert(r:command("set STR 5")); eq(r.cfg.min_stats.STR,5); eq(r.cfg.use_min_stats,true); eq(saved.min_stats.STR,5)
  assert(r:command("set STR off")); eq(r.cfg.min_stats.STR,nil)
end)

test("roller rejects impossible score settings",function()
  local r=Roller.new(fake(),{min_stats={}})
  local ok,err=r:command("set total 78"); eq(ok,nil); assert(err:find("invalid",1,true))
  ok,err=r:command("set STR 8"); eq(ok,nil); assert(err:find("1%-7"))
  ok,err=r:command("set total 53.9"); eq(ok,nil); eq(r.cfg.target_total,nil)
  local guarded=Roller.new(fake(),{target_total=53,hard_stop=nil,max_rolls=nil,min_stats={}}); ok,err=guarded:command("set total off"); eq(ok,nil); eq(guarded.cfg.target_total,53)
  ok,err=guarded:command("set delay 1e999"); eq(ok,nil); eq(guarded.cfg.reroll_delay,nil)
end)

test("duplicate prompts schedule only one reroll and stale rolls are ignored",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="n",reroll_delay=.1})
  r:start(); r:onLine(header); r:onLine("Low Low Low Low Low Low Low Low Low Low Low")
  assert(r:onLine(prompt)); eq(r:onLine(prompt),false); eq(f.next,1)
  f.timers[1].fn(); r:onLine(header); r:onLine("not a roll"); eq(r:onLine(prompt),false); eq(f.next,1)
end)

test("standalone roller conflict prevents the built-in roller from starting",function()
  local f=fake(); function f:standaloneRollerPresent() return true end
  local r=Roller.new(f,{auto_start_on_name=true}); local ok,err=r:onLine("Name : Test Tester Race : Human")
  eq(ok,nil); eq(err,"standalone roller conflict"); eq(r.state.active,false)
end)

test("reroll send failure stops safely",function()
  local f=fake(); function f:sendCommand() error("send failed") end
  local r=Roller.new(f,{target_total=60,reroll_command="n",reroll_delay=.1}); r:start(); r:onLine(header); r:onLine("Low Low Low Low Low Low Low Low Low Low Low"); r:onLine(prompt)
  f.timers[1].fn(); eq(r.state.active,false); assert(f.messages[#f.messages]:find("Could not send reroll",1,true))
end)

test("non-throwing reroll send failure stops safely",function()
  local f=fake(); function f:sendCommand() return nil,"send failed" end
  local r=Roller.new(f,{target_total=60,reroll_command="n",reroll_delay=.1}); r:start(); r:onLine(header); r:onLine("Low Low Low Low Low Low Low Low Low Low Low"); r:onLine(prompt)
  f.timers[1].fn(); eq(r.state.active,false)
end)

test("bulk settings validate and persist atomically",function()
  local f=fake(); local saves=0; local saved
  local r=Roller.new(f,{target_total=53,hard_stop=62,reroll_delay=.1,reroll_command="n",use_min_stats=true,min_stats={STR=5}},function(value) saves=saves+1; saved=value; return true end)
  local ok,err=r:configure({target_total="60",hard_stop="off",max_rolls="1000",reroll_delay="0.2",reroll_command="n",auto_start_on_name=false,use_min_stats=true,require_min_stats_to_stop=true,logging_enabled=true,log_folder="rolls",master_file="master.txt",min_stats={STR="6",INT="off"}})
  assert(ok,err); eq(saves,1); eq(r.cfg.target_total,60); eq(r.cfg.hard_stop,nil); eq(r.cfg.min_stats.STR,6); eq(saved.max_rolls,1000)
  ok,err=r:configure({target_total="banana"}); eq(ok,nil); eq(r.cfg.target_total,60); eq(saves,1)
  ok,err=r:configure({reroll_command="y"}); eq(ok,nil); assert(err:find("must remain n",1,true)); eq(r.cfg.reroll_command,"n")
end)

test("bulk settings leave live config unchanged when persistence fails",function()
  local r=Roller.new(fake(),{target_total=53,hard_stop=62,reroll_command="n",min_stats={STR=5}},function() return nil,"disk full" end)
  local ok,err=r:configure({target_total="70"}); eq(ok,nil); eq(err,"disk full"); eq(r.cfg.target_total,53)
end)

test("reroll execution always sends n even if stored configuration is tampered",function()
  local f=fake(); local r=Roller.new(f,{target_total=60,reroll_command="y",reroll_delay=0}); r:start(); r:onLine(header); r:onLine("Low Low Low Low Low Low Low Low Low Low Low"); r:onLine(prompt); f.timers[1].fn(); eq(f.sent[1],"n")
end)
