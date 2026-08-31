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
