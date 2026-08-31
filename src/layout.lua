local Layout={}
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,math.floor(value+0.5))) end
local function metrics(width,height,layout)
  layout.body_font=clamp(width/100,16,22); layout.small_font=clamp((layout.body_font-2)*2,28,40); layout.heading_font=clamp(layout.body_font+5,21,27)
  layout.panel_padding=clamp(width/120,12,22); layout.gauge_height=clamp(layout.small_font+10,38,50); layout.row_gap=clamp(layout.body_font*.7,11,15)
  layout.title_height=layout.heading_font+30; layout.status_height=layout.body_font*4+40
  layout.room_height=layout.heading_font+layout.body_font*6+54; layout.exit_height=layout.small_font+16
  layout.identity_height=layout.heading_font+layout.body_font*3+48
  layout.inventory_font=clamp(layout.body_font-2,14,20); layout.inventory_row_height=layout.inventory_font+10
  layout.details_line_height=layout.body_font+6; layout.compass_font=clamp(layout.body_font,16,22); layout.compass_cell=layout.compass_font+14
  layout.utility_font=clamp(layout.body_font-4,12,18); layout.utility_height=layout.utility_font+12
  layout.bottom=math.max(layout.bottom,layout.small_font+16); layout.window_height=height
  return layout
end
function Layout.compute(width,height)
  width=tonumber(width) or 1200; height=tonumber(height) or 800
  if width>=1400 then return metrics(width,height,{mode="wide",left=clamp(width*.17,240,350),right=clamp(width*.13,190,270),top=74,bottom=38,show_character_rail=true,show_room_compass=height>=700,vitals_side="left"}) end
  if width>=1000 then return metrics(width,height,{mode="medium",left=clamp(width*.19,200,250),right=clamp(width*.15,150,200),top=66,bottom=36,show_character_rail=true,show_room_compass=height>=650,vitals_side="left"}) end
  return metrics(width,height,{mode="compact",left=0,right=0,top=116,bottom=58,show_character_rail=false,show_room_compass=false,vitals_side="compact"})
end
return Layout
