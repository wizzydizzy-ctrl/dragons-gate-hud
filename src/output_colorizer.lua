local Colorizer={}; Colorizer.__index=Colorizer

local defaultColors={room={224,184,79},label={139,45,45},direction={191,91,33},gold={224,184,79},silver={192,192,192}}
local directions={north=true,northeast=true,east=true,southeast=true,south=true,southwest=true,west=true,northwest=true,up=true,down=true,['in']=true,out=true,n=true,ne=true,e=true,se=true,s=true,sw=true,w=true,nw=true,u=true,d=true}

local function segment(first,last,kind,colors)
  return {start=first,length=last-first+1,kind=kind,color=colors[kind]}
end

function Colorizer.parse(line,colors)
  colors=colors or defaultColors
  if type(line)~="string" or line=="" then return nil end
  local first,last=line:find("%[[^%[%]\r\n]+%]")
  if first and line:sub(1,first-1):match("^%s*$") and line:sub(last+1):match("^%s*$") then
    return {segment(first,last,"room",colors)}
  end
  local lower=line:lower()
  local labelFirst,labelLast=lower:find("obvious%s+exits%s*:")
  if not labelFirst then labelFirst,labelLast=lower:find("obvious%s+paths%s*:") end
  local result={}
  local cursor=1
  local validLabel=labelFirst and line:sub(1,labelFirst-1):match("^%s*$")
  if validLabel then
    result[#result+1]=segment(labelFirst,labelLast,"label",colors)
    cursor=labelLast+1
  end
  while true do
    local wordFirst,wordLast=line:find("%a+",cursor)
    if not wordFirst then break end
    local word=line:sub(wordFirst,wordLast):lower()
    if validLabel and directions[word] then result[#result+1]=segment(wordFirst,wordLast,"direction",colors)
    elseif word=="gold" or word=="gp" then result[#result+1]=segment(wordFirst,wordLast,"gold",colors)
    elseif word=="silver" or word=="sp" then result[#result+1]=segment(wordFirst,wordLast,"silver",colors) end
    cursor=wordLast+1
  end
  return #result>0 and result or nil
end

function Colorizer.new(adapter,enabled,settings)
  settings=type(settings)=="table" and settings or {}
  local colors={room=settings.room_color or defaultColors.room,label=settings.label_color or defaultColors.label,direction=settings.direction_color or defaultColors.direction,gold=settings.gold_color or defaultColors.gold,silver=settings.silver_color or defaultColors.silver}
  local features={room=settings.room_enabled~=false,exits=settings.exits_enabled~=false,currency=settings.currency_enabled~=false}
  return setmetatable({adapter=adapter,enabled=enabled==true,colors=colors,features=features,trigger=nil,started=false},Colorizer)
end
function Colorizer:start()
  if self.started then return true end
  local ok,id=pcall(self.adapter.addColorizerTrigger,self.adapter,function(line) return self:onLine(line) end)
  if not ok then return nil,tostring(id) end
  if not id then return nil,"colorizer trigger registration failed" end
  self.trigger=id; self.started=true; return true
end
function Colorizer:onLine(line)
  if not self.started or not self.enabled then return false end
  local segments=Colorizer.parse(line,self.colors)
  if not segments then return false end
  local filtered={}
  for _,item in ipairs(segments) do
    if (item.kind=="room" and self.features.room) or ((item.kind=="label" or item.kind=="direction") and self.features.exits) or ((item.kind=="gold" or item.kind=="silver") and self.features.currency) then filtered[#filtered+1]=item end
  end
  if #filtered==0 then return false end
  local ok,applied,err=pcall(self.adapter.applyLineColors,self.adapter,filtered)
  if not ok then return nil,tostring(applied) end
  if not applied then return nil,err or "line coloring failed" end
  return true
end
function Colorizer:setEnabled(enabled) self.enabled=enabled==true; return self.enabled end
function Colorizer:setFeature(name,enabled)
  if self.features[name]==nil then return nil,"unknown color feature" end
  self.features[name]=enabled==true; return self.features[name]
end
function Colorizer:toggle() return self:setEnabled(not self.enabled) end
function Colorizer:status() return {enabled=self.enabled,started=self.started,trigger=self.trigger,room=self.features.room,exits=self.features.exits,currency=self.features.currency} end
function Colorizer:shutdown()
  local id=self.trigger; self.trigger=nil; self.started=false
  if id then local ok,err=pcall(self.adapter.killTrigger,self.adapter,id); if not ok then return nil,tostring(err) end end
  return true
end

return Colorizer
