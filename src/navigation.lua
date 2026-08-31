local Navigation={}
Navigation.directions={
  {key="northwest",label="NW",command="northwest",row=1,col=1},{key="north",label="N",command="north",row=1,col=2},{key="northeast",label="NE",command="northeast",row=1,col=3},
  {key="west",label="W",command="west",row=2,col=1},{key="east",label="E",command="east",row=2,col=3},
  {key="southwest",label="SW",command="southwest",row=3,col=1},{key="south",label="S",command="south",row=3,col=2},{key="southeast",label="SE",command="southeast",row=3,col=3}}
Navigation.utilities={{label="GO PORTAL",command="go portal"},{label="GO DOOR",command="go door"},{label="GO GATE",command="go gate"},{label="GO ARCH",command="go arch"}}
local aliases={n="north",ne="northeast",e="east",se="southeast",s="south",sw="southwest",w="west",nw="northwest"}
for _,direction in ipairs(Navigation.directions) do aliases[direction.key]=direction.key end
function Navigation.availability(exits)
  local result={}; for _,direction in ipairs(Navigation.directions) do result[direction.key]=false end; for _,value in ipairs(exits or {}) do local key=aliases[tostring(value):lower():match("^%s*(.-)%s*$")]; if key then result[key]=true end end; return result
end
return Navigation
