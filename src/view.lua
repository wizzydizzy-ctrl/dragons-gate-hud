local View={}; View.__index=View
local function html(text) return tostring(text or ""):gsub("&","&amp;"):gsub("<","&lt;"):gsub(">","&gt;") end
function View.new(settings)
  local self=setmetatable({settings=settings},View); local t=settings.theme
  self.root=Geyser.Container:new({name="DGHUD.Root",x=0,y=0,width="100%",height="100%"})
  self.left=Geyser.Label:new({name="DGHUD.Character",x=0,y=0,width=settings.layout.left_width,height="100%"},self.root)
  self.right=Geyser.Label:new({name="DGHUD.Status",x="100%-"..settings.layout.right_width,y=0,width=settings.layout.right_width,height="100%"},self.root)
  self.left:setStyleSheet("background:"..t.panel..";border-right:1px solid "..t.border..";color:"..t.text..";padding:14px;")
  self.right:setStyleSheet("background:"..t.panel..";border-left:1px solid "..t.border..";color:"..t.text..";padding:14px;")
  return self
end
function View:update(s)
  local ready=function(v) return v and "<span style='color:#79b386'>READY</span>" or "<span style='color:#ba5147'>NOT READY</span>" end
  self.left:echo("<center><span style='color:#e0b56c;font-size:18px'><b>"..html(s.character.full_name).."</b></span><br>"..html(s.character.race).." · "..html(s.character.class).."<br><small>"..html(s.character.alignment).."</small></center>")
  local v=s.vitals; local optional=""; if v.psi.visible then optional=optional.."<br>PSI "..v.psi.current.." / "..v.psi.maximum end; if v.web.visible then optional=optional.."<br>WEB "..v.web.current.." / "..v.web.maximum end
  self.right:echo("<span style='color:#e0b56c'><b>GMCP STATUS</b></span><br><br>Health <b>"..v.hp.current.." / "..v.hp.maximum.."</b><br>Fatigue <b>"..v.fatigue.current.." / "..v.fatigue.maximum.."</b>"..optional.."<br><br>Weapon "..ready(v.weapon_readied).."<br>Shield "..ready(v.shield_readied).."<br><br>Carry "..v.carry.current.." / "..v.carry.maximum.."<br>Gold "..v.gold.." · Silver "..v.silver.."<br><br><span style='color:#e0b56c'><b>"..html(s.room.name).."</b></span><br>"..html(s.room.environment).."<br>Exits: "..html(table.concat(s.room.exits,", ")))
end
function View:delete() if self.root then self.root:delete(); self.root=nil end end
return View
