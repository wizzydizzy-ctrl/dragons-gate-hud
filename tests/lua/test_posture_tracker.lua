local Posture=require("posture_tracker")
local function fake()
  local f={published={}}
  function f:setPostureVariables(state) self.published[#self.published+1]={standing=state.standing,sitting=state.sitting,unconscious=state.unconscious} end
  return f
end

test("posture starts unknown and confirmed messages are mutually exclusive",function()
  local f=fake(); local p=Posture.new(f)
  eq(p:status().standing,nil); eq(p:status().sitting,nil)
  assert(p:onLine("prompt> You sit down beside the fire.")); eq(p:status().sitting,true); eq(p:status().standing,false)
  assert(p:onLine("You stand up.")); eq(p:status().standing,true); eq(p:status().sitting,false)
end)

test("prone and pass-out messages intentionally map to sitting",function()
  for _,line in ipairs({"You lie down.","You stumble and fall down!","You fall back and lie down.","You pass out!","You pass out from blood loss.","You pass out from the drain!","You faint dead away.","You lose consciousness."}) do
    local f=fake(); local p=Posture.new(f); assert(p:onLine(line)); eq(p:status().sitting,true); eq(p:status().standing,false)
  end
end)

test("informational balance lines do not change posture",function()
  local p=Posture.new(fake())
  for _,line in ipairs({"You are thrown off balance!","You are knocked back!","You fall...","You must stand up first!"}) do eq(p:onLine(line),false) end
  eq(p:status().standing,nil); eq(p:status().sitting,nil)
end)

test("unconscious state is tracked independently",function()
  local p=Posture.new(fake()); assert(p:onLine("You fall asleep.")); eq(p:status().unconscious,true); eq(p:status().sitting,nil)
  assert(p:onLine("You regain consciousness.")); eq(p:status().unconscious,false)
end)
