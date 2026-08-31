local Main=require("main")
local function fake()
  local f={next=0,killed={},deleted=0,borders={10,20,30,40},set_borders={}}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders(a,b,c,d) self.set_borders={a,b,c,d} end
  function f:createView() return {update=function(self,state) self.state=state end,delete=function() f.deleted=f.deleted+1 end} end
  function f:addEvent() self.next=self.next+1; return "event-"..self.next end
  function f:addAlias() self.next=self.next+1; return "alias-"..self.next end
  function f:killEvent(id) self.killed[id]=true end
  function f:killAlias(id) self.killed[id]=true end
  function f:getGMCP() return {Char={Vitals={hp=1,hp_max=1}}} end
  return f
end
test("startup is idempotent and shutdown owns exact runtime IDs",function()
  local f=fake(); local hud=Main.new(f,{layout={left_width=190,right_width=270}}); eq(hud:start(),true); local first=f.next; eq(hud:start(),true); eq(f.next,first); eq(hud:shutdown(),true); eq(f.deleted,1); eq(f.set_borders[1],10); eq(f.set_borders[2],20); for i=1,first do eq(f.killed[(i<=5 and "event-" or "alias-")..i],true) end
end)
test("health check requires root and handlers",function() local hud=Main.new(fake(),{layout={left_width=190,right_width=270}}); eq(hud:healthCheck(),nil); hud:start(); eq(hud:healthCheck(),true) end)
