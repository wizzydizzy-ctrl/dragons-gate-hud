local Navigation=require("navigation")
local Layout=require("layout")
local View={}; View.__index=View
function View.withFont(text,size) return "<span style='font-size:"..tonumber(size).."px'>"..text.."</span>" end
function View.raiseCards(cards) for _,card in ipairs(cards or {}) do if card and card.raise then card:raise() end end end
local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
local function safeText(v) return esc(tostring(v or ""):gsub("%c"," ")) end
local function safeChatText(v) return tostring(v or ""):gsub("%c"," ") end
local chat_colors={ROOM="text",OWN="jade",WHISPER="#d49bc8",ESP="#a6a3e8",DRAGON="#d9a869",CONTACT="#8bc6b0",STAFF="#e09672"}
local function chatScroll(output,ranges)
  local okCurrent,current=pcall(function() return output:getScroll() end)
  local okLast,last=pcall(function() return output:getLastLineNumber() end)
  if not okCurrent or not okLast or current==nil or last==nil then return {at_bottom=true,line=0} end
  local state={at_bottom=current>=last,line=current}
  if not state.at_bottom then
    for index,range in ipairs(ranges or {}) do
      if current>=range.first and current<=range.last then
        state.entry=range.entry; state.index=index; state.offset=current-range.first; break
      end
    end
  end
  return state
end
local function restoreChatScroll(output,state,ranges)
  if state.at_bottom then pcall(function() output:scrollTo() end); return end
  local ok,last=pcall(function() return output:getLastLineNumber() end)
  local line=state.line
  for index,range in ipairs(ranges or {}) do
    if range.entry==state.entry or (state.entry==nil and index==state.index) then
      line=range.first+math.min(math.max(0,state.offset or 0),range.last-range.first); break
    end
  end
  pcall(function() output:scrollTo(math.min(line,(ok and tonumber(last)) or line)) end)
end
function View.chatLine(entry,t,timestamps)
  entry=type(entry)=="table" and entry or {}
  local category=tostring(entry.category or "CHAT"):upper()
  local color=chat_colors[category] or t.accent
  if color=="text" then color=t.text elseif color=="jade" then color=t.jade end
  local stamp=""
  if timestamps~=false then
    local time=tostring(entry.timestamp or ""):match("T(%d%d:%d%d)")
    if time then stamp="#"..t.muted:gsub("^#","").."["..time.."]#r " end
  end
  local prefix=stamp.."#"..tostring(color):gsub("^#","")..safeText(category).."#r"
  return prefix," "..safeChatText(entry.line or entry.message).."\n"
end
function View.identityContent(character,t,layout)
  local physical=character.physical or {}; local detail=""
  if physical.age or physical.sex or physical.height then detail="<br><span style='color:"..t.muted.."'>"..esc(physical.age or "")..(physical.age and " · " or "")..esc(physical.sex or "")..(physical.height and " · "..esc(physical.height) or "").."</span>" end
  local faith=""; if character.deity or character.religion then
    local values={}; for _,value in ipairs({character.religion,character.deity}) do if value and value~="" then values[#values+1]=esc(value) end end
    faith="<br><span style='color:"..t.muted.."'>"..table.concat(values," · ").."</span>"
    if character.religious_balance and character.religious_balance~="" then faith=faith.."<br><span style='color:"..t.muted.."'>"..esc(character.religious_balance).."</span>" end
  end
  return View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>"..esc(character.full_name).."</b></span><br><span style='color:"..t.jade.."'><b>"..esc(character.race).." · "..esc(character.class).."</b></span><br><span style='color:"..t.muted.."'>"..esc(character.alignment).."</span>"..detail..faith,layout.body_font)
end
function View.headerContent(layout,t,fullName)
  local detail=layout.mode=="compact" and " &nbsp; <span style='color:"..t.text.."'><b>"..esc(fullName).."</b></span>" or ""
  return View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>DRAGONS GATE</b></span>"..detail.."<br><span style='color:"..t.jade.."'><b>● LIVE</b></span>",layout.body_font)
end
function View.inventoryRows(items,capacity)
  items=items or {}; capacity=math.max(0,tonumber(capacity) or 0); local rows={}
  if #items<=capacity then for _,item in ipairs(items) do rows[#rows+1]=item end; return rows end
  local visible=math.max(0,capacity-1); for i=1,visible do rows[#rows+1]=items[i] end
  if capacity>0 then rows[#rows+1]={label="+"..(#items-visible).." more",overflow=#items-visible} end
  return rows
end
function View.detailsContent(combat,attributes,t,layout)
  combat=combat or {}; attributes=attributes or {}; local parts={}; local columns=layout.details_columns or 4
  if combat.body_armor then
    parts[#parts+1]="Armor <b>"..combat.body_armor.."%</b> &nbsp; OR <b>"..esc(combat.or_rating or "—").."</b> &nbsp; DR <b>"..esc(combat.dr or "—").."</b>"
    if combat.stance then if columns<=2 then parts[#parts+1]="Stance <b>"..esc(combat.stance).."</b>" else parts[#parts]=parts[#parts].." &nbsp; <b>"..esc(combat.stance).."</b>" end end
  elseif combat.stance then parts[#parts+1]="Stance <b>"..esc(combat.stance).."</b>" end
  local stats={}; for _,key in ipairs({"STR","INT","WIS","DEX","AGI","CON","CHA","WIL","VOI","PER","APP"}) do if attributes[key] then stats[#stats+1]=key.." <b>"..esc(attributes[key]).."</b>" end end
  for i=1,#stats,columns do local row={}; for n=i,math.min(i+columns-1,#stats) do row[#row+1]=stats[n] end; parts[#parts+1]=table.concat(row," &nbsp; ") end
  return View.withFont("<span style='color:"..t.accent.."'><b>CHARACTER &amp; COMBAT</b></span><br><br>"..table.concat(parts,"<br>"),layout.inventory_font or layout.body_font)
end
function View.equipmentContent(v,items,t,layout)
  if layout==nil then layout=t; t=items; items={} end
  local function ready(value) return value and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:#c85b4b'><b>NOT READY</b></span>" end
  local body="Weapon &nbsp; "..ready(v.weapon_readied).."<br>Shield &nbsp; "..ready(v.shield_readied)
  return View.withFont("<span style='color:"..t.accent.."'><b>EQUIPMENT</b></span><br><br>"..body,layout.body_font)
end
function View.wealthContent(v,t,layout)
  return View.withFont("<span style='color:"..t.accent.."'><b>WEALTH</b></span><br><br>Gold &nbsp; <b>"..v.gold.."</b><br>Silver &nbsp; <b>"..v.silver.."</b>",layout.body_font)
end
function View.statusContent(v,t,layout)
  local round=v.roundtime==0 and "READY" or v.roundtime
  return View.withFont("<span style='color:"..t.accent.."'><b>STATUS</b></span><br>Roundtime &nbsp; <b>"..round.."</b><br>Position &nbsp; <b>"..v.position.."</b>",layout.lower_body_font)
end
local function label(name,parent,style,geyser)
  local item=(geyser or Geyser).Label:new({name=name,x=0,y=0,width=10,height=10},parent); item:setStyleSheet(style or "background:transparent;"); return item
end
local function gauge(name,parent,color,theme)
  local g=Geyser.Gauge:new({name=name,x=0,y=0,width=100,height=18},parent)
  g.front:setStyleSheet("background:"..color..";border-radius:5px;"); g.back:setStyleSheet("background:#080b0a;border:1px solid "..theme.border..";border-radius:5px;"); g.text:setStyleSheet("background:transparent;color:"..theme.text..";font-size:11px;font-weight:600;")
  return g
end
local function place(item,x,y,w,h) item:move(x,y); item:resize(w,h); item:show() end
function View.new(settings)
  local self=setmetatable({settings=settings,geyser=Geyser,direction_buttons={},utility_buttons={},exit_available={}},View); local t=settings.theme
  self.root=Geyser.Container:new({name="DGHUD.Root",x=0,y=0,width="100%",height="100%"})
  self.header=label("DGHUD.Header",self.root,"background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px 18px;")
  self.chat_container=Geyser.Container:new({name="DGHUD.Chat",x=0,y=0,width=100,height=240},self.root)
  self.chat=self.chat_container
  self.chat_bg=label("DGHUD.Chat.Background",self.chat_container,"background:#0d1210;border:1px solid "..t.border..";")
  self.chat_tabs=Geyser.Container:new({name="DGHUD.Chat.Tabs",x=0,y=0,width="100%",height=32},self.chat_container)
  self.chat_output=Geyser.MiniConsole:new({name="DGHUD.Chat.Output",x=8,y=36,width="100%-16",height="100%-44"},self.chat_container)
  self.chat_output:enableScrollBar()
  self.chat_output:disableHorizontalScrollBar()
  self.left_bg=label("DGHUD.LeftBackground",self.root,"background:"..t.panel..";border-right:1px solid "..t.border..";")
  self.identity=label("DGHUD.Identity",self.root,"background:"..t.panel..";border-right:1px solid "..t.border..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.details=label("DGHUD.Details",self.root,"background:"..t.panel..";border:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.left=label("DGHUD.LeftRail",self.root,"background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.equipment=label("DGHUD.Equipment",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:14px;")
  self.wealth=label("DGHUD.Wealth",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:14px;")
  self.inventory=label("DGHUD.Inventory",self.root,"background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:14px;")
  self.right=Geyser.Container:new({name="DGHUD.RightRail",x=0,y=0,width=300,height=500},self.root)
  self.right_bg=label("DGHUD.RightBackground",self.right,"background:"..t.panel..";border-right:1px solid "..t.border..";")
  self.right_title=label("DGHUD.RightTitle",self.right,"background:transparent;color:"..t.accent..";font-size:13px;font-weight:700;padding:10px 14px;")
  self.hp=gauge("DGHUD.Health",self.right,t.hp,t); self.fatigue=gauge("DGHUD.Fatigue",self.right,t.fatigue,t); self.carry=gauge("DGHUD.Carry",self.right,"#c9a359",t); self.psi=gauge("DGHUD.Psi",self.right,"#6a72c9",t); self.web=gauge("DGHUD.Web",self.right,"#9b78b5",t)
  self.readiness=label("DGHUD.Readiness",self.right,"background:#131a16;border:1px solid #2b3731;border-radius:6px;color:"..t.text..";padding:9px 12px;")
  self.room=label("DGHUD.Room",self.right,"background:#101a16;border:1px solid #385044;border-radius:6px;color:"..t.text..";padding:10px 12px;")
  self.mapper_frame=label("DGHUD.MapperFrame",self.right,"background:#101713;border:1px solid "..t.border..";border-radius:7px;")
  self.mapper=self.geyser.Mapper:new({name="DGHUD.Mapper",x=4,y=4,width="100%-8",height="100%-8"},self.mapper_frame)
  self.compass_area=Geyser.Container:new({name="DGHUD.Compass",x=0,y=0,width=100,height=100},self.right)
  self.compass_center=label("DGHUD.Compass.Center",self.compass_area,"background:transparent;color:"..t.muted..";"); self.compass_center:echo("<center>◆</center>")
  for i,direction in ipairs(Navigation.directions) do local b=label("DGHUD.Compass."..direction.key,self.compass_area); b:setClickCallback(function() if self.exit_available[direction.key] then send(direction.command) end end); self.direction_buttons[i]={label=b,direction=direction} end
  self.utility_area=Geyser.Container:new({name="DGHUD.Utilities",x=0,y=0,width=100,height=60},self.right)
  for i,utility in ipairs(Navigation.utilities) do local b=label("DGHUD.Utility."..i,self.utility_area); b:setClickCallback(function() send(utility.command) end); self.utility_buttons[i]={label=b,utility=utility} end
  self.bottom=label("DGHUD.Bottom",self.root,"background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px 15px;")
  self.compact=label("DGHUD.Compact",self.root,"background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:8px 12px;")
  return self
end
local default_chat_filters={"ALL","ROOM","PRIVATE","ESP","DRAGON","CONTACT","STAFF"}
local reserved_chat_filters={ALL=true,ROOM=true,PRIVATE=true,ESP=true,DRAGON=true,CONTACT=true,STAFF=true,OWN=true,WHISPER=true}
local function chatFilterOrder(categories)
  local result={}; local seen={}
  for _,category in ipairs(default_chat_filters) do result[#result+1]=category; seen[category]=true end
  for _,value in ipairs(categories or {}) do
    local category=tostring(value or ""):upper()
    if category~="" and not reserved_chat_filters[category] and not seen[category] then result[#result+1]=category; seen[category]=true end
  end
  return result
end
local function chatTabWidth(category,font)
  return math.max(42,math.min(96,math.floor(#tostring(category)*(tonumber(font) or 13)*.55+18)))
end
function View:setChatFilterCallback(callback)
  self.chat_filter_callback=type(callback)=="function" and callback or nil
  return true
end
function View:renderChatTabs(categories,activeFilter)
  for _,button in ipairs(self.chat_buttons or {}) do if button.delete then button:delete() end end
  self.chat_buttons={}; self.chat_overflow_button=nil; self.chat_filter_order=chatFilterOrder(categories)
  local width=math.max(80,tonumber(self.layout and self.layout.chat_width) or 640)
  local font=tonumber(self.layout and self.layout.chat_font) or 13
  local gap,padding,overflowWidth=4,8,64
  local total=padding
  for _,category in ipairs(self.chat_filter_order) do total=total+chatTabWidth(category,font)+gap end
  local visible={}; local hidden={}
  if total+padding-gap<=width then
    for _,category in ipairs(self.chat_filter_order) do visible[#visible+1]=category end
  else
    local room=math.max(42,width-padding*2-overflowWidth-gap)
    local used=0
    for _,category in ipairs(self.chat_filter_order) do
      local needed=chatTabWidth(category,font)+(used>0 and gap or 0)
      if used+needed<=room or #visible==0 then visible[#visible+1]=category; used=used+needed else hidden[#hidden+1]=category end
    end
    local active=tostring(activeFilter or "ALL"):upper(); local activeHidden=false
    for _,category in ipairs(hidden) do if category==active then activeHidden=true; break end end
    if activeHidden and #visible>0 then visible[#visible]=active; hidden={}; local selected={}
      for _,category in ipairs(visible) do selected[category]=true end
      for _,category in ipairs(self.chat_filter_order) do if not selected[category] then hidden[#hidden+1]=category end end
    end
  end
  self.chat_overflow_categories=hidden
  local t=self.settings.theme; local x=padding; local active=tostring(activeFilter or "ALL"):upper()
  local maxNormal=width-padding-(#hidden>0 and overflowWidth+gap or 0)
  for _,category in ipairs(visible) do
    local remaining=maxNormal-x; if remaining<=0 then break end
    local button=label("DGHUD.Chat.Tab."..(#self.chat_buttons+1),self.chat_tabs,nil,self.geyser)
    local buttonWidth=math.min(chatTabWidth(category,font),remaining)
    place(button,x,4,buttonWidth,24); x=x+buttonWidth+gap
    local selected=category
    button.category=selected
    button:setStyleSheet("background:"..(selected==active and "#26382d" or "#121a16")..";border:1px solid "..(selected==active and t.jade or t.border)..";border-radius:4px;color:"..(selected==active and t.jade or t.muted)..";font-size:"..font.."px;")
    button:echo("<center><b>"..safeText(selected).."</b></center>")
    button:setClickCallback(function() if self.chat_filter_callback then self.chat_filter_callback(selected) end end)
    self.chat_buttons[#self.chat_buttons+1]=button
  end
  if #hidden>0 then
    local button=label("DGHUD.Chat.Tab.More",self.chat_tabs,nil,self.geyser); place(button,math.max(padding,width-padding-overflowWidth),4,overflowWidth,24)
    button:setStyleSheet("background:#121a16;border:1px solid "..t.border..";border-radius:4px;color:"..t.muted..";font-size:"..font.."px;")
    button:echo("<center><b>MORE "..#hidden.."</b></center>")
    button:setClickCallback(function()
      self.chat_overflow_cursor=((self.chat_overflow_cursor or 0)%#self.chat_overflow_categories)+1
      if self.chat_filter_callback then self.chat_filter_callback(self.chat_overflow_categories[self.chat_overflow_cursor]) end
    end)
    self.chat_overflow_button=button; self.chat_buttons[#self.chat_buttons+1]=button
  end
end
function View:applyLayout(layout)
  self.layout=layout; local top,bottom=layout.header_height or layout.top,layout.bottom; local t=self.settings.theme; local p=layout.panel_padding; local lp=layout.lower_panel_padding
  self.header:setStyleSheet("background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  self.identity:setStyleSheet("background:"..t.panel..";border-right:1px solid "..t.border..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.details:setStyleSheet("background:"..t.panel..";border:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.left:setStyleSheet("background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  for _,card in ipairs({self.equipment,self.wealth,self.inventory}) do card:setStyleSheet("background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;") end
  self.right_title:setStyleSheet("background:transparent;color:"..t.accent..";font-size:"..layout.lower_body_font.."px;font-weight:700;padding:"..lp.."px;")
  self.readiness:setStyleSheet("background:#131a16;border:1px solid #2b3731;border-radius:7px;color:"..t.text..";padding:"..lp.."px;font-size:"..layout.lower_body_font.."px;")
  self.room:setStyleSheet("background:#101a16;border:1px solid #385044;border-radius:7px;color:"..t.text..";padding:"..lp.."px;font-size:"..layout.lower_body_font.."px;")
  self.bottom:setStyleSheet("background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px "..p.."px;font-size:"..layout.small_font.."px;")
  self.compact:setStyleSheet("background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  for _,g in ipairs({self.hp,self.fatigue,self.carry,self.psi,self.web}) do g.text:setStyleSheet("background:transparent;color:"..t.text..";font-size:"..layout.lower_small_font.."px;font-weight:700;"); if g.text.setFontSize then g.text:setFontSize(layout.lower_small_font) end end
  place(self.header,0,0,"100%",top); self.bottom:hide()
  place(self.chat_container,layout.chat_x or layout.left,top,layout.chat_width or layout.console_width,layout.chat_height or 240)
  place(self.chat_bg,0,0,"100%","100%")
  place(self.chat_tabs,0,0,"100%",32)
  place(self.chat_output,layout.chat_padding or 8,36,"100%-"..((layout.chat_padding or 8)*2),"100%-44")
  if layout.mode=="wide" or layout.mode=="medium" then
    self.compact:hide()
    place(self.left_bg,0,top,layout.left,"100%-"..top)
    place(self.identity,0,top,layout.left,layout.identity_height)
    place(self.left,"100%-"..layout.right,top,layout.right,"100%-"..(top+bottom))
    local available=math.max(100,(layout.window_height or 800)-top-bottom)
    local psi_visible=self.last_state and self.last_state.vitals.psi.visible or false
    local web_visible=self.last_state and self.last_state.vitals.web.visible or false
    local lower=Layout.lowerPanelGeometry(layout,psi_visible,web_visible)
    local panel_height=math.min(available,lower.panel_height)
    layout.lower_geometry=lower
    place(self.right,0,"100%-"..(bottom+panel_height),layout.left,panel_height)
    local details_y=top+layout.identity_height+12; local vitals_y=(layout.window_height or 800)-bottom-panel_height; local details_h=vitals_y-details_y-12
    local details_placement=Layout.detailsPlacement(details_h,layout.details_line_height,layout.left)
    layout.details_columns=details_placement=="right" and 2 or 4
    if details_placement=="left" then place(self.details,0,details_y,layout.left,details_h) else self.details:hide() end
    local card_x="100%-"..(layout.right-p); local card_w=layout.right-p*2; local eq_rows=2
    local equipment_h=layout.heading_font+eq_rows*layout.details_line_height+p*2+18; local wealth_h=layout.heading_font+layout.details_line_height*2+p*2+18
    place(self.equipment,card_x,top+p,card_w,equipment_h); place(self.wealth,card_x,top+p+equipment_h+12,card_w,wealth_h)
    local inventory_y=top+p+equipment_h+wealth_h+24; local rail_bottom=(layout.window_height or 800)-bottom-p
    local minimum_inventory_h=layout.heading_font+layout.inventory_row_height+p*2+30
    if details_placement=="right" then
      local right_details_h=layout.details_line_height*Layout.detailsCardRows(layout.details_columns)+p*2+18
      if Layout.detailsFit(rail_bottom,inventory_y,right_details_h,minimum_inventory_h) then place(self.details,card_x,rail_bottom-right_details_h,card_w,right_details_h); rail_bottom=rail_bottom-right_details_h-12 else self.details:hide() end
    end
    local inventory_h=rail_bottom-inventory_y
    if inventory_h>=minimum_inventory_h then place(self.inventory,card_x,inventory_y,card_w,inventory_h); self.inventory_capacity=math.max(1,math.floor((inventory_h-layout.heading_font-p*2-30)/layout.inventory_row_height)) else self.inventory:hide(); self.inventory_capacity=0 end
    View.raiseCards({self.equipment,self.wealth,self.inventory,self.details})
  else
    self.left_bg:hide(); self.identity:hide(); self.details:hide(); self.left:hide(); self.equipment:hide(); self.wealth:hide(); self.inventory:hide(); self.mapper_frame:hide(); self.mapper:hide(); self.right:hide(); place(self.compact,0,62,"100%",top-62)
  end
  if layout.mode~="compact" then
    place(self.right_bg,0,0,"100%","100%"); self.right_title:hide()
    local panel_height=tonumber(self.right.height) or math.max(0,(layout.window_height or 800)-top-bottom)
    local lower=layout.lower_geometry or Layout.lowerPanelGeometry(layout,false,false)
    local inset=lp; local y=layout.lower_title_height; for _,g in ipairs({self.hp,self.fatigue,self.carry}) do place(g,inset,y,"100%-"..(inset*2),layout.lower_gauge_height); y=y+layout.lower_gauge_height+layout.lower_row_gap end
    if lower.show_psi then place(self.psi,inset,y,"100%-"..(inset*2),layout.lower_gauge_height); y=y+layout.lower_gauge_height+layout.lower_row_gap else self.psi:hide() end
    if lower.show_web then place(self.web,inset,y,"100%-"..(inset*2),layout.lower_gauge_height); y=y+layout.lower_gauge_height+layout.lower_row_gap else self.web:hide() end
    place(self.readiness,inset,y+3,"100%-"..(inset*2),lower.status_height)
    local compass_h,utility_h=lower.compass_height,lower.utility_height
    local utility_y,compass_y=lower.utility_y,lower.compass_y
    local mapper_h,mapper_y=lower.mapper_height,lower.mapper_y
    local content_top=y+lower.status_height+13
    local room_h=lower.room_height
    layout.lower_room_visible_height=room_h
    if room_h>0 then place(self.room,inset,content_top,"100%-"..(inset*2),room_h) else self.room:hide() end
    if layout.mapper_visible and mapper_h>0 then
      place(self.mapper_frame,inset,mapper_y,"100%-"..(inset*2),mapper_h)
      place(self.mapper,4,4,"100%-8","100%-8"); self.mapper:raise()
    else self.mapper_frame:hide(); self.mapper:hide() end
    place(self.compass_area,inset,compass_y,"100%-"..(inset*2),compass_h); self.compass_area:raise()
    local cell_width=33.333; for _,entry in ipairs(self.direction_buttons) do local d=entry.direction; place(entry.label,(d.col-1)*cell_width.."%",(d.row-1)*layout.lower_compass_cell,cell_width.."%",layout.lower_compass_cell) end
    place(self.compass_center,cell_width.."%",layout.lower_compass_cell,cell_width.."%",layout.lower_compass_cell)
    place(self.utility_area,inset,utility_y,"100%-"..(inset*2),utility_h); self.utility_area:raise()
    for i,entry in ipairs(self.utility_buttons) do local col=(i-1)%2; local row=math.floor((i-1)/2); place(entry.label,(col*50).."%",row*(layout.lower_utility_height+2),"49%",layout.lower_utility_height) end
  end
  self:applyChatWrap(layout)
end
function View:setMapCenterCallback(callback) self.map_center_callback=type(callback)=="function" and callback or nil; return true end
function View:centerMap(roomID)
  if not self.map_center_callback then return nil,"map center callback is unavailable" end
  return self.map_center_callback(roomID)
end
function View:renderNavigation(exits)
  if not self.layout or self.layout.mode=="compact" then return end
  local t=self.settings.theme; self.exit_available=Navigation.availability(exits)
  for _,entry in ipairs(self.direction_buttons) do local active=self.exit_available[entry.direction.key]; entry.label:setStyleSheet("background:"..(active and "#193024" or "rgba(16,23,19,0.28)")..";border:1px solid "..(active and "#5d9b71" or "#273029")..";border-radius:5px;color:"..(active and "#b8efc2" or "#536058")..";font-weight:700;"); entry.label:echo(View.withFont("<center><b>"..entry.direction.label.."</b></center>",self.layout.lower_compass_font)) end
  for _,entry in ipairs(self.utility_buttons) do entry.label:setStyleSheet("background:#17231c;border:1px solid #385044;border-radius:5px;color:"..t.jade..";font-weight:700;"); entry.label:echo(View.withFont("<center><b>"..entry.utility.label.."</b></center>",self.layout.lower_utility_font)) end
end
function View:renderInventory(s)
  local t=self.settings.theme; local layout=self.layout; if not layout or layout.mode=="compact" then return end
  local rows=View.inventoryRows(s.inventory.items,self.inventory_capacity or 0); local lines={"<span style='color:"..t.accent.."'><b>INVENTORY</b></span>"}
  for _,item in ipairs(rows) do if item.overflow then lines[#lines+1]="<span style='color:"..t.muted.."'>"..item.label.."</span>" else lines[#lines+1]=esc(item.name).." <span style='color:"..t.muted.."'>"..esc(item.weight or "").." lb</span>" end end
  if s.inventory.total_weight then lines[#lines+1]="<br><b>Total "..esc(s.inventory.total_weight).." lb</b>" end
  self.inventory:echo(View.withFont(table.concat(lines,"<br>"),layout.inventory_font))
end
function View:renderChat(entries,categories,activeFilter,savedScroll)
  entries=type(entries)=="table" and entries or {}; categories=type(categories)=="table" and categories or {}
  local state=savedScroll or chatScroll(self.chat_output,self.chat_line_ranges); local first=math.max(1,#entries-999)
  self.chat_entries={}; for index=first,#entries do self.chat_entries[#self.chat_entries+1]=entries[index] end
  self.chat_categories={}; for index,value in ipairs(categories) do self.chat_categories[index]=value end
  self.chat_active_filter=tostring(activeFilter or "ALL"):upper()
  self:renderChatTabs(self.chat_categories,self.chat_active_filter)
  self.chat_output:clear()
  local chatSettings=self.settings.chat or {}
  self.chat_line_ranges={}
  for index,entry in ipairs(self.chat_entries) do
    local okBefore,before=pcall(function() return self.chat_output:getLastLineNumber() end)
    local prefix,message=View.chatLine(entry,self.settings.theme,chatSettings.timestamps)
    self.chat_output:hecho(prefix)
    self.chat_output:echo(message)
    local okAfter,after=pcall(function() return self.chat_output:getLastLineNumber() end)
    before=okBefore and tonumber(before) or 0; after=okAfter and tonumber(after) or before
    self.chat_line_ranges[index]={entry=entry,first=before+1,last=math.max(before+1,after)}
  end
  restoreChatScroll(self.chat_output,state,self.chat_line_ranges)
  return true
end
local function chatFontWidth(output)
  if type(output.calcFontSize)=="function" then
    local ok,width=pcall(output.calcFontSize,output)
    width=ok and tonumber(width) or nil
    if width and width>0 then return width end
  end
  local calculator=rawget(_G,"calcFontSize")
  if type(calculator)=="function" and output.name then
    local ok,width=pcall(calculator,output.name)
    width=ok and tonumber(width) or nil
    if width and width>0 then return width end
  end
end
local function chatConsoleWidth(output,layout)
  if type(output.get_width)=="function" then
    local ok,width=pcall(output.get_width,output)
    width=ok and tonumber(width) or nil
    if width and width>0 then return width end
  end
  return math.max(1,(tonumber(layout.chat_width) or 1)-(2*(tonumber(layout.chat_padding) or 0)))
end
local function liveChatColumns(output,layout)
  local fontWidth=chatFontWidth(output)
  if not fontWidth then return math.max(30,math.floor(tonumber(layout.chat_wrap_columns) or 30)) end
  local allowance=output.scrollBar==false and 0 or (tonumber(layout.chat_scrollbar_allowance) or 15)
  local width=math.max(1,chatConsoleWidth(output,layout)-allowance)
  return math.max(1,math.floor(width/fontWidth)),fontWidth
end
function View:applyChatWrap(layout)
  layout=layout or self.layout or {}; local output=self.chat_output
  local font=math.max(1,math.floor(tonumber(layout.chat_font) or 13))
  local previousState=chatScroll(output,self.chat_line_ranges)
  pcall(function() output:setFontSize(font) end)
  local columns,fontWidth=liveChatColumns(output,layout)
  local changed=self.chat_wrap_columns~=columns or self.chat_font~=font
  local state=changed and previousState or nil
  local ok,applied,why=pcall(function() return output:setWrap(columns) end)
  if not ok then return nil,tostring(applied) end
  if applied==false or (applied==nil and why~=nil) then return nil,tostring(why or "could not apply chat wrap") end
  self.chat_wrap_columns=columns; self.chat_font=font; self.chat_character_width=fontWidth
  if changed then
    if self.chat_entries then self:renderChat(self.chat_entries,self.chat_categories,self.chat_active_filter,state)
    else restoreChatScroll(output,state,self.chat_line_ranges) end
  end
  return true
end
function View:update(s)
  self.last_state=s; local t=self.settings.theme; local v=s.vitals; local layout=self.layout or {mode="wide",heading_font=20}; local ready=function(x) return x and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:"..t.hp.."'><b>NOT READY</b></span>" end
  self.header:echo(View.headerContent(layout,t,s.character.full_name))
  self.identity:echo(View.identityContent(s.character,t,layout))
  self.equipment:echo(View.equipmentContent(v,s.equipment.items,t,layout)); self.wealth:echo(View.wealthContent(v,t,layout))
  self.hp:setValue(v.hp.current,math.max(v.hp.maximum,1),"Health  "..v.hp.current.." / "..v.hp.maximum); self.fatigue:setValue(v.fatigue.current,math.max(v.fatigue.maximum,1),"Fatigue  "..v.fatigue.current.." / "..v.fatigue.maximum); self.carry:setValue(v.carry.current,math.max(v.carry.maximum,1),"Carry  "..v.carry.current.." / "..v.carry.maximum)
  if v.psi.visible then self.psi:setValue(v.psi.current,v.psi.maximum,"PSI  "..v.psi.current.." / "..v.psi.maximum) end; if v.web.visible then self.web:setValue(v.web.current,v.web.maximum,"Web  "..v.web.current.." / "..v.web.maximum) end
  self.readiness:echo(View.statusContent(v,t,layout))
  self.room:echo(View.withFont("<span style='color:"..t.accent..";font-size:"..layout.lower_heading_font.."px'><b>"..esc(s.room.name).."</b></span><br><span style='color:"..t.muted.."'>Room "..esc(s.room.num or "—").." · Area "..esc(s.room.area or "—").."</span><br><br>"..esc(s.room.environment).."<br>Players &nbsp; <b>"..#s.room.players.."</b><br>Flags &nbsp; "..esc(table.concat(s.room.flags,", ")),layout.lower_body_font))
  self.compact:echo(View.withFont("<b>HP "..v.hp.current.."/"..v.hp.maximum.."</b> &nbsp; FAT "..v.fatigue.current.."/"..v.fatigue.maximum.." &nbsp; WPN "..(v.weapon_readied and "✓" or "×").." &nbsp; SHD "..(v.shield_readied and "✓" or "×").." &nbsp; <span style='color:"..t.accent.."'>"..esc(s.room.name).."</span>",layout.body_font))
  self.bottom:echo(View.withFont("EXITS &nbsp; <b>"..esc(table.concat(s.room.exits,", ")).."</b> &nbsp;&nbsp; | &nbsp;&nbsp; CARRY &nbsp; <b>"..v.carry.current.." / "..v.carry.maximum.."</b> &nbsp;&nbsp; | &nbsp;&nbsp; ROUND &nbsp; <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b>",layout.small_font))
  if self.layout then self:applyLayout(self.layout); self.details:echo(View.detailsContent(s.combat,s.attributes,t,self.layout)); self:renderInventory(s); self:renderNavigation(s.room.exits) end
end
function View:delete() if self.root then self.root:delete(); self.root=nil end end
return View
