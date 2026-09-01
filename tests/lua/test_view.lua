local View=require("view")
test("rich text receives an explicit responsive font size",function()
  eq(View.withFont("Status",20),"<span style='font-size:20px'>Status</span>")
end)

test("identity and right rail content remain separate",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local character={full_name="Test Tester",race="Monitanian",class="Fighter",alignment="entropy"}
  local identity=View.identityContent(character,theme,layout)
  local equipment=View.equipmentContent({weapon_readied=true,shield_readied=false,gold=3,silver=9},theme,layout)
  eq(identity:find("Test Tester",1,true)~=nil,true); eq(identity:find("Monitanian",1,true)~=nil,true)
  eq(identity:find("Fighter",1,true)~=nil,true); eq(identity:find("entropy",1,true)~=nil,true)
  eq(identity:find("EQUIPMENT",1,true)==nil,true); eq(equipment:find("Test Tester",1,true)==nil,true)
  eq(equipment:find("EQUIPMENT",1,true)~=nil,true); eq(equipment:find("WEALTH",1,true)==nil,true)
end)

test("visible header removes protocol wording",function()
  local h=View.headerContent({mode="wide",body_font=20,heading_font=25},{accent="#d8ae53",jade="#72bd82",text="#fff"},"Test Tester")
  eq(h:find("GMCP",1,true),nil); eq(h:find("● LIVE",1,true)~=nil,true)
end)
test("inventory truncates without splitting rows",function()
  local rows=View.inventoryRows({{name="One",weight=1},{name="Two",weight=2},{name="Three",weight=3}},2)
  eq(#rows,2); eq(rows[1].name,"One"); eq(rows[2].label,"+2 more"); eq(rows[2].overflow,2)
end)
test("inventory footer renders compact colored gold and silver currency",function()
  local theme={accent="#d8ae53",muted="#91a098",gold="#e0b84f",silver="#c0c0c0"}
  local html=View.inventoryContent({items={},total_weight=0},{gold=12,silver=34},theme,{inventory_font=18},4)
  eq(html:find("WEALTH",1,true),nil)
  eq(html:find("12gp",1,true)~=nil,true); eq(html:find("34sp",1,true)~=nil,true)
  eq(html:find("color:#e0b84f",1,true)~=nil,true); eq(html:find("color:#c0c0c0",1,true)~=nil,true)
  eq(html:find("12gp",1,true)<html:find("34sp",1,true),true)
end)
test("skill rows use stable aligned name level and remaining columns",function()
  local header=View.skillHeader(24); local short=View.skillLine({name="Biting",level=4,remain=105},24); local long=View.skillLine({name="Identify Armor Quality",level=1,remain=7},24)
  eq(header:find("LVL",1,true)~=nil,true); eq(header:find("USES",1,true)~=nil,true)
  eq(short:find("4",1,true),long:find("1",1,true)); eq(short:find("105",1,true)+2,long:find("7",1,true))
end)
test("identity details render while attributes move to the top strip",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Test Tester",race="Monitanian",class="Fighter",alignment="entropy",physical={age=28,sex="Male",height="6'10\""}},theme,layout)
  local details=View.detailsContent({body_armor=4,or_rating=18,dr=70,stance="Aggressive"},{STR="Good",APP="Fair"},theme,layout,{roundtime=8,position=1})
  local equipment=View.equipmentContent({weapon_readied=true,shield_readied=true},{"A spear","A shield"},theme,layout)
  local strip=View.attributeStripContent({STR="Good",APP="Fair"},theme,{attribute_strip_font=12})
  eq(identity:find("28",1,true)~=nil,true); eq(details:find("Aggressive",1,true)~=nil,true); eq(details:find("STR",1,true),nil)
  eq(details:find("COMBAT",1,true)~=nil,true); eq(details:find("CHARACTER",1,true),nil)
  eq(details:find("Roundtime",1,true)~=nil,true); eq(details:find("Position",1,true)~=nil,true)
  eq(strip:find("STR",1,true)~=nil,true); eq(strip:find("Good",1,true)~=nil,true); eq(strip:find("APP",1,true)~=nil,true); eq(strip:find("Fair",1,true)~=nil,true)
  eq(equipment:find("A spear",1,true),nil); eq(equipment:find("Weapon",1,true)~=nil,true); eq(equipment:find("Shield",1,true)~=nil,true)
end)
test("identity includes compact religion information",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25}
  local identity=View.identityContent({full_name="Test Tester",race="Monitanian",class="Fighter",alignment="entropy",religion="Novitiate",deity="Unknown",religious_balance="Balanced"},theme,layout)
  eq(identity:find("Novitiate · Unknown",1,true)~=nil,true); eq(identity:find(">Balanced</span>",1,true)~=nil,true)
end)
test("right rail details keep combat information without attributes",function()
  local theme={accent="#d8ae53",jade="#72bd82",muted="#91a098"}; local layout={body_font=20,heading_font=25,details_columns=2}
  local details=View.detailsContent({body_armor=4,or_rating=18,dr=70,stance="Aggressive"},{STR="Good",INT="Low",WIS="Fair"},theme,layout)
  eq(details:find("<br>Stance",1,true)~=nil,true)
  eq(details:find("STR",1,true),nil); eq(details:find("INT",1,true),nil); eq(details:find("WIS",1,true),nil)
end)
test("right rail cards can be raised above their shared background",function()
  local raised=0; local card={raise=function() raised=raised+1 end}
  View.raiseCards({card,card,card}); eq(raised,3)
end)
test("combat card renders ready roundtime and position without a status heading",function()
  local html=View.detailsContent({},nil,{accent="#d8ae53"},{inventory_font=18},{roundtime=0,position=1})
  eq(html:find("COMBAT",1,true)~=nil,true); eq(html:find("STATUS",1,true),nil)
  eq(html:find("Roundtime",1,true)~=nil,true); eq(html:find("READY",1,true)~=nil,true); eq(html:find("Position",1,true)~=nil,true)
end)

local function fakeGeyser()
  local function widget(cons,parent,kind)
    local item={name=cons.name,parent=parent,kind=kind,visible=true,echoes={},currentScroll=0,lastLine=0}
    function item:setStyleSheet(value) self.style=value end
    function item:move(x,y) self.x=x; self.y=y end
    function item:resize(width,height) self.width=width; self.height=height end
    function item:show() self.visible=true end
    function item:hide() self.visible=false end
    function item:raise() self.raised=true end
    function item:delete() self.deleted=true end
    function item:setClickCallback(callback) self.click=callback end
    function item:setToolTip(value) self.tooltip=value end
    function item:echo(value)
      if self.kind=="console" then
        self.echoes[#self.echoes+1]=value
        local first=self.lastLine+1
        local columns=math.max(1,tonumber(self.wrap) or 80)
        local rows=math.max(1,math.ceil(#tostring(value)/columns))
        self.lastLine=self.lastLine+rows
        self.renderedEntries=self.renderedEntries or {}
        self.renderedEntries[#self.renderedEntries+1]={first=first,last=self.lastLine}
      else self.message=value end
    end
    function item:hecho(value)
      self.hechoes=self.hechoes or {}
      self.hechoes[#self.hechoes+1]=value
    end
    function item:clear() self.clearCalls=(self.clearCalls or 0)+1; self.echoes={}; self.hechoes={}; self.lastLine=0; self.renderedEntries={} end
    function item:setWrap(value) self.wrap=value; return true end
    function item:setFontSize(value) self.fontSize=value end
    function item:enableScrollBar() self.scrollBar=true end
    function item:disableHorizontalScrollBar() self.horizontalScrollBar=false end
    function item:getScroll() return self.currentScroll end
    function item:getLastLineNumber() return self.lastLine end
    function item:scrollTo(line) self.scrollCalls=self.scrollCalls or {}; self.scrollCalls[#self.scrollCalls+1]=line==nil and "bottom" or line; self.currentScroll=line or self.lastLine end
    function item:setValue(current,maximum,text) self.value={current,maximum,text} end
    return item
  end
  local geyser={}
  geyser.Container={new=function(_,cons,parent) return widget(cons,parent,"container") end}
  geyser.ScrollBox={new=function(_,cons,parent) return widget(cons,parent,"scrollbox") end}
  geyser.Label={new=function(_,cons,parent) return widget(cons,parent,"label") end}
  geyser.MiniConsole={new=function(_,cons,parent) return widget(cons,parent,"console") end}
  geyser.Mapper={new=function(_,cons,parent) return widget(cons,parent,"mapper") end}
  geyser.Gauge={new=function(_,cons,parent)
    local item=widget(cons,parent,"gauge"); item.front=widget({},item,"label"); item.back=widget({},item,"label"); item.text=widget({},item,"label"); return item
  end}
  return geyser
end

local function chatView()
  local original=Geyser; Geyser=fakeGeyser()
  local view=View.new({theme={background="#080b0a",panel="#0d1210",border="#423825",text="#d7d0bf",muted="#75857c",accent="#e0b56c",jade="#79b386",hp="#ba5147",fatigue="#8bad4e"},chat={timestamps=true}})
  Geyser=original
  return view
end

test("view has no standalone wealth widget",function()
  local view=chatView(); eq(view.wealth,nil)
end)

test("inventory and skills own five-row scrollable consoles",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  eq(view.inventory_output.kind,"scrollbox"); eq(view.skills_output.kind,"scrollbox")
  eq(view.inventory_content.parent,view.inventory_output); eq(view.skills_content.parent,view.skills_output)
  eq(view.inventory_output.height,layout.list_row_height*5); eq(view.skills_output.height,layout.list_row_height*5)
end)
test("scrollable list content uses resolved numeric widths",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  local state={character={physical={}},attributes={},combat={},equipment={items={}},inventory={items={{name="One",weight=1}},total_weight=1},skills={items={{name="Biting",level=4,remain=10}}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=0,silver=0,roundtime=0,position=0},room={players={},flags={},exits={}}}
  view:update(state)
  eq(type(view.inventory_content.width),"number"); eq(type(view.skills_content.width),"number")
  eq(view.inventory_content.width<view.inventory_output.width,true); eq(view.skills_content.width<view.skills_output.width,true)
  eq(view.inventory_content.raised,true); eq(view.skills_content.raised,true)
end)
test("responsive skill columns fit both wide and medium right rails",function()
  for _,size in ipairs({{1920,1080},{1200,800},{1200,650}}) do
    local view=chatView(); local layout=require("layout").compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.skill_name_width>=8,true); eq(#View.skillLine({name=string.rep("Long Skill ",5),level=30,remain=7},view.skill_name_width)<=view.skill_character_capacity,true)
  end
end)

test("scrollable cards render every inventory item and every ranked skill",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  local items,skills={},{}; for i=1,12 do items[i]={name="Item "..i,weight=i}; skills[i]={name="Skill "..i,level=20-i,remain=i} end
  view:update({character={full_name="Test",race="Monitanian",class="Fighter",alignment="entropy",physical={}},attributes={},combat={},equipment={items={}},inventory={items=items,total_weight=78},skills={items=skills},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=2,silver=3,roundtime=0,position=0,weapon_readied=false,shield_readied=false},room={name="Room",num=1,area=1,environment="Plain",players={},flags={},exits={}}})
  eq(view.inventory_content.message:find("Item 12",1,true)~=nil,true); eq(view.skills_content.message:find("Skill&nbsp;12",1,true)~=nil,true)
  eq(view.inventory_content.height>=layout.list_row_height*12,true); eq(view.skills_content.height>=layout.list_row_height*12,true); eq(view.inventory_footer.message:find("2gp",1,true)~=nil,true)
  eq(view.skills_content.message:find("white-space:pre",1,true),nil); eq(view.skills_content.message:find("&nbsp;",1,true)~=nil,true)
end)

test("unchanged HUD refreshes preserve inventory and skill scroll positions",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080))
  local state={character={full_name="Test",race="M",class="F",alignment="e",physical={}},attributes={},combat={},equipment={items={}},inventory={items={{name="One",weight=1}},total_weight=1},skills={items={{name="Biting",level=4,remain=10}}},vitals={hp={current=1,maximum=1},fatigue={current=1,maximum=1},carry={current=1,maximum=1},psi={visible=false},web={visible=false},gold=0,silver=0,roundtime=0,position=0},room={name="R",players={},flags={},exits={}}}
  view:update(state); local inventoryMessage=view.inventory_content.message; local skillMessage=view.skills_content.message
  view:update(state); eq(view.inventory_content.message,inventoryMessage); eq(view.skills_content.message,skillMessage)
  state.skills.items={{name="Clawing",level=5,remain=2}}; view:update(state); eq(view.skills_content.message:find("Clawing",1,true)~=nil,true)
end)

test("right rail orders inventory combat skills and vitals without overlap",function()
  for _,size in ipairs({{1920,1080},{1200,800},{1200,650}}) do
    local layout=require("layout").compute(size[1],size[2]); local view=chatView(); view.last_state={vitals={psi={visible=false},web={visible=false}},equipment={items={}}}; view:applyLayout(layout)
    eq(view.inventory.visible,true); eq(view.skills.visible,true)
    if view.details.visible then eq(view.inventory.y+view.inventory.height<=view.details.y,true); eq(view.details.y+view.details.height<=view.skills.y,true) else eq(view.inventory.y+view.inventory.height<=view.skills.y,true) end
    eq(view.skills.y+view.skills.height<=layout.window_height-view.vitals_right.height,true)
  end
end)

test("native mapper is embedded immediately above the compass",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.mapper_frame~=nil,true); eq(view.mapper~=nil,true)
  eq(view.mapper.parent,view.mapper_frame); eq(view.mapper_frame.visible,true)
  eq(view.mapper_frame.y+view.mapper_frame.height+layout.lower_mapper_gap,view.compass_area.y)
  eq(view.mapper.raised,true); eq(view.compass_area.raised,true)
end)

test("vitals render at the bottom of the right rail and stay out of navigation",function()
  local layout=require("layout").compute(1920,1080); local view=chatView()
  view.last_state={vitals={psi={visible=true},web={visible=false}},equipment={items={}}}
  view:applyLayout(layout)
  eq(view.vitals_right~=nil,true)
  eq(view.hp.parent,view.vitals_right); eq(view.fatigue.parent,view.vitals_right); eq(view.carry.parent,view.vitals_right)
  eq(view.vitals_right.x,"100%-"..layout.right)
  eq(type(view.vitals_right.y),"string"); eq(view.vitals_right.y:find("100%-",1,true)==1,true)
  eq(view.mapper_frame.height>=300,true)
  eq(view.room.y,layout.lower_panel_padding)
end)

test("mapper owns visible minus center and plus controls without covering compass",function()
  local view=chatView(); local layout=require("layout").compute(1920,1080); view:applyLayout(layout)
  eq(view.map_zoom_out.visible,true); eq(view.map_center.visible,true); eq(view.map_zoom_in.visible,true)
  eq(view.map_zoom_in.parent,view.mapper_frame)
  eq(view.map_zoom_in.y+view.map_zoom_in.height<=view.mapper_frame.height,true)
  eq(view.mapper.y>=layout.lower_mapper_toolbar_height,true)
  eq(view.map_zoom_out.tooltip~=nil,true); eq(view.map_center.tooltip~=nil,true); eq(view.map_zoom_in.tooltip~=nil,true)
end)

test("zoom buttons invoke visual actions",function()
  local view=chatView(); local calls={}; view:setMapZoomCallback(function(action) calls[#calls+1]=action end)
  view.map_zoom_in.click(); view.map_zoom_out.click(); view.map_center.click()
  eq(table.concat(calls,","),"larger,smaller,center")
end)

test("repeated mapper resize reuses controls and callbacks while hidden layouts hide them",function()
  local Layout=require("layout"); local view=chatView(); local calls=0
  view:setMapZoomCallback(function() calls=calls+1 end)
  local zoomOut,center,zoomIn=view.map_zoom_out,view.map_center,view.map_zoom_in
  for _,size in ipairs({{1920,1080},{1200,800},{1200,650},{1000,650},{1920,1080}}) do view:applyLayout(Layout.compute(size[1],size[2])) end
  eq(view.map_zoom_out,zoomOut); eq(view.map_center,center); eq(view.map_zoom_in,zoomIn)
  view.map_zoom_in.click(); eq(calls,1)
  view:applyLayout(Layout.compute(760,700))
  eq(view.map_zoom_out.visible,false); eq(view.map_center.visible,false); eq(view.map_zoom_in.visible,false)
end)

test("responsive mapper survives short layouts and hides cleanly in compact mode",function()
  local Layout=require("layout"); local view=chatView()
  for _,size in ipairs({{1200,800},{1200,650},{1000,650}}) do
    local layout=Layout.compute(size[1],size[2]); view:applyLayout(layout)
    eq(view.mapper_frame.visible,true); eq(view.mapper_frame.height>=90,true)
    eq(view.utility_area.y+view.utility_area.height<=view.right.height,true)
  end
  view:applyLayout(Layout.compute(760,700))
  eq(view.mapper_frame.visible,false); eq(view.mapper.visible,false)
  eq(view.map_zoom_out.visible,false); eq(view.map_center.visible,false); eq(view.map_zoom_in.visible,false)
end)

test("short layouts keep right-side vitals separate from the mapper",function()
  local layout=require("layout").compute(1200,650); local view=chatView()
  view.last_state={vitals={psi={visible=true},web={visible=true}},equipment={items={}}}
  view:applyLayout(layout)
  eq(view.hp.parent,view.vitals_right); eq(view.vitals_right.x,"100%-"..layout.right)
  if view.room.visible then eq(view.room.y+view.room.height<=view.mapper_frame.y,true) end
end)

test("right-side vitals preserve inventory before optional combat details",function()
  local layout=require("layout").compute(1200,600); local view=chatView()
  view.last_state={vitals={psi={visible=false},web={visible=false}},equipment={items={}}}
  view:applyLayout(layout)
  eq(view.inventory.visible,true)
  eq(view.inventory.height>=layout.heading_font+layout.inventory_row_height*3+layout.panel_padding*2+30,true)
  eq(view.details.visible,false)
  eq(view.inventory.y+view.inventory.height<=layout.window_height-view.vitals_right.height-12,true)
end)

test("wide short windows drop optional gauges before overlapping equipment",function()
  for _,size in ipairs({{1920,420},{2560,420}}) do
    local layout=require("layout").compute(size[1],size[2]); local view=chatView()
    view.last_state={vitals={psi={visible=true},web={visible=true}},equipment={items={}}}
    view:applyLayout(layout)
    local vitals_top=layout.window_height-view.vitals_right.height
    eq(view.equipment.y+view.equipment.height+12<=vitals_top,true)
    eq(view.hp.visible,true); eq(view.fatigue.visible,true); eq(view.carry.visible,true)
    eq(view.psi.visible and view.web.visible,false)
  end
end)

test("mapper stack has exact non-overlapping bounds across resolutions and vital states",function()
  local Layout=require("layout")
  local sizes={{1920,1080},{2560,1400},{1200,800},{1200,650},{1000,650}}
  local states={{false,false},{true,false},{false,true},{true,true}}
  for _,size in ipairs(sizes) do for _,flags in ipairs(states) do
    local layout=Layout.compute(size[1],size[2]); local view=chatView()
    view.last_state={vitals={psi={visible=flags[1]},web={visible=flags[2]}},equipment={items={}}}
    view:applyLayout(layout)
    local panel=view.right.height
    if view.room.visible then
      eq(view.room.height>=layout.lower_room_min_height,true)
      if view.mapper_frame.visible then eq(view.room.y+view.room.height<=view.mapper_frame.y,true) end
    end
    if view.mapper_frame.visible then
      eq(view.mapper_frame.height>=layout.lower_mapper_min_height,true)
      eq(view.mapper_frame.y+view.mapper_frame.height+layout.lower_mapper_gap,view.compass_area.y)
      eq(view.mapper_frame.y>=0,true)
    end
    eq(view.compass_area.y+view.compass_area.height<=view.utility_area.y,true)
    eq(view.utility_area.y+view.utility_area.height<=panel,true)
    for _,widget in ipairs({view.hp,view.fatigue,view.carry,view.room,view.compass_area,view.utility_area}) do
      if widget.visible then eq(widget.y>=0 and widget.y+widget.height<=panel,true) end
    end
  end end
end)

test("view centers the native map through its adapter boundary",function()
  local view=chatView(); local calls={}
  view:setMapCenterCallback(function(roomID) calls[#calls+1]=roomID; return true end)
  eq(view:centerMap(175),true); eq(calls[1],175)
end)

test("chat output colors its trusted prefix without printing HTML markup literally",function()
  local view=chatView()
  view:renderChat({{category="ROOM",timestamp="2026-08-31T20:12:00-04:00",line='Gia says, "hey"'}},{"ROOM"},"ALL")
  eq(#(view.chat_output.hechoes or {}),1)
  eq(view.chat_output.hechoes[1]:find("<span",1,true),nil)
  eq(view.chat_output.hechoes[1]:find("<",1,true),nil)
  eq(view.chat_output.hechoes[1],"#75857c[20:12]#r #d7d0bfROOM#r")
  eq(#view.chat_output.echoes,1)
  eq(view.chat_output.echoes[1]:find('Gia says, "hey"',1,true)~=nil,true)
end)

test("view owns a scrollable chat panel above the main console",function()
  local view=chatView()
  eq(view.chat_container~=nil,true); eq(view.chat_tabs~=nil,true); eq(view.chat_output~=nil,true)
  eq(view.chat_output.parent,view.chat_container); eq(view.chat_output.scrollBar,true); eq(view.chat_output.horizontalScrollBar,false)
end)

test("attribute strip spans the center header above the chatbox",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.attribute_strip.x,layout.left); eq(view.attribute_strip.y,0)
  eq(view.attribute_strip.width,layout.console_width); eq(view.attribute_strip.height,layout.header_height)
  eq(layout.attribute_strip_font>=10,true); eq(layout.attribute_strip_font<=14,true)
end)

test("chat panel occupies the center while side cards stay at the header",function()
  local layout=require("layout").compute(1920,1080); local view=chatView(); view:applyLayout(layout)
  eq(view.header.height,layout.header_height)
  eq(view.chat_container.x,layout.chat_x); eq(view.chat_container.y,layout.header_height)
  eq(view.chat_container.width,layout.chat_width); eq(view.chat_container.height,layout.chat_height)
  eq(view.identity.y,layout.header_height); eq(view.left.y,layout.header_height); eq(view.equipment.y,layout.header_height+layout.panel_padding)
end)

test("chat rendering keeps only the newest thousand and isolates untrusted text from color markup",function()
  local view=chatView(); view:applyLayout(require("layout").compute(1920,1080)); local entries={}
  for index=1,1001 do entries[index]={category="ROOM",timestamp="2026-08-31T13:00:00-04:00",line="line-"..index} end
  entries[1001].line="<b>owned &\n\27[31m"
  view:renderChat(entries,{"ROOM","QUEST<script>","EVENTS\n"},"ALL")
  eq(#view.chat_output.echoes,1000); eq(view.chat_output.echoes[1]:find("line-2",1,true)~=nil,true)
  local last=view.chat_output.echoes[#view.chat_output.echoes]
  eq(last:find("<b>owned &",1,true)~=nil,true); eq(last:find("\n\27",1,true),nil)
  eq(view.chat_output.hechoes[#view.chat_output.hechoes]:find("#75857c",1,true)~=nil,true)
end)

test("chat tabs stay inside narrow panels and expose deterministic overflow",function()
  local layout=require("layout").compute(280,700); local view=chatView(); view:applyLayout(layout); local selected
  view:setChatFilterCallback(function(category) selected=category end)
  view:renderChat({}, {"QUEST","EVENTS","QUEST<script>","LINE\nBREAK"}, "ALL")
  eq(table.concat(view.chat_filter_order,","),"ALL,ROOM,PRIVATE,ESP,DRAGON,CONTACT,STAFF,QUEST,EVENTS,QUEST<SCRIPT>,LINE\nBREAK")
  eq(#view.chat_overflow_categories>0,true)
  for _,button in ipairs(view.chat_buttons) do
    eq(button.x+button.width<=layout.chat_width,true); eq(tostring(button.message):find("<script>",1,true),nil)
  end
  local first=view.chat_overflow_categories[1]; view.chat_overflow_button.click(); eq(selected,first)
end)

test("chat wrap reflows on resize while preserving scroll intent and filter",function()
  local Layout=require("layout"); local wide=Layout.compute(1920,1080); local narrow=Layout.compute(1000,700); local view=chatView()
  view:applyLayout(wide); view:renderChat({
    {category="ESP",timestamp="2026-08-31T13:00:00-04:00",line=string.rep("long message ",30)},
    {category="ESP",timestamp="2026-08-31T13:01:00-04:00",line="newest"},
  },{"ESP"},"ESP")
  view.chat_output.currentScroll=0; view:applyLayout(narrow)
  eq(view.chat_output.wrap,narrow.chat_wrap_columns); eq(view.chat_output.scrollCalls[#view.chat_output.scrollCalls],0)
  eq(view.chat_active_filter,"ESP"); eq(#view.chat_output.echoes,2)
  view.chat_output.currentScroll=view.chat_output.lastLine; view:applyLayout(wide)
  eq(view.chat_output.wrap,wide.chat_wrap_columns); eq(view.chat_output.scrollCalls[#view.chat_output.scrollCalls],"bottom")
  eq(view.chat_active_filter,"ESP")
end)

test("chat reflow keeps the same wrapped entry visible while narrowing and widening",function()
  local Layout=require("layout"); local wide=Layout.compute(1920,1080); local narrow=Layout.compute(1000,700); local view=chatView(); local entries={}
  for index=1,20 do entries[index]={category="ESP",timestamp="2026-08-31T13:00:00-04:00",line=string.rep("entry-"..index.." ",40)} end
  view:applyLayout(wide); view:renderChat(entries,{"ESP"},"ESP")
  view.chat_output.currentScroll=view.chat_output.renderedEntries[10].first+1
  view:applyLayout(narrow)
  local narrowed=view.chat_output.renderedEntries[10]
  eq(view.chat_output.currentScroll>=narrowed.first and view.chat_output.currentScroll<=narrowed.last,true)
  view:applyLayout(wide)
  local widened=view.chat_output.renderedEntries[10]
  eq(view.chat_output.currentScroll>=widened.first and view.chat_output.currentScroll<=widened.last,true)
end)

test("chat wrap uses live MiniConsole metrics after resize and font application",function()
  local layout=require("layout").compute(1000,700); local view=chatView(); local output=view.chat_output
  output.metricWidth=12
  function output:calcFontSize() self.metricFontSeen=self.fontSize; return self.metricWidth,18 end
  function output:get_width() return layout.chat_width-(2*layout.chat_padding) end
  view:applyLayout(layout)
  eq(layout.chat_wrap_columns==52,false)
  eq(output.metricFontSeen,layout.chat_font)
  eq(output.wrap,52)

  local entries={}
  for index=1,20 do entries[index]={category="ESP",timestamp="2026-08-31T13:00:00-04:00",line=string.rep("entry-"..index.." ",40)} end
  view:renderChat(entries,{"ESP"},"ESP"); output.currentScroll=output.renderedEntries[10].first+1
  output.metricWidth=16; view:applyLayout(layout)
  local anchored=output.renderedEntries[10]
  eq(output.wrap,39); eq(output.currentScroll>=anchored.first and output.currentScroll<=anchored.last,true)
  output.currentScroll=output.lastLine; output.metricWidth=10; view:applyLayout(layout)
  eq(output.wrap,62); eq(output.scrollCalls[#output.scrollCalls],"bottom")
end)

test("chat wrap accepts legacy Geyser setters that return no value",function()
  local layout=require("layout").compute(1920,1080); local view=chatView()
  function view.chat_output:setWrap(value) self.wrap=value end
  local applied,err=view:applyChatWrap(layout)
  eq(applied,true); eq(err,nil); eq(view.chat_output.wrap,layout.chat_wrap_columns)
  eq(view.chat_wrap_columns,layout.chat_wrap_columns); eq(view.chat_font,layout.chat_font)
end)

test("chat wrap reports explicit Geyser setter failures",function()
  local layout=require("layout").compute(1920,1080); local view=chatView()
  function view.chat_output:setWrap() return nil,"manual wrap rejected" end
  local applied,err=view:applyChatWrap(layout)
  eq(applied,nil); eq(err,"manual wrap rejected")
end)
