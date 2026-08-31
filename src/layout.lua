local Layout={}
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,math.floor(value+0.5))) end
local function metrics(width,layout)
  layout.body_font=clamp(width/100,16,22); layout.small_font=clamp(layout.body_font-2,14,20); layout.heading_font=clamp(layout.body_font+5,21,27)
  layout.panel_padding=clamp(width/120,12,22); layout.gauge_height=clamp(layout.body_font*1.7,30,38); layout.row_gap=clamp(layout.body_font*.7,11,15)
  return layout
end
function Layout.compute(width,height)
  width=tonumber(width) or 1200; height=tonumber(height) or 800
  if width>=1400 then return metrics(width,{mode="wide",left=clamp(width*.13,220,270),right=clamp(width*.17,280,350),top=74,bottom=38,show_character_rail=true,show_room_compass=height>=700}) end
  if width>=900 then return metrics(width,{mode="medium",left=0,right=clamp(width*.21,220,290),top=66,bottom=36,show_character_rail=false,show_room_compass=height>=650}) end
  return metrics(width,{mode="compact",left=0,right=0,top=116,bottom=58,show_character_rail=false,show_room_compass=false})
end
return Layout
