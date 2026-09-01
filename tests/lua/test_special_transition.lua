local MapperModel=require("mapper_model")
local Special=require("special_transition")

local function fakeTimerAdapter()
  local adapter={timers={},nextTimer=0}
  function adapter:schedule(delay,callback)
    self.nextTimer=self.nextTimer+1
    local id="special-timer-"..self.nextTimer
    self.timers[id]={delay=delay,callback=callback}
    return id
  end
  function adapter:cancelTimer(id)
    if self.cancelError then return nil,self.cancelError end
    self.timers[id]=nil
    return true
  end
  function adapter:fireOnlyTimer()
    for id,timer in pairs(self.timers) do
      self.timers[id]=nil
      timer.callback()
      return
    end
  end
  function adapter:timerCount()
    local count=0
    for _ in pairs(self.timers) do count=count+1 end
    return count
  end
  return adapter
end

test("confirms the final eligible non-direction command from canonical rooms",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("open gate",100)); assert(tracker:onOutgoing("go gate",100))
  eq(tracker:onRoom(100),nil)
  local transition=assert(tracker:onRoom(900))
  eq(transition.from,100); eq(transition.to,900); eq(transition.command,"go gate")
  eq(tracker:pending(),nil)
end)

test("preserves exact trimmed command bytes while classifying with a lowercase copy",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  eq(tracker:onOutgoing("  NoRtH  ",100),nil)
  eq(tracker:onOutgoing("  DGHUD UPDATE  ",100),nil)
  assert(tracker:onOutgoing("  Open RuneDoor --Sigil=Ä  ",100))
  local transition=assert(tracker:onRoom(900))
  eq(transition.command,"Open RuneDoor --Sigil=Ä")
end)

test("directions controls and expired candidates never become special exits",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  eq(tracker:onOutgoing("north",100),nil)
  eq(tracker:onOutgoing("dghud update",100),nil)
  assert(tracker:onOutgoing("climb rope",100)); adapter:fireOnlyTimer()
  eq(tracker:onRoom(900),nil)
end)

test("excludes every explicit non-travel control and its argument forms",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  local controls={"dghud","walkto","walkstop","mapcenter","inventory","inv","stat","info","look","l","who","say","whisper","link"}
  for _,command in ipairs(controls) do
    eq(tracker:onOutgoing(command,100),nil)
    eq(tracker:onOutgoing(command.." example",100),nil)
  end
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
end)

test("replacement disconnect and cancellation failures clear candidate ownership",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("enter tunnel",100)); assert(tracker:cancel("disconnect"))
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
  adapter.cancelError="cancel exploded"; assert(tracker:onOutgoing("climb rope",100))
  local ok,err=tracker:cancel("shutdown"); eq(ok,nil); assert(err:find("cancel exploded",1,true))
  eq(tracker:pending(),nil)

  adapter=fakeTimerAdapter(); tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("enter tunnel",100))
  function adapter:cancelTimer() error("cancel threw") end
  ok,err=tracker:cancel("shutdown"); eq(ok,nil); assert(err:find("cancel threw",1,true))
  eq(tracker:pending(),nil)
end)

test("replacement cancellation failure is bounded aborts replacement and leaves stale callback inert",function()
  local adapter=fakeTimerAdapter(); local statuses={}
  local tracker=Special.new(MapperModel,adapter,3,function(kind) statuses[#statuses+1]=kind end)
  assert(tracker:onOutgoing("enter tunnel",100))
  local oldTimer=tracker.timer; local staleCallback=adapter.timers[oldTimer].callback
  adapter.cancelError="cancel rejected "..string.rep("x",500)
  local ok,err=tracker:onOutgoing("Open New Door",100)
  eq(ok,nil); eq(err:find("special transition replacement cancellation failed",1,true),1); eq(#err<=200,true)
  eq(tracker:pending(),nil); eq(tracker.timer,nil); eq(adapter.nextTimer,1)

  adapter.cancelError=nil
  assert(tracker:onOutgoing("Open Final Door",100))
  local replacementTimer=tracker.timer
  staleCallback()
  eq(tracker:pending().command,"Open Final Door"); eq(tracker.timer,replacementTimer)
  eq(statuses[#statuses],nil)
end)

test("timer creation failures never leave pending candidates",function()
  local adapter=fakeTimerAdapter(); function adapter:schedule() return nil,"schedule failed" end
  local tracker=Special.new(MapperModel,adapter,3)
  local ok,err=tracker:onOutgoing("climb rope",100)
  eq(ok,nil); eq(err,"schedule failed"); eq(tracker:pending(),nil)

  function adapter:schedule() error("schedule exploded") end
  ok,err=tracker:onOutgoing("enter tunnel",100)
  eq(ok,nil); assert(err:find("schedule exploded",1,true)); eq(tracker:pending(),nil)
end)

test("shutdown cancels the owned timer",function()
  local adapter=fakeTimerAdapter(); local tracker=Special.new(MapperModel,adapter,3)
  assert(tracker:onOutgoing("climb rope",100)); assert(tracker:shutdown())
  eq(tracker:pending(),nil); eq(adapter:timerCount(),0)
end)

test("reports lifecycle status only when a candidate changes",function()
  local adapter=fakeTimerAdapter(); local statuses={}
  local tracker=Special.new(MapperModel,adapter,3,function(kind) statuses[#statuses+1]=kind end)
  eq(tracker:onOutgoing("north",100),nil); eq(tracker:onOutgoing("dghud update",100),nil)
  eq(#statuses,0)
  assert(tracker:onOutgoing("open gate",100)); assert(tracker:onOutgoing("go gate",100))
  eq(#statuses,1); eq(statuses[1],"replaced")
  adapter:fireOnlyTimer(); eq(#statuses,2); eq(statuses[2],"expired")
end)
