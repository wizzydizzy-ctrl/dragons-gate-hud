local Main=require("main")
local function fake()
  local f={next=0,killed={},deleted=0,borders={10,20,30,40},set_borders={},callbacks={},layouts={}}
  function f:getBorders() return self.borders[1],self.borders[2],self.borders[3],self.borders[4] end
  function f:setBorders(a,b,c,d) self.set_borders={a,b,c,d} end
  function f:getWindowSize() return self.width or 1920,self.height or 1080 end
  function f:createView() return {update=function(self,state) self.state=state end,applyLayout=function(self,layout) f.layouts[#f.layouts+1]=layout end,delete=function() f.deleted=f.deleted+1 end} end
  function f:addEvent(name,fn) self.next=self.next+1; self.callbacks[name]=fn; return "event-"..self.next end
  function f:addAlias() self.next=self.next+1; return "alias-"..self.next end
  function f:killEvent(id) self.killed[id]=true end
  function f:killAlias(id) self.killed[id]=true end
  function f:getGMCP() return {Char={Vitals={hp=1,hp_max=1}}} end
  return f
end
test("startup is idempotent and shutdown owns exact runtime IDs",function()
  local f=fake(); local hud=Main.new(f,{layout={left_width=190,right_width=270}}); eq(hud:start(),true); local first=f.next; eq(hud:start(),true); eq(f.next,first); eq(hud:shutdown(),true); eq(f.deleted,1); eq(f.set_borders[1],0); eq(f.set_borders[2],0); for i=1,first do eq(f.killed[(i<=6 and "event-" or "alias-")..i],true) end
end)
test("health check requires root and handlers",function() local hud=Main.new(fake(),{layout={left_width=190,right_width=270}}); eq(hud:healthCheck(),nil); hud:start(); eq(hud:healthCheck(),true) end)
test("window resize recomputes absolute borders and view layout",function()
  local f=fake(); f.borders={1290,234,1610,120}; local hud=Main.new(f,{layout={}}); hud:start(); eq(f.layouts[#f.layouts].mode,"wide"); eq(f.set_borders[1],250); eq(f.set_borders[2],74); eq(f.set_borders[3],326); eq(f.set_borders[4],38); f.width=760; f.height=700; f.callbacks["sysWindowResizeEvent"](); eq(f.layouts[#f.layouts].mode,"compact"); eq(f.set_borders[1],0); eq(f.set_borders[2],116); eq(f.set_borders[3],0); eq(f.set_borders[4],58)
end)
