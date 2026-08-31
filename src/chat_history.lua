local History={}
History.__index=History

local private={WHISPER=true,ESP=true,DRAGON=true,CONTACT=true}

local function normalized(value)
  return tostring(value or ""):lower():match("^%s*(.-)%s*$"):gsub("%s+"," ")
end

local function key(entry)
  return table.concat({normalized(entry.category),normalized(entry.speaker),normalized(entry.target),normalized(entry.message)},"\0")
end

function History.new(limit,dedupeSeconds)
  return setmetatable({limit=math.max(1,math.floor(tonumber(limit) or 1000)),dedupeSeconds=math.max(0,tonumber(dedupeSeconds) or 3),items={},categoryOrder={},knownCategories={}},History)
end

function History:append(entry,epoch)
  if type(entry)~="table" then return false end
  epoch=tonumber(epoch) or os.time()
  local entryKey=key(entry)
  local elapsed=epoch-(self.lastEpoch or epoch)
  if self.lastKey==entryKey and elapsed>=0 and elapsed<=self.dedupeSeconds then return false end
  self.lastKey=entryKey
  self.lastEpoch=epoch
  self.items[#self.items+1]=entry
  while #self.items>self.limit do table.remove(self.items,1) end
  local category=tostring(entry.category or ""):upper()
  if category~="" and not self.knownCategories[category] then
    self.knownCategories[category]=true
    self.categoryOrder[#self.categoryOrder+1]=category
  end
  return true
end

function History:entries(filter)
  filter=tostring(filter or "ALL"):upper()
  local entries={}
  for _,entry in ipairs(self.items) do
    local category=tostring(entry.category or ""):upper()
    if filter=="ALL" or category==filter or (filter=="PRIVATE" and private[category]) then entries[#entries+1]=entry end
  end
  return entries
end

function History:categories()
  local categories={}
  for index,category in ipairs(self.categoryOrder) do categories[index]=category end
  return categories
end

return History
