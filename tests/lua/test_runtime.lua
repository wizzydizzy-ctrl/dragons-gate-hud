local Main=require("main")
local function fake()
  local f={next=0,killed={},deleted=0,borders={10,20,30,40},set_borders={},callbacks={},layouts={},triggers={},timers={},events={},aliases={}}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders(a,b,c,d) self.set_borders={a,b,c,d} end
  function f:getWindowSize() return self.width or 1920,self.height or 1080 end
  function f:createView() return {update=function(self,state) self.state=state end,applyLayout=function(self,layout) f.layouts[#f.layouts+1]=layout end,delete=function() f.deleted=f.deleted+1 end} end
  function f:addEvent(name,fn) self.next=self.next+1; self.callbacks[name]=fn; local id="event-"..self.next; self.events[id]=name; return id end
  function f:addAlias() self.next=self.next+1; local id="alias-"..self.next; self.aliases[id]=true; return id end
  function f:killEvent(id) self.killed[id]=true; self.events[id]=nil end
  function f:killAlias(id) self.killed[id]=true; self.aliases[id]=nil end
  function f:getGMCP() return {Char={Vitals={hp=1,hp_max=1}}} end
  function f:addLineTrigger(fn) self.next=self.next+1; local id="trigger-"..self.next; self.triggers[id]=fn; return id end
  function f:killTrigger(id) self.killed[id]=true; self.triggers[id]=nil end
  function f:schedule(_,fn) self.next=self.next+1; local id="timer-"..self.next; self.timers[id]=fn; return id end
  function f:cancelTimer(id) self.timers[id]=nil end
  function f:sendCommand(command) self.sent=command end
  function f:count(tableValue) local n=0; for _ in pairs(tableValue) do n=n+1 end; return n end
  return f
end
test("startup is idempotent and shutdown owns exact runtime IDs",function()
  local f=fake(); local hud=Main.new(f,{layout={left_width=190,right_width=270}}); eq(hud:start(),true); local first=f.next; eq(hud:start(),true); eq(f.next,first); eq(hud:shutdown(),true); eq(f.deleted,1); eq(f.set_borders[1],0); eq(f.set_borders[2],0); eq(f:count(f.events),0); eq(f:count(f.aliases),0); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("health check requires root and handlers",function() local hud=Main.new(fake(),{layout={left_width=190,right_width=270}}); eq(hud:healthCheck(),nil); hud:start(); eq(hud:healthCheck(),true) end)
test("window resize recomputes absolute borders and view layout",function()
  local f=fake(); f.borders={1290,234,1610,120}; local hud=Main.new(f,{layout={}}); hud:start(); eq(f.layouts[#f.layouts].mode,"wide"); eq(f.set_borders[1],384); eq(f.set_borders[2],74); eq(f.set_borders[3],384); f.width=760; f.height=700; f.callbacks["sysWindowResizeEvent"](); eq(f.layouts[#f.layouts].mode,"compact"); eq(f.set_borders[1],0); eq(f.set_borders[2],116); eq(f.set_borders[3],0); eq(f.set_borders[4],58)
end)
test("controller merges collector snapshots and removes collector runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud.collector.snapshot.info={attributes={STR="Good"}}; hud:refresh(); eq(hud.last_state.attributes.STR,"Good"); eq(f:count(f.triggers),1); hud:shutdown(); eq(f:count(f.triggers),0); eq(f:count(f.timers),0)
end)
test("reload leaves one command collector",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); hud:reload(); eq(f:count(f.triggers),1); local outgoing=0; for _,name in pairs(f.events) do if name=="sysDataSendRequest" then outgoing=outgoing+1 end end; eq(outgoing,1)
end)
test("repeated resize changes typography without growing runtime",function()
  local f=fake(); local hud=Main.new(f,{layout={}}); hud:start(); local runtime=f:count(f.events)+f:count(f.triggers)+f:count(f.aliases)
  for _,size in ipairs({{2056,1177},{1200,800},{760,700},{3840,2160},{1200,800}}) do
    f.width,f.height=size[1],size[2]; f.callbacks["sysWindowResizeEvent"](); local r=f.layouts[#f.layouts]
    eq(r.inventory_row_height>=r.inventory_font+8,true); eq(r.details_line_height>=r.body_font+4,true); eq(r.console_width>=size[1]*.60,true); eq(f:count(f.events)+f:count(f.triggers)+f:count(f.aliases),runtime)
  end
end)
