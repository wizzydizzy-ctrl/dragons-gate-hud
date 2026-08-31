local View={}; View.__index=View
function View.withFont(text,size) return "<span style='font-size:"..tonumber(size).."px'>"..text.."</span>" end
local function esc(v) return tostring(v or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
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
  local self=setmetatable({settings=settings,exit_buttons={}},View); local t=settings.theme
  self.root=Geyser.Container:new({name="DGHUD.Root",x=0,y=0,width="100%",height="100%"})
  self.header=label("DGHUD.Header",self.root,"background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px 18px;")
  self.left=label("DGHUD.LeftRail",self.root,"background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.right=Geyser.Container:new({name="DGHUD.RightRail",x=0,y=0,width=300,height=500},self.root)
  self.right_bg=label("DGHUD.RightBackground",self.right,"background:"..t.panel..";border-right:1px solid "..t.border..";")
  self.right_title=label("DGHUD.RightTitle",self.right,"background:transparent;color:"..t.accent..";font-size:13px;font-weight:700;padding:10px 14px;")
  self.hp=gauge("DGHUD.Health",self.right,t.hp,t); self.fatigue=gauge("DGHUD.Fatigue",self.right,t.fatigue,t); self.carry=gauge("DGHUD.Carry",self.right,"#c9a359",t); self.psi=gauge("DGHUD.Psi",self.right,"#6a72c9",t); self.web=gauge("DGHUD.Web",self.right,"#9b78b5",t)
  self.readiness=label("DGHUD.Readiness",self.right,"background:#131a16;border:1px solid #2b3731;border-radius:6px;color:"..t.text..";padding:9px 12px;")
  self.room=label("DGHUD.Room",self.right,"background:#101a16;border:1px solid #385044;border-radius:6px;color:"..t.text..";padding:10px 12px;")
  self.exit_area=Geyser.Container:new({name="DGHUD.Exits",x=0,y=0,width=100,height=40},self.right)
  self.bottom=label("DGHUD.Bottom",self.root,"background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px 15px;")
  self.compact=label("DGHUD.Compact",self.root,"background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:8px 12px;")
  return self
end
function View:applyLayout(layout)
  self.layout=layout; local top,bottom=layout.top,layout.bottom; local t=self.settings.theme; local p=layout.panel_padding
  self.header:setStyleSheet("background:"..t.background..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  self.left:setStyleSheet("background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:"..p.."px;font-size:"..layout.body_font.."px;")
  self.right_title:setStyleSheet("background:transparent;color:"..t.accent..";font-size:"..layout.body_font.."px;font-weight:700;padding:12px "..p.."px;")
  self.readiness:setStyleSheet("background:#131a16;border:1px solid #2b3731;border-radius:7px;color:"..t.text..";padding:12px "..p.."px;font-size:"..layout.body_font.."px;")
  self.room:setStyleSheet("background:#101a16;border:1px solid #385044;border-radius:7px;color:"..t.text..";padding:12px "..p.."px;font-size:"..layout.body_font.."px;")
  self.bottom:setStyleSheet("background:#151713;border-top:1px solid "..t.border..";color:"..t.muted..";padding:9px "..p.."px;font-size:"..layout.small_font.."px;")
  self.compact:setStyleSheet("background:"..t.panel..";border-bottom:1px solid "..t.border..";color:"..t.text..";padding:10px "..p.."px;font-size:"..layout.body_font.."px;")
  for _,g in ipairs({self.hp,self.fatigue,self.carry,self.psi,self.web}) do g.text:setStyleSheet("background:transparent;color:"..t.text..";font-size:"..layout.small_font.."px;font-weight:700;"); if g.text.setFontSize then g.text:setFontSize(layout.small_font) end end
  place(self.header,0,0,"100%",top); place(self.bottom,0,"100%-"..bottom,"100%",bottom)
  if layout.mode=="wide" or layout.mode=="medium" then
    self.compact:hide()
    place(self.left,"100%-"..layout.right,top,layout.right,"100%-"..(top+bottom))
    local available=math.max(100,(layout.window_height or 800)-top-bottom)
    local optional=(self.last_state and self.last_state.vitals.psi.visible and 1 or 0)+(self.last_state and self.last_state.vitals.web.visible and 1 or 0)
    local panel_height=math.min(available,layout.title_height+(3+optional)*(layout.gauge_height+layout.row_gap)+layout.status_height+layout.room_height+layout.exit_height+44)
    place(self.right,0,"100%-"..(bottom+panel_height),layout.left,panel_height)
  else
    self.left:hide(); self.right:hide(); place(self.compact,0,62,"100%",top-62)
  end
  if layout.mode~="compact" then
    place(self.right_bg,0,0,"100%","100%"); place(self.right_title,0,0,"100%",layout.title_height)
    local inset=p; local y=layout.title_height; for _,g in ipairs({self.hp,self.fatigue,self.carry}) do place(g,inset,y,"100%-"..(inset*2),layout.gauge_height); y=y+layout.gauge_height+layout.row_gap end
    if self.last_state and self.last_state.vitals.psi.visible then place(self.psi,inset,y,"100%-"..(inset*2),layout.gauge_height); y=y+layout.gauge_height+layout.row_gap else self.psi:hide() end
    if self.last_state and self.last_state.vitals.web.visible then place(self.web,inset,y,"100%-"..(inset*2),layout.gauge_height); y=y+layout.gauge_height+layout.row_gap else self.web:hide() end
    place(self.readiness,inset,y+4,"100%-"..(inset*2),layout.status_height)
    place(self.room,inset,y+layout.status_height+16,"100%-"..(inset*2),layout.room_height)
    place(self.exit_area,inset,y+layout.status_height+layout.room_height+28,"100%-"..(inset*2),layout.exit_height)
  end
end
function View:clearExits() for _,button in ipairs(self.exit_buttons) do button:delete() end; self.exit_buttons={} end
function View:buildExits(exits)
  self:clearExits(); if not self.layout or self.layout.mode=="compact" then return end
  local count=math.max(#exits,1); local width=math.floor(100/count)
  for i,direction in ipairs(exits) do local b=label("DGHUD.Exit."..i,self.exit_area,"background:#193024;border:1px solid #39614a;border-radius:4px;color:#91d9a2;font-size:"..self.layout.small_font.."px;font-weight:700;"); place(b,(i-1)*width.."%",0,(width-2).."%",self.layout.small_font+12); b:echo(View.withFont("<center><b>"..esc(direction):upper().."</b></center>",self.layout.small_font)); b:setClickCallback(function() send(direction) end); self.exit_buttons[#self.exit_buttons+1]=b end
end
function View:update(s)
  self.last_state=s; local t=self.settings.theme; local v=s.vitals; local layout=self.layout or {mode="wide",heading_font=20}; local ready=function(x) return x and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:"..t.hp.."'><b>NOT READY</b></span>" end
  local header_detail=layout.mode=="wide" and "" or " &nbsp; <span style='color:"..t.text.."'><b>"..esc(s.character.full_name).."</b></span>"
  self.header:echo(View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>DRAGONS GATE</b></span>"..header_detail.."<br><span style='color:"..t.jade.."'><b>● GMCP LIVE</b></span>",layout.body_font))
  self.left:echo(View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>"..esc(s.character.full_name).."</b></span><br><span style='color:"..t.jade.."'><b>"..esc(s.character.race).." · "..esc(s.character.class).."</b></span><br><span style='color:"..t.muted.."'>"..esc(s.character.alignment).."</span><br><br><span style='color:"..t.accent.."'><b>EQUIPMENT</b></span><br><br>Weapon<br>"..ready(v.weapon_readied).."<br><br>Shield<br>"..ready(v.shield_readied).."<br><br><hr><br><span style='color:"..t.accent.."'><b>WEALTH</b></span><br><br>Gold &nbsp; <b>"..v.gold.."</b><br>Silver &nbsp; <b>"..v.silver.."</b>",layout.body_font))
  self.right_title:echo(View.withFont("<b>VITALS &amp; LOCATION</b>",layout.body_font))
  self.hp:setValue(v.hp.current,math.max(v.hp.maximum,1),"Health  "..v.hp.current.." / "..v.hp.maximum); self.fatigue:setValue(v.fatigue.current,math.max(v.fatigue.maximum,1),"Fatigue  "..v.fatigue.current.." / "..v.fatigue.maximum); self.carry:setValue(v.carry.current,math.max(v.carry.maximum,1),"Carry  "..v.carry.current.." / "..v.carry.maximum)
  if v.psi.visible then self.psi:setValue(v.psi.current,v.psi.maximum,"PSI  "..v.psi.current.." / "..v.psi.maximum) end; if v.web.visible then self.web:setValue(v.web.current,v.web.maximum,"Web  "..v.web.current.." / "..v.web.maximum) end
  self.readiness:echo(View.withFont("<span style='color:"..t.accent.."'><b>STATUS</b></span><br><br>Roundtime &nbsp; <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b><br>Position &nbsp; <b>"..v.position.."</b>",layout.body_font))
  self.room:echo(View.withFont("<span style='color:"..t.accent..";font-size:"..layout.heading_font.."px'><b>"..esc(s.room.name).."</b></span><br><span style='color:"..t.muted.."'>Room "..esc(s.room.num or "—").." · Area "..esc(s.room.area or "—").."</span><br><br>"..esc(s.room.environment).."<br>Players &nbsp; <b>"..#s.room.players.."</b><br>Flags &nbsp; "..esc(table.concat(s.room.flags,", ")),layout.body_font))
  self.compact:echo(View.withFont("<b>HP "..v.hp.current.."/"..v.hp.maximum.."</b> &nbsp; FAT "..v.fatigue.current.."/"..v.fatigue.maximum.." &nbsp; WPN "..(v.weapon_readied and "✓" or "×").." &nbsp; SHD "..(v.shield_readied and "✓" or "×").." &nbsp; <span style='color:"..t.accent.."'>"..esc(s.room.name).."</span>",layout.body_font))
  self.bottom:echo(View.withFont("EXITS &nbsp; <b>"..esc(table.concat(s.room.exits,", ")).."</b> &nbsp;&nbsp; | &nbsp;&nbsp; CARRY &nbsp; <b>"..v.carry.current.." / "..v.carry.maximum.."</b> &nbsp;&nbsp; | &nbsp;&nbsp; ROUND &nbsp; <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b>",layout.small_font))
  self:buildExits(s.room.exits); if self.layout then self:applyLayout(self.layout) end
end
function View:delete() self:clearExits(); if self.root then self.root:delete(); self.root=nil end end
return View
