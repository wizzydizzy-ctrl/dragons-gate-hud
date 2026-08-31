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
  eq(equipment:find("EQUIPMENT",1,true)~=nil,true); eq(equipment:find("WEALTH",1,true)~=nil,true)
end)
