local Navigation=require("navigation")
local Layout=require("layout")
local View={}; View.__index=View
function View.withFont(text,size) return "<span style='font-size:"..tonumber(size).."px'>"..text.."</span>" end
local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
function View.identityContent(character,t,layout)
  local physical=character.physical or {}; local detail=""
  if physical.age or physical.sex or physical.height then detail="<br><span style='color:"..t.muted.."'>"..esc(physical.age or "")..(physical.age and " · " or "")..esc(physical.sex or "")..(physical.height and " · "..esc(physical.height) or "").."</span>" end
  local faith=""; if character.deity or character.religion then faith="<br><span style='color:"..t.muted.."'>"..esc(character.deity or character.religion).."</span>" end
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
  local body
  if items and #items>0 then local lines={}; for _,item in ipairs(items) do lines[#lines+1]=esc(item) end; body=table.concat(lines,"<br>")
  else body="Weapon &nbsp; "..ready(v.weapon_readied).."<br>Shield &nbsp; "..ready(v.shield_readied) end
  return View.withFont("<span style='color:"..t.accent.."'><b>EQUIPMENT</b></span><br><br>"..body,layout.body_font)
end
function View.wealthContent(v,t,layout)
  return View.withFont("<span style='color:"..t.accent.."'><b>WEALTH</b></span><br><br>Gold &nbsp; <b>"..v.gold.."</b><br>Silver &nbsp; <b>"..v.silver.."</b>",layout.body_font)
end
local function label(name,parent,style)
  local item=Geyser.Label:new({name=name,x=0,y=0,width=10,height=10},parent); item:setStyleSheet(style or "background:transparent;"); return item
end
local function gauge(name,parent,color,theme)
  local g=Geyser.Gauge:new({name=name,x=0,y=0,width=100,height=18},parent)
  g.front:setStyleSheet("background:"..color..";border-radius:5px;"); g.back:setStyleSheet("background:#080b0a;border:1px solid "..theme.border..";border-radius:5px;"); g.text:setStyleSheet("background:transparent;color:"..theme.text..";font-size:11px;font-weight:600;")
  return g
end
local function place(item,x,y,w,h) item:move(x,y); item:resize(w,h); item:show() end
function View.new(settings)
  local self=setmetatable({settings=settings,direction_buttons={},utility_buttons={},exit_available={}},View); local t=settings.theme
  self.root=Geyser.Container:new({name="DGHUD.Root",x=0,y=0,width="100%",height="100%"})
  self.header=label("DGHUD.Header",self.root,"background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px 18px;")
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
  self.compass_area=Geyser.Container:new({name="DGHUD.Compass",x=0,y=0,width=100,height=100},self.right)
  self.compass_center=label("DGHUD.Compass.Center",self.compass_area,"background:transparent;color:"..t.muted..";"); self.compass_center:echo("<center>◆</center>")
  for i,direction in ipairs(Navigation.directions) do local b=label("DGHUD.Compass."..direction.key,self.compass_area); b:setClickCallback(function() if self.exit_available[direction.key] then send(direction.command) end end); self.direction_buttons[i]={label=b,direction=direction} end
  self.utility_area=Geyser.Container:new({name="DGHUD.Utilities",x=0,y=0,width=100,height=60},self.right)
  for i,utility in ipairs(Navigation.utilities) do local b=label("DGHUD.Utility."..i,self.utility_area); b:setClickCallback(function() send(utility.command) end); self.utility_buttons[i]={label=b,utility=utility} end
  self.bottom=label("DGHUD.Bottom",self.root,"background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px 15px;")
  self.compact=label("DGHUD.Compact",self.root,"background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:8px 12px;")
  return self
end
function View:applyLayout(layout)
  self.layout=layout; local top,bottom=layout.top,layout.bottom; local t=self.settings.theme; local p=layout.panel_padding
  self.header:setStyleSheet("background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  self.identity:setStyleSheet("background:"..t.panel..";border-right:1px solid "..t.border..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.details:setStyleSheet("background:"..t.panel..";border:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.left:setStyleSheet("background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  for _,card in ipairs({self.equipment,self.wealth,self.inventory}) do card:setStyleSheet("background:#101713;border:1px solid "..t.border..";border-radius:7px;color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;") end
  self.right_title:setStyleSheet("background:transparent;color:"..t.accent..";font-size:"..layout.body_font.."px;font-weight:700;padding:12px "..p.."px;")
  self.readiness:setStyleSheet("background:#131a16;border:1px solid #2b3731;border-radius:7px;color:"..t.text..";padding:12px "..p.."px;font-size:"..layout.body_font.."px;")
  self.room:setStyleSheet("background:#101a16;border:1px solid #385044;border-radius:7px;color:"..t.text..";padding:12px "..p.."px;font-size:"..layout.body_font.."px;")
  self.bottom:setStyleSheet("background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px "..p.."px;font-size:"..layout.small_font.."px;")
  self.compact:setStyleSheet("background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  for _,g in ipairs({self.hp,self.fatigue,self.carry,self.psi,self.web}) do g.text:setStyleSheet("background:transparent;color:"..t.text..";font-size:"..layout.small_font.."px;font-weight:700;"); if g.text.setFontSize then g.text:setFontSize(layout.small_font) end end
  place(self.header,0,0,"100%",top); place(self.bottom,0,"100%-"..bottom,"100%",bottom)
  if layout.mode=="wide" or layout.mode=="medium" then
    self.compact:hide()
    place(self.identity,0,top,layout.left,layout.identity_height)
    place(self.left,"100%-"..layout.right,top,layout.right,"100%-"..(top+bottom))
    local available=math.max(100,(layout.window_height or 800)-top-bottom)
    local optional=(self.last_state and self.last_state.vitals.psi.visible and 1 or 0)+(self.last_state and self.last_state.vitals.web.visible and 1 or 0)
    local navigation_height=layout.compass_cell*3+layout.utility_height*2+22
    local panel_height=math.min(available,layout.title_height+(3+optional)*(layout.gauge_height+layout.row_gap)+layout.status_height+layout.room_height+navigation_height+44)
    place(self.right,0,"100%-"..(bottom+panel_height),layout.left,panel_height)
    local details_y=top+layout.identity_height+12; local vitals_y=(layout.window_height or 800)-bottom-panel_height; local details_h=vitals_y-details_y-12
    local details_placement=Layout.detailsPlacement(details_h,layout.details_line_height)
    layout.details_columns=details_placement=="right" and 2 or 4
    if details_placement=="left" then place(self.details,0,details_y,layout.left,details_h) else self.details:hide() end
    local card_x="100%-"..(layout.right-p); local card_w=layout.right-p*2; local eq_rows=math.max(2,math.min(#((self.last_state and self.last_state.equipment.items) or {}),6))
    local equipment_h=layout.heading_font+eq_rows*layout.details_line_height+p*2+18; local wealth_h=layout.heading_font+layout.details_line_height*2+p*2+18
    place(self.equipment,card_x,top+p,card_w,equipment_h); place(self.wealth,card_x,top+p+equipment_h+12,card_w,wealth_h)
    local inventory_y=top+p+equipment_h+wealth_h+24; local rail_bottom=(layout.window_height or 800)-bottom-p
    if details_placement=="right" then
      local right_details_h=layout.details_line_height*Layout.detailsCardRows(layout.details_columns)+p*2+18
      place(self.details,card_x,rail_bottom-right_details_h,card_w,right_details_h)
      if self.details.raise then self.details:raise() end
      rail_bottom=rail_bottom-right_details_h-12
    end
    local inventory_h=rail_bottom-inventory_y
    if inventory_h>=layout.inventory_row_height*2 then place(self.inventory,card_x,inventory_y,card_w,inventory_h); self.inventory_capacity=math.max(1,math.floor((inventory_h-layout.heading_font-p*2-30)/layout.inventory_row_height)) else self.inventory:hide(); self.inventory_capacity=0 end
  else
    self.identity:hide(); self.details:hide(); self.left:hide(); self.equipment:hide(); self.wealth:hide(); self.inventory:hide(); self.right:hide(); place(self.compact,0,62,"100%",top-62)
  end
  if layout.mode~="compact" then
    place(self.right_bg,0,0,"100%","100%"); place(self.right_title,0,0,"100%",layout.title_height)
    local inset=p; local y=layout.title_height; for _,g in ipairs({self.hp,self.fatigue,self.carry}) do place(g,inset,y,"100%-"..(inset*2),layout.gauge_height); y=y+layout.gauge_height+layout.row_gap end
    if self.last_state and self.last_state.vitals.psi.visible then place(self.psi,inset,y,"100%-"..(inset*2),layout.gauge_height); y=y+layout.gauge_height+layout.row_gap else self.psi:hide() end
    if self.last_state and self.last_state.vitals.web.visible then place(self.web,inset,y,"100%-"..(inset*2),layout.gauge_height); y=y+layout.gauge_height+layout.row_gap else self.web:hide() end
    place(self.readiness,inset,y+4,"100%-"..(inset*2),layout.status_height)
    place(self.room,inset,y+layout.status_height+16,"100%-"..(inset*2),layout.room_height)
    local nav_y=y+layout.status_height+layout.room_height+28; place(self.compass_area,inset,nav_y,"100%-"..(inset*2),layout.compass_cell*3)
    local cell_width=33.333; for _,entry in ipairs(self.direction_buttons) do local d=entry.direction; place(entry.label,(d.col-1)*cell_width.."%",(d.row-1)*layout.compass_cell,cell_width.."%",layout.compass_cell) end
    place(self.compass_center,cell_width.."%",layout.compass_cell,cell_width.."%",layout.compass_cell)
    place(self.utility_area,inset,nav_y+layout.compass_cell*3+8,"100%-"..(inset*2),layout.utility_height*2+6)
    for i,entry in ipairs(self.utility_buttons) do local col=(i-1)%2; local row=math.floor((i-1)/2); place(entry.label,(col*50).."%",row*(layout.utility_height+3),"49%",layout.utility_height) end
  end
end
function View:renderNavigation(exits)
  if not self.layout or self.layout.mode=="compact" then return end
  local t=self.settings.theme; self.exit_available=Navigation.availability(exits)
  for _,entry in ipairs(self.direction_buttons) do local active=self.exit_available[entry.direction.key]; entry.label:setStyleSheet("background:"..(active and "#193024" or "rgba(16,23,19,0.28)")..";border:1px solid "..(active and "#5d9b71" or "#273029")..";border-radius:5px;color:"..(active and "#b8efc2" or "#536058")..";font-weight:700;"); entry.label:echo(View.withFont("<center><b>"..entry.direction.label.."</b></center>",self.layout.compass_font)) end
  for _,entry in ipairs(self.utility_buttons) do entry.label:setStyleSheet("background:#17231c;border:1px solid #385044;border-radius:5px;color:"..t.jade..";font-weight:700;"); entry.label:echo(View.withFont("<center><b>"..entry.utility.label.."</b></center>",self.layout.utility_font)) end
end
function View:renderInventory(s)
  local t=self.settings.theme; local layout=self.layout; if not layout or layout.mode=="compact" then return end
  local rows=View.inventoryRows(s.inventory.items,self.inventory_capacity or 0); local lines={"<span style='color:"..t.accent.."'><b>INVENTORY</b></span>"}
  for _,item in ipairs(rows) do if item.overflow then lines[#lines+1]="<span style='color:"..t.muted.."'>"..item.label.."</span>" else lines[#lines+1]=esc(item.name).." <span style='color:"..t.muted.."'>"..esc(item.weight or "").." lb</span>" end end
  if s.inventory.total_weight then lines[#lines+1]="<br><b>Total "..esc(s.inventory.total_weight).." lb</b>" end
  self.inventory:echo(View.withFont(table.concat(lines,"<br>"),layout.inventory_font))
end
function View:update(s)
  self.last_state=s; local t=self.settings.theme; local v=s.vitals; local layout=self.layout or {mode="wide",heading_font=20}; local ready=function(x) return x and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:"..t.hp.."'><b>NOT READY</b></span>" end
  self.header:echo(View.headerContent(layout,t,s.character.full_name))
  self.identity:echo(View.identityContent(s.character,t,layout))
  self.equipment:echo(View.equipmentContent(v,s.equipment.items,t,layout)); self.wealth:echo(View.wealthContent(v,t,layout))
  self.right_title:echo(View.withFont("<b>VITALS &amp; LOCATION</b>",layout.body_font))
  self.hp:setValue(v.hp.current,math.max(v.hp.maximum,1),"Health  "..v.hp.current.." / "..v.hp.maximum); self.fatigue:setValue(v.fatigue.current,math.max(v.fatigue.maximum,1),"Fatigue  "..v.fatigue.current.." / "..v.fatigue.maximum); self.carry:setValue(v.carry.current,math.max(v.carry.maximum,1),"Carry  "..v.carry.current.." / "..v.carry.maximum)
  if v.psi.visible then self.psi:setValue(v.psi.current,v.psi.maximum,"PSI  "..v.psi.current.." / "..v.psi.maximum) end; if v.web.visible then self.web:setValue(v.web.current,v.web.maximum,"Web  "..v.web.current.." / "..v.web.maximum) end
  self.readiness:echo(View.withFont("<span style='color:"..t.accent.."'><b>STATUS</b></span><br><br>Roundtime &nbsp; <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b><br>Position &nbsp; <b>"..v.position.."</b>",layout.body_font))
  self.room:echo(View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>"..esc(s.room.name).."</b></span><br><span style='color:"..t.muted.."'>Room "..esc(s.room.num or "—").." · Area "..esc(s.room.area or "—").."</span><br><br>"..esc(s.room.environment).."<br>Players &nbsp; <b>"..#s.room.players.."</b><br>Flags &nbsp; "..esc(table.concat(s.room.flags,", ")),layout.body_font))
  self.compact:echo(View.withFont("<b>HP "..v.hp.current.."/"..v.hp.maximum.."</b> &nbsp; FAT "..v.fatigue.current.."/"..v.fatigue.maximum.." &nbsp; WPN "..(v.weapon_readied and "✓" or "×").." &nbsp; SHD "..(v.shield_readied and "✓" or "×").." &nbsp; <span style='color:"..t.accent.."'>"..esc(s.room.name).."</span>",layout.body_font))
  self.bottom:echo(View.withFont("EXITS &nbsp; <b>"..esc(table.concat(s.room.exits,", ")).."</b> &nbsp;&nbsp; | &nbsp;&nbsp; CARRY &nbsp; <b>"..v.carry.current.." / "..v.carry.maximum.."</b> &nbsp;&nbsp; | &nbsp;&nbsp; ROUND &nbsp; <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b>",layout.small_font))
  if self.layout then self:applyLayout(self.layout); self.details:echo(View.detailsContent(s.combat,s.attributes,t,self.layout)); self:renderInventory(s); self:renderNavigation(s.room.exits) end
end
function View:delete() if self.root then self.root:delete(); self.root=nil end end
return View
