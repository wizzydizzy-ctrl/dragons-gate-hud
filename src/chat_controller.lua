local Controller={}
Controller.__index=Controller

local function call(object,name,...)
  if type(object)~="table" or type(object[name])~="function" then return nil end
  local ok,first,second=pcall(object[name],object,...)
  if not ok then return nil,tostring(first) end
  return first,second
end

function Controller.new(adapter,parser,history,storage,onChange,characterProvider)
  return setmetatable({adapter=adapter,parser=parser,history=history,storage=storage,onChange=onChange or function() end,characterProvider=characterProvider or function() end,filter="ALL",started=false},Controller)
end

function Controller:character()
  local ok,value=pcall(self.characterProvider)
  return ok and value or nil
end

function Controller:notify()
  pcall(self.onChange,self:entries(),self.history:categories(),self.filter)
end

function Controller:entries()
  return self.history:entries(self.filter)
end

function Controller:reportStorageError(message)
  if self.reportedStorageError then return end
  self.reportedStorageError=true
  call(self.adapter,"reportChatErrorOnce",message or "could not access chat log")
end

function Controller:accept(entry)
  local added=self.history:append(entry,call(self.adapter,"epoch"))
  if not added then return false end
  local ok,err=call(self.storage,"append",entry)
  if not ok then self:reportStorageError(err or "could not append chat log") end
  self:notify()
  return true
end

function Controller:start()
  if self.started then return true end
  local recent,loadErr=call(self.storage,"loadRecent",self:character())
  if loadErr then self:reportStorageError(loadErr) end
  for _,entry in ipairs(type(recent)=="table" and recent or {}) do self.history:append(entry,-math.huge) end
  local trigger,triggerErr=call(self.adapter,"addLineTrigger",function(line) self:onLine(line) end)
  if not trigger then return nil,triggerErr or "could not register chat trigger" end
  self.trigger=trigger
  self.started=true
  self:notify()
  return true
end

function Controller:onLine(line)
  if not self.started then return nil,"chatbox is not running" end
  local entry=self.parser.parse(line,self:character(),call(self.adapter,"timestamp"))
  if entry then return self:accept(entry) end
  return false
end

function Controller:capture(category,text,metadata)
  if not self.started then return nil,"chatbox is not running" end
  local entry,err=self.parser.custom(category,text,metadata,self:character(),call(self.adapter,"timestamp"))
  if not entry then return nil,err end
  local accepted=self:accept(entry)
  return accepted==false and true or accepted
end

function Controller:setFilter(filter)
  if not self.started then return nil,"chatbox is not running" end
  filter=self.parser.category(filter)
  if not filter then return nil,"invalid chat category" end
  self.filter=filter
  self:notify()
  return true
end

function Controller:shutdown()
  self.started=false
  local trigger=self.trigger; self.trigger=nil; local storage=self.storage
  if trigger then call(self.adapter,"killTrigger",trigger) end
  if storage then call(storage,"close") end
  return true
end

return Controller
