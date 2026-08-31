local View={}; View.__index=View
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
  self.left=label("DGHUD.LeftRail",self.root,"background:"..t.panel..";border-right:1px solid "..t.border..";color:"..t.text..";padding:18px;")
  self.right=Geyser.Container:new({name="DGHUD.RightRail",x=0,y=0,width=300,height=500},self.root)
  self.right_bg=label("DGHUD.RightBackground",self.right,"background:"..t.panel..";border-left:1px solid "..t.border..";")
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
  self.layout=layout; local top,bottom=layout.top,layout.bottom
  place(self.header,0,0,"100%",top); place(self.bottom,0,"100%-"..bottom,"100%",bottom)
  if layout.mode=="wide" then
    self.compact:hide(); place(self.left,0,top,layout.left,"100%-"..(top+bottom)); place(self.right,"100%-"..layout.right,top,layout.right,"100%-"..(top+bottom))
  elseif layout.mode=="medium" then
    self.left:hide(); self.compact:hide(); place(self.right,"100%-"..layout.right,top,layout.right,"100%-"..(top+bottom))
  else
    self.left:hide(); self.right:hide(); place(self.compact,0,62,"100%",top-62)
  end
  if layout.mode~="compact" then
    place(self.right_bg,0,0,"100%","100%"); place(self.right_title,0,0,"100%",42)
    local y=48; for _,g in ipairs({self.hp,self.fatigue,self.carry}) do place(g,14,y,"100%-28",22); y=y+32 end
    if self.last_state and self.last_state.vitals.psi.visible then place(self.psi,14,y,"100%-28",22); y=y+32 else self.psi:hide() end
    if self.last_state and self.last_state.vitals.web.visible then place(self.web,14,y,"100%-28",22); y=y+32 else self.web:hide() end
    place(self.readiness,14,y+4,"100%-28",82); place(self.room,14,y+96,"100%-28",layout.show_room_compass and 150 or 112); place(self.exit_area,14,y+(layout.show_room_compass and 252 or 214),"100%-28",42)
  end
end
function View:clearExits() for _,button in ipairs(self.exit_buttons) do button:delete() end; self.exit_buttons={} end
function View:buildExits(exits)
  self:clearExits(); if not self.layout or self.layout.mode=="compact" then return end
  local count=math.max(#exits,1); local width=math.floor(100/count)
  for i,direction in ipairs(exits) do local b=label("DGHUD.Exit."..i,self.exit_area,"background:#193024;border:1px solid #39614a;border-radius:4px;color:#91d9a2;font-size:10px;font-weight:700;"); place(b,(i-1)*width.."%",0,(width-2).."%",30); b:echo("<center>"..esc(direction):upper().."</center>"); b:setClickCallback(function() send(direction) end); self.exit_buttons[#self.exit_buttons+1]=b end
end
function View:update(s)
  self.last_state=s; local t=self.settings.theme; local v=s.vitals; local ready=function(x) return x and "<span style='color:"..t.jade.."'><b>READY</b></span>" or "<span style='color:"..t.hp.."'><b>NOT READY</b></span>" end
  local identity="<span style='color:"..t.accent..";font-size:19px'><b>DRAGONS GATE</b></span> &nbsp; <span style='color:"..t.jade.."'><b>"..esc(s.character.full_name).."</b></span><br><span style='color:"..t.muted.."'>"..esc(s.character.race).." · "..esc(s.character.class).." · "..esc(s.character.alignment).." &nbsp; | &nbsp; GMCP LIVE</span>"
  self.header:echo(identity)
  self.left:echo("<center><span style='color:"..t.accent..";font-size:22px'><b>"..esc(s.character.full_name).."</b></span><br><span style='color:"..t.jade.."'>"..esc(s.character.race).." · "..esc(s.character.class).."</span><br><span style='color:"..t.muted.."'>Alignment: "..esc(s.character.alignment).."</span></center><br><br><span style='color:"..t.accent.."'><b>READIED</b></span><br><br>Weapon &nbsp; "..ready(v.weapon_readied).."<br><br>Shield &nbsp;&nbsp; "..ready(v.shield_readied).."<br><br><hr><br><span style='color:"..t.accent.."'><b>CURRENCY</b></span><br><br>Gold: <b>"..v.gold.."</b><br>Silver: <b>"..v.silver.."</b><br><br><span style='color:"..t.accent.."'><b>POSITION</b></span><br><br>"..v.position)
  self.right_title:echo("GMCP STATUS")
  self.hp:setValue(v.hp.current,math.max(v.hp.maximum,1),"Health  "..v.hp.current.." / "..v.hp.maximum); self.fatigue:setValue(v.fatigue.current,math.max(v.fatigue.maximum,1),"Fatigue  "..v.fatigue.current.." / "..v.fatigue.maximum); self.carry:setValue(v.carry.current,math.max(v.carry.maximum,1),"Carry  "..v.carry.current.." / "..v.carry.maximum)
  if v.psi.visible then self.psi:setValue(v.psi.current,v.psi.maximum,"PSI  "..v.psi.current.." / "..v.psi.maximum) end; if v.web.visible then self.web:setValue(v.web.current,v.web.maximum,"Web  "..v.web.current.." / "..v.web.maximum) end
  self.readiness:echo("<span style='color:"..t.muted.."'>EQUIPMENT</span><br>Weapon &nbsp; "..ready(v.weapon_readied).."<br>Shield &nbsp;&nbsp; "..ready(v.shield_readied).."<br><span style='color:"..t.muted.."'>Roundtime:</span> <b>"..(v.roundtime==0 and "READY" or v.roundtime).."</b>")
  self.room:echo("<span style='color:"..t.accent..";font-size:15px'><b>"..esc(s.room.name).."</b></span><br><span style='color:"..t.muted.."'>Room "..esc(s.room.num or "—").." · Area "..esc(s.room.area or "—").."</span><br>"..esc(s.room.environment).."<br>Players here: <b>"..#s.room.players.."</b><br>Flags: "..esc(table.concat(s.room.flags,", ")))
  self.compact:echo("<b>HP "..v.hp.current.."/"..v.hp.maximum.."</b> &nbsp; FAT "..v.fatigue.current.."/"..v.fatigue.maximum.." &nbsp; WPN "..(v.weapon_readied and "✓" or "×").." &nbsp; SHD "..(v.shield_readied and "✓" or "×").." &nbsp; <span style='color:"..t.accent.."'>"..esc(s.room.name).."</span>")
  self.bottom:echo("WEAPON <b>"..(v.weapon_readied and "READY" or "NOT READY").."</b> &nbsp; | &nbsp; SHIELD <b>"..(v.shield_readied and "READY" or "NOT READY").."</b> &nbsp; | &nbsp; EXITS <b>"..esc(table.concat(s.room.exits,", ")).."</b> &nbsp; | &nbsp; NETWORK <span style='color:"..t.jade.."'><b>GMCP LIVE</b></span>")
  self:buildExits(s.room.exits); if self.layout then self:applyLayout(self.layout) end
end
function View:delete() self:clearExits(); if self.root then self.root:delete(); self.root=nil end end
return View
