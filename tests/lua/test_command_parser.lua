local Parser=require("command_parser")

local inventory={"Items carried:","  A wooden torch [1.0 lb].","  A wooden torch [0.1 lbs].","  A simple spear [0.5 lbs].","Your inventory totals 1.6 lbs.",">"}
local stat={"Body Armor: 4%.","OR:  18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","You are in the center of the area!","You are still protected by the 80 hour novice protection.","  ::: Equipment Readied :::","  A simple spear.","  A wooden shield.",">"}
local info={"You are Test Tester, a light boned and stocky bodied 28 year old Entropic Male young Monitanian.  You are 6'10\" and weigh 309 lbs.","HP: 201 of 201  Ftg:  69 of  69  Carry: 15.9 of 380.0 lbs."," Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Voi   Per   App","Good  Low   Fair  Fair  Fair  Good  Good  Good  Aver  Fair  Fair",">"}

test("parses inventory items without merging duplicates",function()
  local r=assert(Parser.parseInventory(inventory)); eq(#r.items,3); eq(r.items[1].name,"A wooden torch"); eq(r.items[2].weight,0.1); eq(r.total_weight,1.6)
end)
test("rejects incomplete inventory",function() eq(Parser.parseInventory({"Items carried:","  A torch [1.0 lb]."}),nil) end)
test("parses stat combat protection and readied equipment",function()
  local r=assert(Parser.parseStat(stat)); eq(r.body_armor,4); eq(r.or_rating,18); eq(r.dr,70); eq(r.move.current,6); eq(r.move.maximum,6); eq(r.damage_bonus,"Good/None"); eq(r.stance,"Aggressive"); eq(r.area_position,"center"); eq(r.novice_protected,true); eq(r.equipment[2],"A wooden shield")
end)
test("parses info physical data and all attributes",function()
  local r=assert(Parser.parseInfo(info)); eq(r.physical.age,28); eq(r.physical.sex,"Male"); eq(r.physical.height,"6'10\""); eq(r.physical.weight,309); eq(r.attributes.STR,"Good"); eq(r.attributes.APP,"Fair")
end)
test("detects completed command responses",function() eq(Parser.isComplete("inventory",inventory),true); eq(Parser.isComplete("inventory",{"Items carried:","Your inventory totals 0 lbs."}),false); eq(Parser.isComplete("stat",stat),true); eq(Parser.isComplete("info",info),true); eq(Parser.isComplete("info",{"You are Test"}),false) end)

return {inventory=inventory,stat=stat,info=info}
