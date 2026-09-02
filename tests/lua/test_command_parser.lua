local Parser=require("command_parser")

local inventory={"Items carried:","  A wooden torch [1.0 lb].","  A wooden torch [0.1 lbs].","  A simple spear [0.5 lbs].","Your inventory totals 1.6 lbs.",">"}
local stat={"Body Armor: 4%.","OR:  18  DR: 70  Move Rate: 6/6 UDs  Dam Bonus: Good/None  Stance: Aggressive","You are in the center of the area!","You are still protected by the 80 hour novice protection.","  ::: Equipment Readied :::","  A simple spear.","  A wooden shield.",">"}
local info={"You are Test Tester, a light boned and stocky bodied 28 year old Entropic Male young Monitanian.  You are 6'10\" and weigh 309 lbs.","HP: 201 of 201  Ftg:  69 of  69  Carry: 15.9 of 380.0 lbs."," Str   Int   Wis   Dex   Agi   Con   Cha   Wil   Voi   Per   App","Good  Low   Fair  Fair  Fair  Good  Good  Good  Aver  Fair  Fair",">"}
local religion={"You are a Novitiate follower of Unknown.","You are Balanced within your Entropic alignment.",">"}
local skills={"Skill                     Remain Level","Biting                    105    4","Clawing                   276    2","Pole Weapons               42    4","Identify Armor Quality    100    1",">"}
local time={"Current time is: Wed Sep  2 00:40:30 2026 EST.","It is now 3:22 am on the 4th day of the 8th month in the year 362.","You have been adventuring for 14 secs this session.",">"}

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
test("info parses from its data rows but collector completion waits for a prompt",function()
  local without_prompt={}; for i=1,#info-1 do without_prompt[i]=info[i] end
  local r=assert(Parser.parseInfo(without_prompt)); eq(r.attributes.STR,"Good"); eq(Parser.isComplete("info",without_prompt),false); eq(Parser.isComplete("info",info),true)
end)
test("info tolerates condition text appended to the physical sentence",function()
  local with_conditions={}; for i,line in ipairs(info) do with_conditions[i]=line end
  with_conditions[1]=with_conditions[1].." You are hungry. You are thirsty."
  local r=assert(Parser.parseInfo(with_conditions)); eq(r.physical.weight,309); eq(r.attributes.APP,"Fair")
end)
test("detects completed command responses",function() eq(Parser.isComplete("inventory",inventory),true); eq(Parser.isComplete("inventory",{"Items carried:","Your inventory totals 0 lbs."}),false); eq(Parser.isComplete("stat",stat),true); eq(Parser.isComplete("info",info),true); eq(Parser.isComplete("info",{"You are Test"}),false) end)
test("parses info religion rank deity balance and alignment",function()
  local r=assert(Parser.parseReligion(religion)); eq(r.rank,"Novitiate"); eq(r.deity,"Unknown"); eq(r.balance,"Balanced"); eq(r.alignment,"Entropic"); eq(Parser.isComplete("info religion",religion),true)
end)
test("parses every skill and ranks by level then lowest remaining uses",function()
  local r=assert(Parser.parseSkills(skills)); eq(#r.items,4)
  eq(r.items[1].name,"Pole Weapons"); eq(r.items[1].level,4); eq(r.items[1].remain,42)
  eq(r.items[2].name,"Biting"); eq(r.items[3].name,"Clawing"); eq(r.items[4].name,"Identify Armor Quality")
end)
test("skill parsing requires a header rows and final prompt",function()
  eq(Parser.parseSkills({"Skill Remain Level","Biting 100 1"}),nil)
  eq(Parser.parseSkills({"Biting 100 1",">"}),nil)
  eq(Parser.isComplete("skill",skills),true)
end)
test("skill parsing ignores a stale prompt before its header",function()
  local contaminated={"You are Balanced within your Entropic alignment.",">","Skill                     Remain Level","Biting                    105    4","Clawing                   276    2"}
  eq(Parser.parseSkills(contaminated),nil); contaminated[#contaminated+1]=">"
  local r=assert(Parser.parseSkills(contaminated)); eq(#r.items,2)
end)
test("parses game time and completes only at the prompt",function()
  local r=assert(Parser.parseTime(time)); eq(r.hour,3); eq(r.minute,22); eq(r.day,4); eq(r.month,8); eq(r.year,362)
  eq(Parser.parseTime({time[1],time[2]}),nil); eq(Parser.isComplete("time",time),true)
  local pm={time[1],"It is now 12:07 pm on the 4th day of the 8th month in the year 362.",time[3],">"}
  eq(assert(Parser.parseTime(pm)).hour,12)
  local midnight={time[1],"It is now 12:07 am on the 4th day of the 8th month in the year 362.",time[3],">"}
  eq(assert(Parser.parseTime(midnight)).hour,0)
end)

return {inventory=inventory,stat=stat,info=info,religion=religion,skills=skills,time=time}
