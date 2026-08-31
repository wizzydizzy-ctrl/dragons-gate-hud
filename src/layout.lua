local Layout={}
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,math.floor(value+0.5))) end
function Layout.compute(width,height)
  width=tonumber(width) or 1200; height=tonumber(height) or 800
  if width>=1400 then return {mode="wide",left=clamp(width*.13,220,270),right=clamp(width*.17,280,350),top=74,bottom=38,show_character_rail=true,show_room_compass=height>=700,font_scale=width>=2200 and 1.15 or 1} end
  if width>=900 then return {mode="medium",left=0,right=clamp(width*.21,220,290),top=66,bottom=36,show_character_rail=false,show_room_compass=height>=650,font_scale=.95} end
  return {mode="compact",left=0,right=0,top=116,bottom=58,show_character_rail=false,show_room_compass=false,font_scale=.9}
end
return Layout
