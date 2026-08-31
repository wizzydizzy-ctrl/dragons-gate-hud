local State = require("state")

test("normalizes supplied Dragons Gate GMCP values", function()
  local result = State.normalize({Char={Status={name="Test",surname="Tester",race="Monitanian",class="Fighter",alignment="entropy"},Vitals={hp=201,hp_max=201,fatigue=69,fatigue_max=69,carry=15.9,carry_max=380,weapon_readied=true,shield_readied=true,psi=0,psi_max=0,web=0,web_max=0}},Room={Info={name="Training Center.",num=199,area=1,environment="Plains/Grasslands",exits={"east","west"},flags={"indoor"}},Players={}}})
  eq(result.character.full_name, "Test Tester"); eq(result.vitals.hp.percent, 100); eq(result.vitals.carry.percent, 4.2)
  eq(result.vitals.weapon_readied, true); eq(result.vitals.shield_readied, true); eq(result.vitals.psi.visible, false)
  eq(result.room.exits[2], "west")
end)

test("clamps percentages and tolerates missing GMCP", function()
  local result = State.normalize({Char={Vitals={hp=150,hp_max=100,fatigue=-2,fatigue_max=100}}})
  eq(result.vitals.hp.percent, 100); eq(result.vitals.fatigue.percent, 0); eq(result.character.full_name, "Unknown")
end)

test("GMCP wins while parsed commands fill absent character data",function()
  local result=State.normalize({Char={Status={name="Live",race="Monitanian"},Vitals={carry=15.9,carry_max=380}}},{info={character={name="Parsed"},physical={age=28,sex="Male"},attributes={STR="Good"}},religion={rank="Novitiate",deity="Unknown",balance="Balanced",alignment="Entropic"},stat={body_armor=4,stance="Aggressive",equipment={"A simple spear"}},inventory={items={{name="A torch",weight=1}},total_weight=1}})
  eq(result.character.name,"Live"); eq(result.character.physical.age,28); eq(result.character.religion,"Novitiate"); eq(result.character.deity,"Unknown"); eq(result.character.religious_balance,"Balanced"); eq(result.attributes.STR,"Good"); eq(result.combat.stance,"Aggressive"); eq(result.equipment.items[1],"A simple spear"); eq(result.inventory.total_weight,1); eq(result.vitals.carry.current,15.9)
end)

test("unknown parsed fields remain absent",function()
  local result=State.normalize({},{}); eq(result.combat.body_armor,nil); eq(result.character.religion,nil); eq(result.character.deity,nil); eq(#result.inventory.items,0)
end)
